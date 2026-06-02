import Foundation
import UserNotifications

enum SyncStatusNotifier {
    private static let notificationId = "com.openwhoop.syncStatus"
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    /// Notification body. Appends the freshly-computed day strain when it's known.
    static func body(at date: Date, strain: Double?) -> String {
        var text = "Last successful sync: \(timeFormatter.string(from: date))"
        if let strain { text += " · Current Strain: \(String(format: "%.1f", strain))" }
        return text
    }

    static func post(at date: Date = Date(), strain: Double? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "OpenWhoop"
        content.body = body(at: date, strain: strain)
        content.interruptionLevel = .passive
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: notificationId, content: content, trigger: nil)
        )
    }
}
