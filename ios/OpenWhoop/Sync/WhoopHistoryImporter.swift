import Foundation
import WhoopStore

@MainActor
final class WhoopHistoryImporter {
    private let store: WhoopStore
    private let deviceId: String

    init(store: WhoopStore, deviceId: String) {
        self.store = store
        self.deviceId = deviceId
    }

    // MARK: - Public entry point

    /// Returns (imported, skipped) counts.
    func importCycles(from url: URL) async throws -> (imported: Int, skipped: Int) {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return (0, 0) }

        let headers = parseCSVRow(lines[0])
        var imported = 0
        var skipped  = 0

        for line in lines.dropFirst() {
            let cols = parseCSVRow(line)
            guard cols.count == headers.count else { continue }
            let row = Dictionary(uniqueKeysWithValues: zip(headers, cols))

            guard let metric = buildDailyMetric(row: row) else { skipped += 1; continue }

            // Never overwrite a row that already has on-device computed data
            if let existing = try? await store.dailyMetrics(deviceId: deviceId,
                                                             from: metric.day, to: metric.day).first,
               existing.recovery != nil {
                skipped += 1; continue
            }

            try? await store.upsertDailyMetrics([metric], deviceId: deviceId)

            // Also create a sleep session if sleep onset/offset are present
            if let session = buildSleepSession(row: row, daily: metric) {
                try? await store.upsertSleepSessions([session], deviceId: deviceId)
            }

            imported += 1
        }

        return (imported, skipped)
    }

    // MARK: - Row builders

    private func buildDailyMetric(row: [String: String]) -> DailyMetric? {
        guard let startStr = row["Cycle start time"], !startStr.isEmpty,
              let tzStr    = row["Cycle timezone"],   !tzStr.isEmpty else { return nil }

        let tz = parseTimezone(tzStr)
        guard let startDate = parseDate(startStr, tz: tz) else { return nil }
        let day = utcDay(from: startDate)

        let recovery   = dbl(row["Recovery score %"]).map { $0 / 100.0 }
        let restingHr  = int(row["Resting heart rate (bpm)"])
        let avgHrv     = dbl(row["Heart rate variability (ms)"])
        let strain     = dbl(row["Day Strain"])
        let calories   = dbl(row["Energy burned (cal)"])
        let sleepMin   = dbl(row["Asleep duration (min)"])
        let efficiency = dbl(row["Sleep efficiency %"]).map { $0 / 100.0 }
        let deepMin    = dbl(row["Deep (SWS) duration (min)"])
        let remMin     = dbl(row["REM duration (min)"])
        let lightMin   = dbl(row["Light sleep duration (min)"])
        let spo2       = dbl(row["Blood oxygen %"])
        let resp       = dbl(row["Respiratory rate (rpm)"])
        let needMin    = dbl(row["Sleep need (min)"])

        // Skin temp stored as absolute celsius; we track deviation as 0 on first import
        // (baseline gets established from the first value encountered in sequence)
        let skinTempDev: Double? = nil

        // Skip completely empty rows (e.g. current in-progress cycle)
        if recovery == nil && strain == nil && sleepMin == nil { return nil }

        return DailyMetric(
            day: day,
            totalSleepMin: sleepMin,
            efficiency: efficiency,
            deepMin: deepMin,
            remMin: remMin,
            lightMin: lightMin,
            disturbances: nil,
            restingHr: restingHr,
            avgHrv: avgHrv,
            recovery: recovery,
            strain: strain,
            exerciseCount: nil,
            spo2Pct: spo2,
            skinTempDevC: skinTempDev,
            respRateBpm: resp,
            calories: calories,
            sleepNeedMin: needMin
        )
    }

    private func buildSleepSession(row: [String: String], daily: DailyMetric) -> CachedSleepSession? {
        guard let onsetStr = row["Sleep onset"],  !onsetStr.isEmpty,
              let wakeStr  = row["Wake onset"],   !wakeStr.isEmpty,
              let tzStr    = row["Cycle timezone"] else { return nil }

        let tz = parseTimezone(tzStr)
        guard let onset = parseDate(onsetStr, tz: tz),
              let wake  = parseDate(wakeStr,  tz: tz) else { return nil }

        let startTs = Int(onset.timeIntervalSince1970)
        let endTs   = Int(wake.timeIntervalSince1970)
        guard endTs > startTs else { return nil }

        return CachedSleepSession(
            startTs: startTs,
            endTs: endTs,
            efficiency: daily.efficiency,
            restingHr: daily.restingHr,
            avgHrv: daily.avgHrv,
            stagesJSON: nil  // stage segments not available from CSV export
        )
    }

    // MARK: - Parsing helpers

    private func parseTimezone(_ s: String) -> TimeZone {
        let stripped = s.replacingOccurrences(of: "UTC", with: "")
        if stripped.isEmpty { return TimeZone(identifier: "UTC")! }
        return TimeZone(identifier: "GMT\(stripped)") ?? TimeZone(identifier: "UTC")!
    }

    private func parseDate(_ s: String, tz: TimeZone) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = tz
        return fmt.date(from: s.trimmingCharacters(in: .whitespaces))
    }

    private func utcDay(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private func dbl(_ s: String?) -> Double? {
        guard let s, !s.isEmpty else { return nil }
        return Double(s.trimmingCharacters(in: .whitespaces))
    }

    private func int(_ s: String?) -> Int? {
        guard let s, !s.isEmpty else { return nil }
        return Int(s.trimmingCharacters(in: .whitespaces))
    }

    /// Minimal CSV row parser — handles quoted fields with embedded commas.
    private func parseCSVRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields
    }
}
