import Foundation
import WhoopStore
import WhoopProtocol

public struct EngineProfile {
    public var age: Int
    public var sex: String
    public var weightKg: Double
    public var heightCm: Double
    public init(age: Int = 30, sex: String = "male", weightKg: Double = 70, heightCm: Double = 170) {
        self.age = age; self.sex = sex; self.weightKg = weightKg; self.heightCm = heightCm
    }
}

public actor OnDeviceEngine {
    private let store: WhoopStore
    private let deviceId: String
    private var profile: EngineProfile = EngineProfile()

    static let lookbackDays = 30
    static let streamLimitPerDay = 200_000

    public init(store: WhoopStore, deviceId: String) {
        self.store = store
        self.deviceId = deviceId
    }

    public func setProfile(_ p: EngineProfile) {
        profile = p
    }

    // MARK: - Public entry point

    /// Compute metrics for the last `days` calendar days and upsert into WhoopStore.
    /// Skips days already populated (daily row exists with non-nil recovery), unless `force` is true.
    public func computeRecent(days: Int = 7, force: Bool = false) async {
        let cal = Calendar(identifier: .gregorian)
        let tz  = TimeZone(identifier: "UTC")!
        var calUTC = cal
        calUTC.timeZone = tz

        // Use the latest HR timestamp as the reference date so the engine works
        // even when the band's internal clock is behind wall-clock time (common on first
        // pair — historical frames carry device-epoch timestamps, not wall-clock).
        let latestHRTs = (try? await store.latestHRSampleTs(deviceId: deviceId)) ?? Int(Date().timeIntervalSince1970)
        let now = Date(timeIntervalSince1970: TimeInterval(latestHRTs))
        let fmt = DateFormatter()
        fmt.calendar = calUTC
        fmt.timeZone = tz
        fmt.dateFormat = "yyyy-MM-dd"

        var baselines = await loadBaselines()

        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calUTC.date(byAdding: .day, value: -offset, to: now) else { continue }
            let dayStr = fmt.string(from: day)

            if !force,
               let existing = try? await store.dailyMetrics(deviceId: deviceId, from: dayStr, to: dayStr).first,
               existing.recovery != nil {
                continue
            }

            await computeDay(dayStr: dayStr, cal: calUTC, fmt: fmt, baselines: &baselines)
        }
    }

    // MARK: - Per-day computation

    private func computeDay(dayStr: String, cal: Calendar, fmt: DateFormatter, baselines: inout [String: BaselineState]) async {
        guard let dayDate = fmt.date(from: dayStr) else { return }

        let sleepSearchStart = Int(dayDate.addingTimeInterval(-14 * 3600).timeIntervalSince1970)
        let sleepSearchEnd   = Int(dayDate.addingTimeInterval(14 * 3600).timeIntervalSince1970)

        guard let grav = try? await store.gravitySamples(deviceId: deviceId, from: sleepSearchStart, to: sleepSearchEnd, limit: Self.streamLimitPerDay),
              let hr   = try? await store.hrSamples(deviceId: deviceId, from: sleepSearchStart - 86400, to: sleepSearchEnd, limit: Self.streamLimitPerDay),
              let rr   = try? await store.rrIntervals(deviceId: deviceId, from: sleepSearchStart, to: sleepSearchEnd, limit: Self.streamLimitPerDay)
        else { return }

        let gravityInput: [SleepDetection.GravitySample] = grav.map {
            SleepDetection.GravitySample(ts: $0.ts, x: $0.x, y: $0.y, z: $0.z)
        }
        let hrInput  = hr.map  { (ts: $0.ts, bpm: $0.bpm) }
        let rrInput  = rr.map  { (ts: $0.ts, rrMs: $0.rrMs) }

        // Manual override: find any session the user edited for this day.
        let overrideSession: CachedSleepSession? = (try? await store.sleepSessions(
            deviceId: deviceId, from: sleepSearchStart, to: sleepSearchEnd, limit: 10))?
            .first(where: { $0.isManualOverride })

        // Determine sleep runs: override window or auto-detected.
        let rawRuns: [(start: Int, end: Int)]
        if let s = overrideSession {
            rawRuns = [(s.startTs, s.endTs)]
        } else {
            rawRuns = SleepDetection.detect(gravity: gravityInput, hr: hrInput)
        }

        // Group runs within 30 min of each other, pick the group with the most sleep time.
        let groups = groupRuns(rawRuns, maxGapSec: 1800)
        guard let bestGroup = groups.max(by: {
            $0.reduce(0) { $0 + $1.end - $1.start } < $1.reduce(0) { $0 + $1.end - $1.start }
        }) else {
            let dayStart = Int(dayDate.timeIntervalSince1970)
            let dayEnd   = Int(dayDate.addingTimeInterval(86400).timeIntervalSince1970)
            let strainHR = hrInput.filter { $0.ts >= dayStart && $0.ts <= dayEnd }
            let rhr = baselines[BaselineMetric.restingHr.rawValue].map { Int($0.baseline) } ?? 55
            let strain = Strain.compute(hr: strainHR, restingHr: rhr, age: profile.age, sex: profile.sex)
            let needMin = SleepNeed.need(strain: strain, recovery: nil)
            let metric = DailyMetric(day: dayStr, totalSleepMin: nil, efficiency: nil, deepMin: nil,
                                     remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil,
                                     avgHrv: nil, recovery: nil, strain: strain, exerciseCount: nil,
                                     sleepNeedMin: needMin)
            try? await store.upsertDailyMetrics([metric], deviceId: deviceId)
            return
        }

        let sleepRun = (start: bestGroup.first!.start, end: bestGroup.last!.end)

        // Stages: use pre-computed stages from a manual override (editor already staged
        // each sub-segment correctly). Otherwise stage each sub-run independently so
        // a brief wake gap (bathroom trip) doesn't contaminate the adjacent sleep windows.
        let stages: [StageSegment]
        if let override = overrideSession, let json = override.stagesJSON,
           let decoded = decodeStages(json), !decoded.isEmpty {
            stages = decoded
        } else {
            stages = stageRuns(bestGroup, gravity: gravityInput, hr: hrInput, rr: rrInput)
        }

        let resting = RestingHR.compute(hr: hrInput, sleepStart: sleepRun.start, sleepEnd: sleepRun.end)
        let avgHRV  = HRV.nightlyRMSSD(rr: rrInput, sleepStart: sleepRun.start, sleepEnd: sleepRun.end, stages: stages)

        let session = ComputedSleepSession(
            startTs: sleepRun.start, endTs: sleepRun.end,
            efficiency: efficiency(stages: stages, start: sleepRun.start, end: sleepRun.end),
            restingHr: resting, avgHrv: avgHRV, stages: stages
        )

        let sleepMinutes = stageDuration(stages, stage: nil, start: sleepRun.start, end: sleepRun.end) / 60
        let deepMin   = stageDuration(stages, stage: "deep") / 60
        let remMin    = stageDuration(stages, stage: "rem")  / 60
        let lightMin  = stageDuration(stages, stage: "light") / 60
        let disturbances = countDisturbances(stages: stages)

        let nowTs = Int(Date().timeIntervalSince1970)

        if let hrv = avgHRV {
            let cfg = defaultConfigs[.hrv]!
            baselines[BaselineMetric.hrv.rawValue] = Baselines.update(
                state: baselines[BaselineMetric.hrv.rawValue], value: hrv, cfg: cfg, nowTs: nowTs)
        }
        if let rhr = resting {
            let cfg = defaultConfigs[.restingHr]!
            baselines[BaselineMetric.restingHr.rawValue] = Baselines.update(
                state: baselines[BaselineMetric.restingHr.rawValue], value: Double(rhr), cfg: cfg, nowTs: nowTs)
        }

        await saveBaselines(baselines)

        let recovery: Double?
        if let hrv = avgHRV, let rhr = resting,
           let hrvBase = baselines[BaselineMetric.hrv.rawValue],
           let rhrBase = baselines[BaselineMetric.restingHr.rawValue] {
            let inputs = Recovery.Inputs(
                hrv: hrv, restingHr: Double(rhr),
                sleepEfficiency: session.efficiency, resp: nil
            )
            recovery = Recovery.score(inputs: inputs, hrv: hrvBase, restingHr: rhrBase, resp: nil)
        } else {
            recovery = nil
        }

        let dayStart = Int(dayDate.timeIntervalSince1970)
        let dayEnd   = Int(dayDate.addingTimeInterval(86400).timeIntervalSince1970)
        let rhrForStrain = resting ?? Int(baselines[BaselineMetric.restingHr.rawValue]?.baseline ?? 55)
        let strainHR = hrInput.filter { $0.ts >= dayStart && $0.ts <= dayEnd }
        let strain = Strain.compute(hr: strainHR, restingHr: rhrForStrain, age: profile.age, sex: profile.sex)

        let respSamples = (try? await store.respSamples(deviceId: deviceId, from: sleepRun.start, to: sleepRun.end, limit: Self.streamLimitPerDay)) ?? []
        let respRateBpm: Double? = respSamples.isEmpty ? nil : {
            let vals = respSamples.map { Double($0.raw) / 10.0 }.filter { $0 > 4 && $0 < 40 }
            return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        }()

        let skinSamples = (try? await store.skinTempSamples(deviceId: deviceId, from: sleepRun.start, to: sleepRun.end, limit: Self.streamLimitPerDay)) ?? []
        let skinTempDevC: Double? = skinSamples.isEmpty ? nil : {
            let vals = skinSamples.map { Double($0.raw) }.filter { $0 > 0 }
            guard !vals.isEmpty else { return nil }
            let mean = vals.reduce(0, +) / Double(vals.count)
            let baselineKey = "skinTempBaseline_\(deviceId)"
            let baseline = UserDefaults.standard.double(forKey: baselineKey)
            if baseline == 0 {
                UserDefaults.standard.set(mean, forKey: baselineKey)
                return 0.0
            }
            return mean - baseline
        }()

        let cals = Calories.estimate(
            hr: hrInput,
            age: profile.age,
            sex: profile.sex,
            weightKg: profile.weightKg,
            dayStartTs: sleepRun.end,
            dayEndTs: dayEnd
        )

        let needMin = SleepNeed.need(strain: strain, recovery: recovery)

        let cachedSession = CachedSleepSession(
            startTs: session.startTs, endTs: session.endTs,
            efficiency: session.efficiency,
            restingHr: session.restingHr,
            avgHrv: session.avgHrv,
            stagesJSON: encodeStages(session.stages),
            isManualOverride: overrideSession != nil   // preserve the flag
        )
        try? await store.upsertSleepSessions([cachedSession], deviceId: deviceId)

        let metric = DailyMetric(
            day: dayStr,
            totalSleepMin: sleepMinutes > 0 ? sleepMinutes : nil,
            efficiency: session.efficiency,
            deepMin: deepMin > 0 ? deepMin : nil,
            remMin: remMin > 0 ? remMin : nil,
            lightMin: lightMin > 0 ? lightMin : nil,
            disturbances: disturbances,
            restingHr: resting,
            avgHrv: avgHRV,
            recovery: recovery,
            strain: strain,
            exerciseCount: nil,
            skinTempDevC: skinTempDevC,
            respRateBpm: respRateBpm,
            calories: cals > 0 ? cals : nil,
            sleepNeedMin: needMin
        )
        try? await store.upsertDailyMetrics([metric], deviceId: deviceId)
    }

    // MARK: - Baseline I/O

    private func loadBaselines() async -> [String: BaselineState] {
        guard let stored = try? await store.readBaselines(deviceId: deviceId) else { return [:] }
        var result: [String: BaselineState] = [:]
        for b in stored {
            result[b.metric] = BaselineState(
                baseline: b.baseline, spread: b.spread,
                nValid: b.nValid, lastUpdatedTs: b.lastUpdatedTs
            )
        }
        return result
    }

    private func saveBaselines(_ baselines: [String: BaselineState]) async {
        for (metric, state) in baselines {
            let stored = StoredBaseline(
                metric: metric, baseline: state.baseline, spread: state.spread,
                nValid: state.nValid, lastUpdatedTs: state.lastUpdatedTs
            )
            try? await store.upsertBaseline(stored, deviceId: deviceId)
        }
    }

    // MARK: - Helpers

    private func efficiency(stages: [StageSegment], start: Int, end: Int) -> Double {
        let inBed = Double(end - start)
        guard inBed > 0 else { return 0 }
        let wakeSecs = stages.filter { $0.stage == "wake" }.map { Double($0.end - $0.start) }.reduce(0, +)
        return min(1.0, max(0, (inBed - wakeSecs) / inBed))
    }

    private func stageDuration(_ stages: [StageSegment], stage: String?, start: Int = 0, end: Int = Int.max) -> Double {
        if let stage {
            return stages.filter { $0.stage == stage }.map { Double($0.end - $0.start) }.reduce(0, +)
        }
        return Double(end - start)
    }

    private func countDisturbances(stages: [StageSegment]) -> Int {
        var count = 0
        var prev: String? = nil
        for seg in stages {
            if seg.stage == "wake" && prev != nil && prev != "wake" { count += 1 }
            prev = seg.stage
        }
        return count
    }

    private func encodeStages(_ stages: [StageSegment]) -> String? {
        guard let data = try? JSONEncoder().encode(stages) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeStages(_ json: String) -> [StageSegment]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([StageSegment].self, from: data)
    }

    // Group sleep runs where consecutive runs are within maxGapSec of each other.
    private func groupRuns(_ runs: [(start: Int, end: Int)], maxGapSec: Int) -> [[(start: Int, end: Int)]] {
        guard !runs.isEmpty else { return [] }
        let sorted = runs.sorted { $0.start < $1.start }
        var groups: [[(start: Int, end: Int)]] = [[sorted[0]]]
        for i in 1..<sorted.count {
            if sorted[i].start - sorted[i-1].end <= maxGapSec {
                groups[groups.count - 1].append(sorted[i])
            } else {
                groups.append([sorted[i]])
            }
        }
        return groups
    }

    // Stage each run independently and insert "wake" segments for the gaps between them.
    // This prevents a brief bathroom-trip wake from contaminating staging of adjacent sleep.
    private func stageRuns(_ runs: [(start: Int, end: Int)],
                            gravity: [SleepDetection.GravitySample],
                            hr: [(ts: Int, bpm: Int)],
                            rr: [(ts: Int, rrMs: Int)]) -> [StageSegment] {
        let sorted = runs.sorted { $0.start < $1.start }
        var all: [StageSegment] = []
        for i in 0..<sorted.count {
            let run = sorted[i]
            let sub = SleepStaging.stage(sleepStart: run.start, sleepEnd: run.end,
                                         gravity: gravity, hr: hr, rr: rr)
            all.append(contentsOf: sub)
            if i < sorted.count - 1 {
                let gapEnd = sorted[i + 1].start
                if gapEnd > run.end {
                    all.append(StageSegment(start: run.end, end: gapEnd, stage: "wake"))
                }
            }
        }
        return all
    }
}
