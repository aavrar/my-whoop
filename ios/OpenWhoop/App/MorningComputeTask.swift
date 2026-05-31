import Foundation
import BackgroundTasks
import WhoopCompute
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
            guard let path = try? StorePaths.defaultDatabasePath(),
                  let store = try? await WhoopStore(path: path) else {
                task.setTaskCompleted(success: false)
                return
            }
            let deviceId = AppConfig.deviceId
            let engine = OnDeviceEngine(store: store, deviceId: deviceId)
            if let data = UserDefaults.standard.data(forKey: "com.openwhoop.profile.v1"),
               let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var engineProfile = EngineProfile()
                if let age = raw["age"] as? Int { engineProfile.age = age }
                if let sex = raw["sex"] as? String { engineProfile.sex = sex }
                if let w = raw["weight_kg"] as? Double { engineProfile.weightKg = w }
                if let h = raw["height_cm"] as? Double { engineProfile.heightCm = h }
                await engine.setProfile(engineProfile)
            }
            await engine.computeRecent(days: 14, force: true)
            if let metric = try? await store.latestDailyMetric(deviceId: deviceId),
               let recovery = metric.recovery {
                RecoveryNotifier.notify(recovery: recovery, forDay: metric.day)
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { taskOp.cancel() }
    }
}
