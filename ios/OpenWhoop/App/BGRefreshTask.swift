import Foundation
import BackgroundTasks

enum BGRefreshTask {
    static let identifier = "com.openwhoop.bgRefresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task: task as! BGAppRefreshTask)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(task: BGAppRefreshTask) {
        schedule()
        let taskOp = Task {
            _ = await BackgroundCompute.run(days: 3, force: false)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { taskOp.cancel() }
    }
}
