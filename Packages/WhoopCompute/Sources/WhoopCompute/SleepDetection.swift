import Foundation

public enum SleepDetection {
    static let gravityStillThresholdG: Double = 0.01
    static let stillWindowMin: Double = 15
    static let stillFraction: Double = 0.70
    static let maxGapS: Double = 20 * 60
    static let mergeMinS: Double = 15 * 60
    static let minSleepS: Double = 60 * 60
    static let hrSleepBaselineMult: Double = 1.05
    static let hrRefineMinSamples = 30

    public struct GravitySample {
        public let ts: Int
        public let x: Double
        public let y: Double
        public let z: Double
        public init(ts: Int, x: Double, y: Double, z: Double) {
            self.ts = ts; self.x = x; self.y = y; self.z = z
        }
    }

    struct Run {
        var stage: String  // "sleep" | "active"
        var start: Int
        var end: Int
    }

    public static func detect(
        gravity: [GravitySample],
        hr: [(ts: Int, bpm: Int)]
    ) -> [(start: Int, end: Int)] {
        guard gravity.count >= 2 else { return detectFromHR(hr: hr) }
        let sorted = gravity.sorted { $0.ts < $1.ts }

        let deltas = gravityDeltas(sorted)
        let flags = classifyStill(sorted, deltas: deltas)
        var runs = buildRuns(sorted, flags: flags)
        runs = mergePeriods(runs)

        let baseline = hrBaseline(hr)
        let minSleepSInt = Int(minSleepS)

        return runs.compactMap { run in
            guard run.stage == "sleep" else { return nil }
            guard (run.end - run.start) > minSleepSInt else { return nil }
            guard confirmWithHR(run: run, hr: hr, baseline: baseline) else { return nil }
            return (run.start, run.end)
        }
    }

    static func gravityDeltas(_ samples: [GravitySample]) -> [Double] {
        var deltas: [Double] = [0.0]
        for i in 1..<samples.count {
            let prev = samples[i-1]
            let curr = samples[i]
            let d = sqrt(
                pow(curr.x - prev.x, 2) +
                pow(curr.y - prev.y, 2) +
                pow(curr.z - prev.z, 2)
            )
            deltas.append(d)
        }
        return deltas
    }

    static func classifyStill(_ samples: [GravitySample], deltas: [Double]) -> [Bool] {
        let n = samples.count
        guard n >= 2 else { return Array(repeating: false, count: n) }

        let times = samples.map { Double($0.ts) }
        let medianInterval = medianIntervalS(times)
        let half = max(2, Int((stillWindowMin * 60) / medianInterval) / 2)

        return (0..<n).map { i in
            let lo = max(0, i - half)
            let hi = min(n, i + half + 1)
            let window = Array(deltas[lo..<hi])
            let stillCount = window.filter { $0 < gravityStillThresholdG }.count
            return Double(stillCount) / Double(window.count) >= stillFraction
        }
    }

    static func medianIntervalS(_ times: [Double]) -> Double {
        guard times.count >= 2 else { return 60.0 }
        let gaps = zip(times, times.dropFirst())
            .map { $1 - $0 }
            .filter { $0 > 0 && $0 < 300 }
            .sorted()
        guard !gaps.isEmpty else { return 60.0 }
        return max(gaps[gaps.count / 2], 1.0)
    }

    static func buildRuns(_ samples: [GravitySample], flags: [Bool]) -> [Run] {
        let n = samples.count
        guard n > 0 else { return [] }

        var runs: [Run] = []
        var runStart = 0

        for i in 1...n {
            let atEnd = i == n
            let close: Bool
            if atEnd {
                close = true
            } else {
                let classChanged = flags[i] != flags[runStart]
                let gapExceeded = Double(samples[i].ts - samples[i-1].ts) > maxGapS
                close = classChanged || gapExceeded
            }
            if close {
                runs.append(Run(
                    stage: flags[runStart] ? "sleep" : "active",
                    start: samples[runStart].ts,
                    end: samples[i-1].ts
                ))
                runStart = i
            }
        }
        return runs
    }

    static func mergePeriods(_ periods: [Run]) -> [Run] {
        guard !periods.isEmpty else { return [] }
        var pending = periods
        var merged: [Run] = []
        var i = 0

        while i < pending.count {
            let curr = pending[i]
            let tooShort = Double(curr.end - curr.start) < mergeMinS

            if !tooShort {
                merged.append(curr)
                i += 1
                continue
            }

            let hasPrev = i > 0 && !merged.isEmpty
            let hasNext = i + 1 < pending.count
            let bridgesSame = hasPrev && hasNext &&
                pending[i-1].stage == pending[i+1].stage

            if bridgesSame {
                let prev = merged.removeLast()
                merged.append(Run(stage: prev.stage, start: prev.start, end: pending[i+1].end))
                i += 2
            } else if hasNext {
                pending[i+1] = Run(stage: pending[i+1].stage, start: curr.start, end: pending[i+1].end)
                i += 1
            } else if hasPrev {
                let prev = merged.removeLast()
                merged.append(Run(stage: prev.stage, start: prev.start, end: curr.end))
                i += 1
            } else {
                i += 1
            }
        }
        return merged
    }

    static func hrBaseline(_ hr: [(ts: Int, bpm: Int)]) -> Double? {
        let vals = hr.map { Double($0.bpm) }.sorted()
        guard !vals.isEmpty else { return nil }
        return vals[vals.count / 2]
    }

    static func confirmWithHR(run: Run, hr: [(ts: Int, bpm: Int)], baseline: Double?) -> Bool {
        guard let baseline else { return true }
        let seg = hr.filter { $0.ts >= run.start && $0.ts <= run.end }
        guard seg.count >= hrRefineMinSamples else { return true }
        let mean = Double(seg.map { $0.bpm }.reduce(0, +)) / Double(seg.count)
        return mean <= baseline * hrSleepBaselineMult
    }

    // Fallback when no gravity data: find the longest low-HR window in the input range.
    // Uses a permissive threshold (115% of median) and allows up to 30-min gaps so BLE
    // disconnects during sleep don't fragment the window. Returns at most one window.
    static func detectFromHR(hr: [(ts: Int, bpm: Int)]) -> [(start: Int, end: Int)] {
        guard hr.count >= hrRefineMinSamples else { return [] }

        let sorted = hr.sorted { $0.ts < $1.ts }
        let allBpm = sorted.map { Double($0.bpm) }.sorted()
        let median = allBpm[allBpm.count / 2]
        let threshold = median * 1.15   // more permissive than confirmWithHR's 1.05

        // Allow up to 30-min gaps (BLE disconnects during sleep are common).
        let maxGapSec = 30 * 60
        var windows: [(start: Int, end: Int)] = []
        var winStart: Int? = nil
        var winEnd: Int = 0

        for i in 0..<sorted.count {
            let s = sorted[i]
            let gap = i > 0 ? (s.ts - sorted[i-1].ts) : 0
            let lowHR = Double(s.bpm) <= threshold
            if lowHR && (winStart == nil || gap <= maxGapSec) {
                if winStart == nil { winStart = s.ts }
                winEnd = s.ts
            } else {
                if let ws = winStart, (winEnd - ws) >= Int(minSleepS) {
                    windows.append((ws, winEnd))
                }
                winStart = lowHR ? s.ts : nil
                winEnd = s.ts
            }
        }
        if let ws = winStart, (winEnd - ws) >= Int(minSleepS) {
            windows.append((ws, winEnd))
        }

        guard let best = windows.max(by: { ($0.end - $0.start) < ($1.end - $1.start) }) else {
            return []
        }
        return [best]
    }
}
