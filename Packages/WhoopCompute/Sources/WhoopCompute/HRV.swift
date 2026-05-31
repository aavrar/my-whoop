import Foundation

public enum HRV {
    static let rrMinMs: Double = 300
    static let rrMaxMs: Double = 2000
    static let malikThreshold = 0.20
    static let minBeats = 20
    static let swsMinDurationS: Double = 5 * 60
    static let gapThresholdS: Double = 3.0

    public static func rmssd(_ rrMs: [Int]) -> Double? {
        let cleaned = cleanRR(rrMs.map { Double($0) })
        guard cleaned.count >= 2 else { return nil }
        return poolRMSSD([cleaned])
    }

    public static func nightlyRMSSD(
        rr: [(ts: Int, rrMs: Int)],
        sleepStart: Int,
        sleepEnd: Int,
        stages: [StageSegment]?
    ) -> Double? {
        guard !rr.isEmpty else { return nil }
        let sorted = rr.sorted { $0.ts < $1.ts }

        let deepEpisodes = (stages ?? []).filter { $0.stage == "deep" }
            .sorted { $0.start < $1.start }

        if let last = deepEpisodes.last,
           Double(last.end - last.start) >= swsMinDurationS {
            let window = sorted.filter { $0.ts >= last.start && $0.ts <= last.end }
            if let result = gapAwareRMSSD(rr: window), !result.isNaN { return result }
        }

        let allDeep = deepEpisodes
        if !allDeep.isEmpty {
            var sqDiffs: [Double] = []
            for ep in allDeep {
                let window = sorted.filter { $0.ts >= ep.start && $0.ts <= ep.end }
                sqDiffs.append(contentsOf: withinSegmentSqDiffs(rr: window))
            }
            if !sqDiffs.isEmpty {
                return sqrt(sqDiffs.reduce(0, +) / Double(sqDiffs.count))
            }
        }

        let window = sorted.filter { $0.ts >= sleepStart && $0.ts <= sleepEnd }
        return gapAwareRMSSD(rr: window)
    }

    static func gapAwareRMSSD(rr: [(ts: Int, rrMs: Int)]) -> Double? {
        let sqDiffs = withinSegmentSqDiffs(rr: rr)
        guard !sqDiffs.isEmpty else { return nil }
        return sqrt(sqDiffs.reduce(0, +) / Double(sqDiffs.count))
    }

    static func withinSegmentSqDiffs(rr: [(ts: Int, rrMs: Int)]) -> [Double] {
        guard rr.count >= 2 else { return [] }
        let sorted = rr.sorted { $0.ts < $1.ts }

        var segments: [[(ts: Int, rrMs: Int)]] = []
        var current: [(ts: Int, rrMs: Int)] = [sorted[0]]
        for i in 1..<sorted.count {
            if Double(sorted[i].ts - sorted[i-1].ts) > gapThresholdS {
                segments.append(current)
                current = []
            }
            current.append(sorted[i])
        }
        segments.append(current)

        var sqDiffs: [Double] = []
        for seg in segments {
            let vals = cleanRR(seg.map { Double($0.rrMs) })
            guard vals.count >= 2 else { continue }
            let diffs = zip(vals, vals.dropFirst()).map { ($1 - $0) * ($1 - $0) }
            sqDiffs.append(contentsOf: diffs)
        }
        return sqDiffs
    }

    static func cleanRR(_ rr: [Double]) -> [Double] {
        let filtered = rr.filter { $0 >= rrMinMs && $0 <= rrMaxMs }
        guard filtered.count >= 3 else { return filtered }
        return malikFilter(filtered)
    }

    static func malikFilter(_ rr: [Double]) -> [Double] {
        var result: [Double] = []
        for i in 0..<rr.count {
            let lo = max(0, i - 2)
            let hi = min(rr.count - 1, i + 2)
            var window = Array(rr[lo...hi])
            let selfIdx = i - lo
            window.remove(at: selfIdx)
            guard !window.isEmpty else { result.append(rr[i]); continue }
            let mean = window.reduce(0, +) / Double(window.count)
            guard mean > 0 else { result.append(rr[i]); continue }
            if abs(rr[i] - mean) / mean <= malikThreshold {
                result.append(rr[i])
            }
        }
        return result
    }

    private static func poolRMSSD(_ segments: [[Double]]) -> Double? {
        var sqDiffs: [Double] = []
        for seg in segments {
            let diffs = zip(seg, seg.dropFirst()).map { ($1 - $0) * ($1 - $0) }
            sqDiffs.append(contentsOf: diffs)
        }
        guard !sqDiffs.isEmpty else { return nil }
        return sqrt(sqDiffs.reduce(0, +) / Double(sqDiffs.count))
    }
}
