import Foundation

public enum Strain {
    static let strainDenominator: Double = 7201.0
    static let minReadings = 600

    public static func compute(
        hr: [(ts: Int, bpm: Int)],
        restingHr: Int,
        age: Int,
        sex: String = "male",
        method: String = "edwards"
    ) -> Double? {
        guard hr.count >= minReadings else { return nil }

        let hrMax = 208.0 - 0.7 * Double(age)
        let rhr = Double(restingHr)
        guard hrMax > rhr else { return nil }
        let hrr = hrMax - rhr

        let sorted = hr.sorted { $0.ts < $1.ts }

        var trimp: Double = 0
        let s = sex.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isFemale = s == "female"
        
        // Banister exponential coefficient b
        let b = isFemale ? 1.67 : 1.92
        let scale = 0.64

        for i in 1..<sorted.count {
            let dt = Double(sorted[i].ts - sorted[i-1].ts)
            // Gap safety: skip gaps larger than 5 minutes (300s) to prevent BLE
            // dropouts from swelling duration and spiking accumulated TRIMP to 21.0.
            guard dt > 0, dt <= 300.0 else { continue }
            let durationMin = dt / 60.0
            
            let bpm = Double(sorted[i].bpm)
            let pctHRR = min(max((bpm - rhr) / hrr * 100.0, 0), 100)

            if method == "banister" {
                let x = pctHRR / 100.0
                if x > 0.0 {
                    trimp += durationMin * x * scale * exp(b * x)
                }
            } else {
                let zoneWeight: Double
                switch pctHRR {
                case ..<50: zoneWeight = 0
                case ..<60: zoneWeight = 1
                case ..<70: zoneWeight = 2
                case ..<80: zoneWeight = 3
                case ..<90: zoneWeight = 4
                default:    zoneWeight = 5
                }
                trimp += zoneWeight * durationMin
            }
        }

        guard trimp > 0 else { return 0 }
        let strain = 21.0 * log(trimp + 1) / log(strainDenominator)
        return min(max(strain, 0), 21.0)
    }
}
