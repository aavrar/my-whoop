import Foundation
import GRDB

public struct StoredBaseline: Equatable {
    public let metric: String
    public let baseline: Double
    public let spread: Double
    public let nValid: Int
    public let lastUpdatedTs: Int

    public init(metric: String, baseline: Double, spread: Double, nValid: Int, lastUpdatedTs: Int) {
        self.metric = metric; self.baseline = baseline; self.spread = spread
        self.nValid = nValid; self.lastUpdatedTs = lastUpdatedTs
    }
}

extension WhoopStore {
    public func upsertBaseline(_ b: StoredBaseline, deviceId: String) async throws {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO baseline (deviceId, metric, baseline, spread, nValid, lastUpdatedTs)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(deviceId, metric) DO UPDATE SET
                    baseline = excluded.baseline,
                    spread = excluded.spread,
                    nValid = excluded.nValid,
                    lastUpdatedTs = excluded.lastUpdatedTs
                """, arguments: [deviceId, b.metric, b.baseline, b.spread, b.nValid, b.lastUpdatedTs])
        }
    }

    public func readBaselines(deviceId: String) async throws -> [StoredBaseline] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT metric, baseline, spread, nValid, lastUpdatedTs FROM baseline
                WHERE deviceId = ?
                """, arguments: [deviceId])
                .map {
                    StoredBaseline(metric: $0["metric"], baseline: $0["baseline"],
                                   spread: $0["spread"], nValid: $0["nValid"],
                                   lastUpdatedTs: $0["lastUpdatedTs"])
                }
        }
    }
}
