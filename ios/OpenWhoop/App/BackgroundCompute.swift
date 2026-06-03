import Foundation
import WhoopCompute
import WhoopStore

enum BackgroundCompute {
    static func run(days: Int, force: Bool) async -> Bool {
        guard let path = try? StorePaths.defaultDatabasePath(),
              let store = try? await WhoopStore(path: path) else { return false }
        let engine = OnDeviceEngine(store: store, deviceId: AppConfig.deviceId)
        if let data = UserDefaults.standard.data(forKey: "com.openwhoop.profile.v1"),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var profile = EngineProfile()
            if let age = raw["age"] as? Int { profile.age = age }
            if let sex = raw["sex"] as? String { profile.sex = sex }
            if let w = raw["weight_kg"] as? Double { profile.weightKg = w }
            if let h = raw["height_cm"] as? Double { profile.heightCm = h }
            await engine.setProfile(profile)
        }
        await engine.computeRecent(days: days, force: force)
        await engine.refreshCurrentDayStrain()
        return true
    }
}
