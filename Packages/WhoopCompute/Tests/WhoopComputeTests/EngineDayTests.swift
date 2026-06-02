import XCTest
@testable import WhoopCompute

/// Tests for the pure day-windowing + wake-day attribution helpers that back OnDeviceEngine.
/// These are the logic that was buggy: UTC-only day buckets and ±14h windows that double-count
/// one night across two calendar days. They run against a fixed America/New_York calendar so the
/// timezone behavior is deterministic regardless of the host's TZ.
final class EngineDayTests: XCTestCase {

    private func edtCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }

    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f
    }()

    // MARK: - Day window bounds

    func testDayWindowStartsAtLocalMidnight() {
        let cal = edtCalendar()
        let win = EngineDay.window(dayStr: "2026-05-31", calendar: cal)!

        // dayStart must be local (EDT) midnight, dayEnd the next local midnight.
        XCTAssertEqual(fmt.string(from: Date(timeIntervalSince1970: TimeInterval(win.dayStart))),
                       "2026-05-31 00:00")
        XCTAssertEqual(fmt.string(from: Date(timeIntervalSince1970: TimeInterval(win.dayEnd))),
                       "2026-06-01 00:00")
    }

    func testDayWindowCoversFullCalendarDayForStrain() {
        let cal = edtCalendar()
        let win = EngineDay.window(dayStr: "2026-06-01", calendar: cal)!
        // The strain window [dayStart, dayEnd) must span a full 24h local day so afternoon/evening
        // HR is included — the bug was the load capping at dayDate+14h (mid-afternoon).
        XCTAssertEqual(win.dayEnd - win.dayStart, 24 * 3600)
    }

    func testSleepSearchStartReachesPreviousEvening() {
        let cal = edtCalendar()
        let win = EngineDay.window(dayStr: "2026-05-31", calendar: cal)!
        // Search must begin the previous evening so a night that started the night before is
        // fully captured. 14h before local midnight = 10:00 the previous morning — generous.
        XCTAssertEqual(win.searchStart, win.dayStart - 14 * 3600)
        XCTAssertLessThan(win.searchStart, win.dayStart)
    }

    // MARK: - Wake-day attribution

    func testKeepsRunEndingWithinDay() {
        let cal = edtCalendar()
        let win = EngineDay.window(dayStr: "2026-05-31", calendar: cal)!
        // A night 01:00 -> 09:00 EDT on 5/31 ends within the day → kept.
        let start = Int(fmt.date(from: "2026-05-31 01:00")!.timeIntervalSince1970)
        let end   = Int(fmt.date(from: "2026-05-31 09:00")!.timeIntervalSince1970)
        let kept = EngineDay.runsEndingInDay([(start, end)], dayStart: win.dayStart, dayEnd: win.dayEnd)
        XCTAssertEqual(kept.count, 1)
    }

    func testDropsRunEndingBeforeDay() {
        let cal = edtCalendar()
        let win = EngineDay.window(dayStr: "2026-06-01", calendar: cal)!
        // The previous night (ended 5/31 09:00 EDT) must NOT be attributed to 6/01 — this is the
        // double-counting that produced a bogus second session on the next day.
        let start = Int(fmt.date(from: "2026-05-31 01:00")!.timeIntervalSince1970)
        let end   = Int(fmt.date(from: "2026-05-31 09:00")!.timeIntervalSince1970)
        let kept = EngineDay.runsEndingInDay([(start, end)], dayStart: win.dayStart, dayEnd: win.dayEnd)
        XCTAssertTrue(kept.isEmpty)
    }

    func testDropsRunEndingAfterDay() {
        let cal = edtCalendar()
        let win = EngineDay.window(dayStr: "2026-05-31", calendar: cal)!
        // A nap ending 6/01 belongs to 6/01, not 5/31.
        let start = Int(fmt.date(from: "2026-06-01 02:00")!.timeIntervalSince1970)
        let end   = Int(fmt.date(from: "2026-06-01 09:00")!.timeIntervalSince1970)
        let kept = EngineDay.runsEndingInDay([(start, end)], dayStart: win.dayStart, dayEnd: win.dayEnd)
        XCTAssertTrue(kept.isEmpty)
    }
}
