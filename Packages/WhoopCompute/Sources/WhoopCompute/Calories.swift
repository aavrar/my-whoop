import Foundation

public enum Calories {
    static func bmr(age: Int, sex: String, weightKg: Double, heightCm: Double) -> Double {
        let a = Double(age)
        let s = sex.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if s == "female" {
            // Revised Harris-Benedict (women): 447.593 + 9.247·kg + 3.098·cm - 4.330·age
            return 447.593 + 9.247 * weightKg + 3.098 * heightCm - 4.330 * a
        } else if s == "male" {
            // Revised Harris-Benedict (men): 88.362 + 13.397·kg + 4.799·cm - 5.677·age
            return 88.362 + 13.397 * weightKg + 4.799 * heightCm - 5.677 * a
        } else {
            // Non-binary / default: element-wise mean of male and female coefficients
            return 267.9775 + 11.322 * weightKg + 3.9485 * heightCm - 5.0035 * a
        }
    }

    public static func estimate(
        hr: [(ts: Int, bpm: Int)],
        age: Int,
        sex: String,
        weightKg: Double,
        heightCm: Double,
        restingHr: Double?,
        hrMax: Double?,
        dayStartTs: Int,
        dayEndTs: Int
    ) -> Double {
        let samples = hr.filter { $0.ts >= dayStartTs && $0.ts <= dayEndTs }
        
        let effResting = restingHr ?? 60.0
        let effHrMax = hrMax ?? (208.0 - 0.7 * Double(age))
        let bmrValue = bmr(age: age, sex: sex, weightKg: weightKg, heightCm: heightCm)
        
        guard samples.count > 10 else {
            // Fallback: return full daily BMR value
            return bmrValue
        }
        
        // Active when HR >= resting + 30% of heart-rate reserve (Karvonen threshold)
        let activeHrrFraction = 0.30
        let activeThreshold = effResting + activeHrrFraction * (effHrMax - effResting)
        
        // BMR rate per second (bmr is daily kcal)
        let restingKcalPerS = max(0.0, bmrValue) / 86400.0
        
        // Keytel workout divisor: 60 s/min * 4.184 kJ/kcal = 251.04
        let workoutDivisor = 251.04
        
        var totalKcal = 0.0
        
        let s = sex.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isFemale = s == "female"
        let isNonbinary = s != "female" && s != "male"
        
        // Men coefficients (Keytel 2005): kJ/min = -55.0969 + 0.6309·HR + 0.1988·kg + 0.2017·age
        let mAlpha = -55.0969
        let mHr = 0.6309
        let mWeight = 0.1988
        let mAge = 0.2017
        
        // Women coefficients (Keytel 2005): kJ/min = -20.4022 + 0.4472·HR - 0.1263·kg + 0.0740·age
        let wAlpha = -20.4022
        let wHr = 0.4472
        let wWeight = -0.1263
        let wAge = 0.0740
        
        // Non-binary coefficients (arithmetic mean)
        let nbAlpha = -37.74955
        let nbHr = 0.53905
        let nbWeight = 0.03625
        let nbAge = 0.13785
        
        for i in 1..<samples.count {
            let dt = Double(samples[i].ts - samples[i-1].ts)
            guard dt > 0, dt < 600 else { continue } // gap-cap of 10 minutes (600s)
            
            let bpm = Double(samples[i].bpm)
            
            if bpm < activeThreshold {
                totalKcal += restingKcalPerS * dt
            } else {
                let cappedBpm = min(bpm, effHrMax)
                let eeKjMin: Double
                if isFemale {
                    eeKjMin = wHr * cappedBpm + wWeight * weightKg + wAge * Double(age) + wAlpha
                } else if isNonbinary {
                    eeKjMin = nbHr * cappedBpm + nbWeight * weightKg + nbAge * Double(age) + nbAlpha
                } else {
                    eeKjMin = mHr * cappedBpm + mWeight * weightKg + mAge * Double(age) + mAlpha
                }
                
                let eeKcalPerS = max(0.0, eeKjMin) / workoutDivisor
                totalKcal += eeKcalPerS * dt
            }
        }
        
        return totalKcal
    }
}
