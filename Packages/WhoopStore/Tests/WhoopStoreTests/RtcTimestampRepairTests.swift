import XCTest
@testable import WhoopStore
import WhoopProtocol

final class RtcTimestampRepairTests: XCTestCase {

    func testRepairShiftsFutureHrRows() async throws {
        let store = try await WhoopStore.inMemory()
        let wall = 1_780_347_000
        let fast = 1_809_088_894
        try await store.insert(Streams(hr: [HRSample(ts: fast, bpm: 70)]), deviceId: "dev")

        let n = try await store.repairFutureTimestamps(deviceId: "dev", wallNow: wall)
        XCTAssertEqual(n, 1)

        let hr = try await store.hrSamples(deviceId: "dev", from: 0, to: Int.max, limit: 10)
        XCTAssertEqual(hr.first?.ts, wall)
    }

    func testRepairIsIdempotent() async throws {
        let store = try await WhoopStore.inMemory()
        let wall = 1_780_347_000
        try await store.insert(Streams(hr: [HRSample(ts: wall + 8 * 86_400, bpm: 70)]), deviceId: "dev")
        _ = try await store.repairFutureTimestamps(deviceId: "dev", wallNow: wall)
        let second = try await store.repairFutureTimestamps(deviceId: "dev", wallNow: wall)
        XCTAssertEqual(second, 0)
    }
}
