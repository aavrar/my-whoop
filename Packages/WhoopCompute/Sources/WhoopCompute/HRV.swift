import Foundation

public enum HRV {
    static let rrMinMs: Double = 300
    static let rrMaxMs: Double = 2000
    static let malikThreshold = 0.20
    static let minBeats = 20
    static let swsMinDurationS: Double = 5 * 60
    static let gapThresholdS: Double = 3.0

    public static func rmssd(_ rrMs: [Int]) -> Double? {
        let runs = cleanRROntoRuns(rrMs.map { Double($0) })
        guard !runs.isEmpty else { return nil }
        return poolRMSSD(runs)
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

        // Primary Tier: Last deep sleep episode (SWS) >= 5 min
        if let last = deepEpisodes.last,
           Double(last.end - last.start) >= swsMinDurationS {
            let window = sorted.filter { $0.ts >= last.start && $0.ts <= last.end }
            if let result = gapAwareRMSSD(rr: window), !result.isNaN { return result }
        }

        // Secondary Tier: Recency-weighted mean RMSSD over all deep sleep episodes
        let allDeep = deepEpisodes
        if !allDeep.isEmpty {
            var epRMSSDs: [Double] = []
            var epWeights: [Double] = []
            
            for (idx, ep) in allDeep.enumerated() {
                let window = sorted.filter { $0.ts >= ep.start && $0.ts <= ep.end }
                if let rmssd = gapAwareRMSSD(rr: window), !rmssd.isNaN {
                    epRMSSDs.append(rmssd)
                    epWeights.append(Double(idx + 1)) // Chronological recency weights: 1, 2, 3...
                }
            }
            
            if !epRMSSDs.isEmpty {
                let sumWeighted = zip(epRMSSDs, epWeights).map { $0 * $1 }.reduce(0, +)
                let totalWeight = epWeights.reduce(0, +)
                return sumWeighted / totalWeight
            }
        }

        // Fallback Tier: Whole sleep session
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

        // Group into segments split by gaps larger than gapThresholdS
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
            // Split segment into clean runs on dropped Malik outliers, preventing fake successive diffs
            let runs = cleanRROntoRuns(seg.map { Double($0.rrMs) })
            for run in runs {
                let diffs = zip(run, run.dropFirst()).map { ($1 - $0) * ($1 - $0) }
                sqDiffs.append(contentsOf: diffs)
            }
        }
        return sqDiffs
    }

    static func cleanRROntoRuns(_ rr: [Double]) -> [[Double]] {
        let n = rr.count
        guard n > 0 else { return [] }
        
        var isValid = Array(repeating: true, count: n)
        
        // 1. Range filter
        for i in 0..<n {
            if rr[i] < rrMinMs || rr[i] > rrMaxMs {
                isValid[i] = false
            }
        }
        
        // 2. Malik filter (excluding outlier beats, but sliding local mean correctly)
        for i in 0..<n {
            guard isValid[i] else { continue }
            
            var neighbors: [Double] = []
            
            // Backward neighbors (up to 2 valid)
            var count = 0
            var j = i - 1
            while j >= 0 && count < 2 {
                if isValid[j] {
                    neighbors.append(rr[j])
                    count += 1
                }
                j -= 1
            }
            
            // Forward neighbors (up to 2 valid)
            count = 0
            j = i + 1
            while j < n && count < 2 {
                if isValid[j] {
                    neighbors.append(rr[j])
                    count += 1
                }
                j += 1
            }
            
            if !neighbors.isEmpty {
                let mean = neighbors.reduce(0, +) / Double(neighbors.count)
                if mean > 0 && abs(rr[i] - mean) / mean > malikThreshold {
                    isValid[i] = false
                }
            }
        }
        
        // 3. Segment into contiguous valid runs (minimum run size = 2)
        var runs: [[Double]] = []
        var currentRun: [Double] = []
        for i in 0..<n {
            if isValid[i] {
                currentRun.append(rr[i])
            } else {
                if currentRun.count >= 2 {
                    runs.append(currentRun)
                }
                currentRun = []
            }
        }
        if currentRun.count >= 2 {
            runs.append(currentRun)
        }
        
        return runs
    }

    private static func poolRMSSD(_ runs: [[Double]]) -> Double? {
        var sqDiffs: [Double] = []
        for run in runs {
            let diffs = zip(run, run.dropFirst()).map { ($1 - $0) * ($1 - $0) }
            sqDiffs.append(contentsOf: diffs)
        }
        guard !sqDiffs.isEmpty else { return nil }
        return sqrt(sqDiffs.reduce(0, +) / Double(sqDiffs.count))
    }
}
