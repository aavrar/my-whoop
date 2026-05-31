import Foundation
import UserNotifications
import WhoopStore

enum WeeklyDigestNotifier {
    static let notificationId = "weekly-digest"

    static func schedule(metrics: [DailyMetric]) {
        guard !metrics.isEmpty else { return }

        let recoveries = metrics.compactMap { $0.recovery }.map { $0 * 100 }
        let strains = metrics.compactMap { $0.strain }
        let sleepNights = metrics.compactMap { $0.totalSleepMin }.filter { $0 > 0 }

        guard !recoveries.isEmpty else { return }

        let avgRecovery = Int(recoveries.reduce(0, +) / Double(recoveries.count))
        let totalStrain = strains.reduce(0, +)
        let avgSleep = sleepNights.isEmpty ? nil : sleepNights.reduce(0, +) / Double(sleepNights.count) / 60

        let content = UNMutableNotificationContent()
        content.title = "Weekly Performance"
        var body = "Avg recovery: \(avgRecovery)% · Total strain: \(String(format: "%.1f", totalStrain))"
        if let sleep = avgSleep {
            body += " · Avg sleep: \(String(format: "%.1f", sleep))h"
        }
        content.body = body
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.weekday = 1
        dateComponents.hour = 8
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
