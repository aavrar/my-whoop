import Foundation
import BackgroundTasks
import WhoopStore

enum MorningComputeTask {
    static let identifier = "com.openwhoop.morningCompute"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task: task as! BGProcessingTask)
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 5; comps.minute = 0; comps.second = 0
        var earliest = cal.date(from: comps) ?? Date()
        if earliest <= Date() {
            earliest = cal.date(byAdding: .day, value: 1, to: earliest) ?? earliest
        }
        request.earliestBeginDate = earliest
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(task: BGProcessingTask) {
        schedule()

        let taskOp = Task {
            guard await BackgroundCompute.run(days: 14, force: true) else {
                task.setTaskCompleted(success: false)
                return
            }
            if let path = try? StorePaths.defaultDatabasePath(),
               let store = try? await WhoopStore(path: path),
               let metric = try? await store.latestDailyMetric(deviceId: AppConfig.deviceId),
               let recovery = metric.recovery {
                RecoveryNotifier.notify(recovery: recovery, forDay: metric.day)
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { taskOp.cancel() }
    }
}
