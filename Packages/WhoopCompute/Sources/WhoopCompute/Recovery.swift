import Foundation

public enum Recovery {
    static let wHRV    = 0.60
    static let wRHR    = 0.20
    static let wResp   = 0.05
    static let wSleep  = 0.15
    static let logisticK  = 1.6
    static let logisticZ0 = -0.20
    static let sleepPerfCenter: Double = 0.85
    static let sleepPerfScale:  Double = 0.12
    public static let populationMean: Double = 58.0

    public struct Inputs {
        public let hrv: Double
        public let restingHr: Double
        public let sleepEfficiency: Double?
        /// Sleep actually obtained ÷ sleep need (1.0 = met need). Lets short sleep depress recovery
        /// even when efficiency is high. Nil falls back to the efficiency-only sleep term.
        public let sleepPerformance: Double?
        public let resp: Double?

        public init(hrv: Double, restingHr: Double, sleepEfficiency: Double?, sleepPerformance: Double? = nil, resp: Double?) {
            self.hrv = hrv; self.restingHr = restingHr
            self.sleepEfficiency = sleepEfficiency
            self.sleepPerformance = sleepPerformance
            self.resp = resp
        }
    }

    public static func score(
        inputs: Inputs,
        hrv: BaselineState,
        restingHr: BaselineState,
        resp: BaselineState?
    ) -> Double? {
        guard hrv.usable else { return nil }

        var terms: [(z: Double, w: Double)] = []

        let zHRV = zScore(inputs.hrv, mean: hrv.baseline, spread: hrv.spread)
        terms.append((zHRV, wHRV))

        let zRHR = zScore(restingHr.baseline, mean: inputs.restingHr, spread: restingHr.spread)
        terms.append((zRHR, wRHR))

        if let r = inputs.resp, let rb = resp {
            let zResp = zScore(rb.baseline, mean: r, spread: rb.spread)
            terms.append((zResp, wResp))
        }

        if let eff = inputs.sleepEfficiency {
            // Blend efficiency with sleep-vs-need so short sleep can't post a high score on
            // efficiency alone. Performance is capped at 1.0 — exceeding need doesn't boost recovery.
            let quality: Double
            if let perf = inputs.sleepPerformance {
                quality = 0.5 * eff + 0.5 * min(perf, 1.0)
            } else {
                quality = eff
            }
            let zSleep = (quality - sleepPerfCenter) / sleepPerfScale
            terms.append((zSleep, wSleep))
        }

        guard !terms.isEmpty else { return nil }
        let totalWeight = terms.map { $0.w }.reduce(0, +)
        guard totalWeight > 0 else { return nil }
        let Z = terms.map { $0.z * $0.w }.reduce(0, +) / totalWeight

        let raw = 100.0 / (1.0 + exp(-logisticK * (Z - logisticZ0)))
        return max(0, min(100, raw))
    }

    public static func band(_ score: Double) -> String {
        if score < 34 { return "red" }
        if score < 67 { return "yellow" }
        return "green"
    }

    static func zScore(_ value: Double, mean: Double, spread: Double) -> Double {
        let sigma = max(1.253 * spread, 1e-9)
        return (value - mean) / sigma
    }
}
