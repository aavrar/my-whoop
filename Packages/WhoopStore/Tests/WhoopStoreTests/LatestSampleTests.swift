import XCTest
import WhoopProtocol
@testable import WhoopStore

final class LatestSampleTests: XCTestCase {
    func testLatestHRSampleTs() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "d", mac: nil, name: nil)
        // No rows yet → nil.
        let empty = try await store.latestHRSampleTs(deviceId: "d")
        XCTAssertNil(empty)
        // Insert HR rows at ts 100 and 250; latest = 250.
        let s = Streams(hr: [HRSample(ts: 100, bpm: 60), HRSample(ts: 250, bpm: 61)])
        _ = try await store.insert(s, deviceId: "d")
        let latest = try await store.latestHRSampleTs(deviceId: "d")
        XCTAssertEqual(latest, 250)
    }

    func testLatestSleepSessionUsesEndTsNotStartTs() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "d", mac: nil, name: nil)
        // Edit (earlier start, the real night) vs. a stale fragment that starts later but ends
        // earlier. Latest = most recent wake (endTs), so the edit must win — not the fragment.
        let edit     = CachedSleepSession(startTs: 1000, endTs: 5000, efficiency: 0.95,
                                          restingHr: 55, avgHrv: 70, stagesJSON: nil, isManualOverride: true)
        let fragment = CachedSleepSession(startTs: 3000, endTs: 4500, efficiency: 0.9,
                                          restingHr: 57, avgHrv: 68, stagesJSON: nil, isManualOverride: false)
        _ = try await store.upsertSleepSessions([edit, fragment], deviceId: "d")
        let latest = try await store.latestSleepSession(deviceId: "d")
        XCTAssertEqual(latest?.startTs, 1000, "latestSleepSession must order by endTs, returning the later-waking session")
    }

    func testDeleteDailyMetricsAfterRemovesFutureRows() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "d", mac: nil, name: nil)
        func dm(_ day: String, strain: Double?) -> DailyMetric {
            DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                        lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                        strain: strain, exerciseCount: nil)
        }
        _ = try await store.upsertDailyMetrics([dm("2026-06-01", strain: 5), dm("2027-04-30", strain: 0)], deviceId: "d")
        let removed = try await store.deleteDailyMetricsAfter(deviceId: "d", day: "2026-06-05")
        XCTAssertEqual(removed, 1)
        let rows = try await store.dailyMetrics(deviceId: "d", from: "1970-01-01", to: "2100-01-01")
        XCTAssertEqual(rows.map(\.day), ["2026-06-01"])
    }

    func testUpdateDailyStrainTouchesOnlyStrain() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "d", mac: nil, name: nil)
        let m = DailyMetric(day: "2026-06-02", totalSleepMin: 480, efficiency: 0.9, deepMin: 60,
                            remMin: 90, lightMin: 300, disturbances: 3, restingHr: 55, avgHrv: 70,
                            recovery: 80, strain: 5, exerciseCount: nil)
        _ = try await store.upsertDailyMetrics([m], deviceId: "d")
        let n = try await store.updateDailyStrain(deviceId: "d", day: "2026-06-02", strain: 12.3)
        XCTAssertEqual(n, 1)
        let row = try await store.dailyMetrics(deviceId: "d", from: "2026-06-02", to: "2026-06-02").first
        XCTAssertEqual(row?.strain, 12.3)            // strain updated
        XCTAssertEqual(row?.totalSleepMin, 480)      // sleep untouched
        XCTAssertEqual(row?.deepMin, 60)
        // no-op when the day has no row
        let missing = try await store.updateDailyStrain(deviceId: "d", day: "2099-01-01", strain: 1)
        XCTAssertEqual(missing, 0)
    }
}
