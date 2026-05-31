import Foundation

public enum Calories {
    static func bmr(age: Int, sex: String, weightKg: Double, heightCm: Double) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return sex == "female" ? base - 161 : base + 5
    }

    public static func estimate(
        hr: [(ts: Int, bpm: Int)],
        age: Int,
        sex: String,
        weightKg: Double,
        dayStartTs: Int,
        dayEndTs: Int
    ) -> Double {
        let samples = hr.filter { $0.ts >= dayStartTs && $0.ts <= dayEndTs }
        guard samples.count > 10 else {
            return bmr(age: age, sex: sex, weightKg: weightKg, heightCm: 170) / 24
        }
        var totalCal = 0.0
        for i in 1..<samples.count {
            let dt = Double(samples[i].ts - samples[i-1].ts) / 60.0
            guard dt > 0, dt < 10 else { continue }
            let bpm = Double(samples[i].bpm)
            let w   = weightKg
            let a   = Double(age)
            let cal: Double
            if sex == "female" {
                cal = ((-20.4022 + 0.4472 * bpm - 0.1263 * w + 0.074 * a) / 4.184) * dt
            } else {
                cal = ((-55.0969 + 0.6309 * bpm + 0.1988 * w + 0.2017 * a) / 4.184) * dt
            }
            totalCal += max(0, cal)
        }
        return totalCal
    }
}
