import Foundation

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
    static func write(recovery: Double?, recoveryBand: String?, restingHr: Int?,
                      avgHrv: Double?, strain: Double?, totalSleepMin: Double?) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let snapshot = WidgetSnapshot(recovery: recovery, recoveryBand: recoveryBand,
                                      restingHr: restingHr, avgHrv: avgHrv,
                                      strain: strain, totalSleepMin: totalSleepMin,
                                      updatedAt: Date())
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
