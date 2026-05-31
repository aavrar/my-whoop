import Foundation
import WidgetKit
import WhoopStore

private let suiteName = "group.com.aahad.openwhoop"
private let key = "widgetSnapshot"

struct WidgetSnapshot: Codable {
    let recovery: Double?
    let recoveryBand: String?
    let restingHr: Int?
    let avgHrv: Double?
    let strain: Double?
    let totalSleepMin: Double?
    let updatedAt: Date
}

enum WidgetDataStore {
    static func write(today: DailyMetric?, lastNight: CachedSleepSession?) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let recovery = today?.recovery.map { $0 * 100 } ?? today?.recovery
        let band: String? = {
            guard let r = today?.recovery else { return nil }
            let pct = r * 100
            if pct >= 67 { return "green" }
            if pct >= 34 { return "yellow" }
            return "red"
        }()
        let snapshot = WidgetSnapshot(
            recovery: today?.recovery.map { $0 * 100 },
            recoveryBand: band,
            restingHr: today?.restingHr ?? lastNight?.restingHr,
            avgHrv: today?.avgHrv ?? lastNight?.avgHrv,
            strain: today?.strain,
            totalSleepMin: today?.totalSleepMin,
            updatedAt: Date()
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    static func read() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
