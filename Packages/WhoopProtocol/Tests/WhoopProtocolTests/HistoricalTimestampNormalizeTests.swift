import XCTest
@testable import WhoopProtocol

final class HistoricalTimestampNormalizeTests: XCTestCase {

    func testNoOpWhenTimestampsNearWall() {
        let wall = 1_780_347_000
        var s = Streams()
        s.hr = [HRSample(ts: wall - 60, bpm: 70)]
        let out = HistoricalTimestampNormalize.applyIfNeeded(s, wall: wall)
        XCTAssertEqual(out.hr.first?.ts, wall - 60)
    }

    func testShiftsFastRtcBatchToWall() {
        let wall = 1_780_347_000
        let fast = 1_809_088_894  // ~332d ahead (strap RTC)
        var s = Streams()
        s.hr = [HRSample(ts: fast - 10, bpm: 70), HRSample(ts: fast, bpm: 72)]
        let out = HistoricalTimestampNormalize.applyIfNeeded(s, wall: wall)
        XCTAssertEqual(out.hr.last?.ts, wall)
        XCTAssertEqual(out.hr.first?.ts, wall - 10)
    }
}
