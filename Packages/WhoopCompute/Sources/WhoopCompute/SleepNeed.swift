import Foundation

public enum SleepNeed {
    public static func need(strain: Double?, recovery: Double?) -> Double {
        var base = 480.0
        if let s = strain {
            if s >= 14 { base += 30 }
            else if s >= 8 { base += 15 }
        }
        if let r = recovery {
            if r < 0.33 { base += 30 }
        }
        return base
    }

    public static func debt(nights: [(need: Double, actual: Double?)]) -> Double {
        nights.reduce(0.0) { acc, pair in
            acc + (pair.need - (pair.actual ?? 0))
        }
    }
}
