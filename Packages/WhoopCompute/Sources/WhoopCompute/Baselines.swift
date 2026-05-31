import Foundation

public struct BaselineState: Equatable, Codable {
    public let baseline: Double
    public let spread: Double
    public let nValid: Int
    public let lastUpdatedTs: Int

    public var usable: Bool { nValid >= 4 }
    public var trusted: Bool { nValid >= 14 }

    public init(baseline: Double, spread: Double, nValid: Int, lastUpdatedTs: Int) {
        self.baseline = baseline
        self.spread = spread
        self.nValid = nValid
        self.lastUpdatedTs = lastUpdatedTs
    }
}

public struct MetricConfig {
    let minVal: Double
    let maxVal: Double
    let floorSpread: Double
    let halfLifeB: Double
    let halfLifeS: Double

    var lambdaB: Double { 1.0 - pow(0.5, 1.0 / halfLifeB) }
    var lambdaS: Double { 1.0 - pow(0.5, 1.0 / halfLifeS) }
}

public enum BaselineMetric: String, CaseIterable {
    case hrv, restingHr, resp
}

public let defaultConfigs: [BaselineMetric: MetricConfig] = [
    .hrv:       MetricConfig(minVal: 5,  maxVal: 250, floorSpread: 5.0, halfLifeB: 14, halfLifeS: 21),
    .restingHr: MetricConfig(minVal: 30, maxVal: 120, floorSpread: 2.0, halfLifeB: 14, halfLifeS: 21),
    .resp:      MetricConfig(minVal: 4,  maxVal: 40,  floorSpread: 0.5, halfLifeB: 14, halfLifeS: 21),
]

public enum Baselines {
    static let winsorK = 3.0
    static let hardOutlierK = 5.0

    public static func update(
        state: BaselineState?,
        value: Double,
        cfg: MetricConfig,
        nowTs: Int
    ) -> BaselineState {
        guard value >= cfg.minVal && value <= cfg.maxVal else {
            if let state { return state }
            let midpoint = (cfg.minVal + cfg.maxVal) / 2.0
            return BaselineState(baseline: midpoint, spread: cfg.floorSpread, nValid: 0, lastUpdatedTs: nowTs)
        }

        guard let state else {
            return seed(value: value, cfg: cfg, nowTs: nowTs)
        }

        let spread = max(state.spread, cfg.floorSpread)

        if abs(value - state.baseline) > hardOutlierK * spread {
            return BaselineState(baseline: state.baseline, spread: state.spread,
                                 nValid: state.nValid, lastUpdatedTs: nowTs)
        }

        let clamped = min(max(value, state.baseline - winsorK * spread),
                          state.baseline + winsorK * spread)

        let newBaseline = state.baseline + cfg.lambdaB * (clamped - state.baseline)
        let absDev = abs(value - newBaseline)
        let newSpread = max(state.spread + cfg.lambdaS * (absDev - state.spread), cfg.floorSpread)

        return BaselineState(baseline: newBaseline, spread: newSpread,
                             nValid: state.nValid + 1, lastUpdatedTs: nowTs)
    }

    public static func fold(values: [(value: Double, ts: Int)], cfg: MetricConfig) -> BaselineState? {
        var state: BaselineState?
        for (value, ts) in values.sorted(by: { $0.ts < $1.ts }) {
            state = update(state: state, value: value, cfg: cfg, nowTs: ts)
        }
        return state
    }

    private static func seed(value: Double, cfg: MetricConfig, nowTs: Int) -> BaselineState {
        BaselineState(baseline: value, spread: cfg.floorSpread, nValid: 1, lastUpdatedTs: nowTs)
    }
}
