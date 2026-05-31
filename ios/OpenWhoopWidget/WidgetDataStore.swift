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
    static func read() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
