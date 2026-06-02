import Foundation

/// WHOOP-faithful day strain: an *absolute* cardiovascular load (every beat above your resting HR
/// contributes, exponentially weighted by intensity — Banister TRIMP), mapped onto the 0–21
/// logarithmic scale against a *personalized* anchor (the load that reads 21). The anchor rises with
/// your hardest recent days and decays slowly (~60-day half-life), so the same workout yields less
/// strain as you get fitter — and a quiet day reads low, not zero.
public enum Strain {
    static let scaleK = 0.64
    /// Load that maps to 21 before/with no personal history, and the floor the anchor never drops
    /// below — keeps a sedentary stretch from collapsing the scale (else a moderate day reads 21).
    public static let floorAnchor = 300.0
    /// Per-day multiplicative decay of the anchor (~60-day half-life) when today is easier than the
    /// running peak — the scale tracks fitness down as well as up.
    static let anchorDecayPerDay = pow(0.5, 1.0 / 60.0)
    static let maxGapSeconds = 300.0

    /// Continuous cardiovascular load for a set of HR samples. Every interval contributes
    /// `dt_min · x · scaleK · e^(b·x)` where `x` is the fraction of heart-rate reserve used. Gaps
    /// > 5 min are skipped so a BLE dropout can't inflate the total.
    public static func rawLoad(hr: [(ts: Int, bpm: Int)], restingHr: Int,
                               age: Int, sex: String = "male") -> Double {
        guard hr.count >= 2 else { return 0 }
        let hrMax = 208.0 - 0.7 * Double(age)
        let rhr = Double(restingHr)
        guard hrMax > rhr else { return 0 }
        let hrr = hrMax - rhr
        let b = sex.lowercased().trimmingCharacters(in: .whitespaces).hasPrefix("f") ? 1.67 : 1.92

        let sorted = hr.sorted { $0.ts < $1.ts }
        var load = 0.0
        for i in 1..<sorted.count {
            let dt = Double(sorted[i].ts - sorted[i - 1].ts)
            guard dt > 0, dt <= maxGapSeconds else { continue }
            let x = min(max((Double(sorted[i].bpm) - rhr) / hrr, 0), 1)
            guard x > 0 else { continue }
            load += (dt / 60.0) * x * scaleK * exp(b * x)
        }
        return load
    }

    /// Map a day's load to 0–21 against `anchor` (the load that reads 21) on a concave power curve.
    /// Concave (exponent < 1) so a rest day stays low while 16→17 costs more load than 4→5 — the
    /// "logarithmic feel" of WHOOP's scale, but fitted to the ~20× dynamic range of Banister load
    /// (a true log over-compresses that range and floats rest days up into the teens).
    static let curveExponent = 0.5
    public static func score(load: Double, anchor: Double) -> Double {
        guard load > 0 else { return 0 }
        let a = max(anchor, floorAnchor)
        let s = 21.0 * pow(min(load / a, 1.0), curveExponent)
        return min(max(s, 0), 21.0)
    }

    /// Advance the personalized anchor: today's load raises it immediately; otherwise it decays
    /// slowly toward (but never below) the floor.
    public static func updatedAnchor(previous: Double, dayLoad: Double) -> Double {
        max(dayLoad, previous * anchorDecayPerDay, floorAnchor)
    }
}
