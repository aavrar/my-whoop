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

    static func post(at date: Date = Date()) {
        let content = UNMutableNotificationContent()
        content.title = "OpenWhoop"
        content.body = "Last successful sync: \(timeFormatter.string(from: date))"
        content.interruptionLevel = .passive
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: notificationId, content: content, trigger: nil)
        )
    }
}
