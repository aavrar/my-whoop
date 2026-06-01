import Foundation
import GRDB

extension WhoopStore {
    /// Rows stored with a fast strap RTC land far in the future. Shift them by `(wall - maxFutureTs)`
    /// so streams and on-device compute line up with calendar days. Idempotent once corrected.
    @discardableResult
    public func repairFutureTimestamps(deviceId: String, wallNow: Int) async throws -> Int {
        let threshold = wallNow + HistoricalTimestampRepair.futureSlopSeconds
        return try syncWrite { db in
            var total = 0
            for table in HistoricalTimestampRepair.streamTables {
                guard let maxTs = try Int.fetchOne(
                    db, sql: "SELECT MAX(ts) FROM \(table) WHERE deviceId = ? AND ts > ?",
                    arguments: [deviceId, threshold]
                ), maxTs > threshold else { continue }
                let fix = wallNow - maxTs
                try db.execute(
                    sql: "UPDATE \(table) SET ts = ts + ? WHERE deviceId = ? AND ts > ?",
                    arguments: [fix, deviceId, threshold]
                )
                total += db.changesCount
            }
            return total
        }
    }
}

/// Shared threshold with WhoopProtocol's ingest normalizer (duplicated constant to avoid a package cycle).
enum HistoricalTimestampRepair {
    static let futureSlopSeconds = 7 * 86_400
    static let streamTables = [
        "hrSample", "rrInterval", "event", "battery",
        "spo2Sample", "skinTempSample", "respSample", "gravitySample",
    ]
}
