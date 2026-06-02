import Foundation

/// Pure day-windowing + wake-day attribution helpers for OnDeviceEngine. Kept free of the actor
/// and the store so the timezone/attribution logic — historically the source of double-counted
/// nights — is unit-testable in isolation.
enum EngineDay {
    /// How far before local midnight the sleep search reaches, so a night that began the previous
    /// evening is fully captured before we attribute it to its wake day.
    static let searchLookbackSeconds = 14 * 3600

    struct Window {
        let dayStart: Int     // local midnight (unix seconds)
        let dayEnd: Int       // next local midnight (unix seconds)
        let searchStart: Int  // dayStart - searchLookbackSeconds: reaches the previous evening
    }

    /// Local-day bounds for a "yyyy-MM-dd" day string, using `calendar`'s timezone.
    static func window(dayStr: String, calendar: Calendar) -> Window? {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dayStr) else { return nil }
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let startTs = Int(dayStart.timeIntervalSince1970)
        return Window(
            dayStart: startTs,
            dayEnd: Int(dayEnd.timeIntervalSince1970),
            searchStart: startTs - searchLookbackSeconds
        )
    }

    /// Wake-day attribution: keep only runs whose END falls within [dayStart, dayEnd). A night is
    /// owned by the single local day on which the sleeper woke, so adjacent days never both claim it.
    static func runsEndingInDay(_ runs: [(start: Int, end: Int)], dayStart: Int, dayEnd: Int) -> [(start: Int, end: Int)] {
        runs.filter { $0.end >= dayStart && $0.end < dayEnd }
    }
}
