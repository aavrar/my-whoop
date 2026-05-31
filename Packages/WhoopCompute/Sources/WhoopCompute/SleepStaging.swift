import Foundation

public enum SleepStaging {
    static let epochS: Double = 30
    static let featureWindowS: Double = 5 * 60
    static let smoothEpochs = 5
    static let noRemAfterOnsetS: Double = 15 * 60
    static let deepFirstFraction = 1.0 / 3.0
    static let onsetPersistEpochs = 3
    static let wakeMoveThresh: Double = 0.15
    static let stillMoveThresh: Double = 0.10
    static let gravityStillThreshG: Double = 0.01

    // Cole-Kripke (te Lindert 30 s) coefficients
    static let ckWeights: [Double] = [106, 54, 58, 76, 230, 74, 67]
    static let ckBack = 4
    static let ckFwd = 2
    static let ckScale = 0.001
    static let ckCountDivisor = 100.0
    static let ckCountClip = 300.0

    struct Epoch {
        let start: Int
        let end: Int
        let meanHR: Double?
        let rmssd: Double?
        let moveFrac: Double
        let hrStd: Double?   // rolling HR std — proxy for Walch DoG HRV variability
    }

    public static func stage(
        sleepStart: Int,
        sleepEnd: Int,
        gravity: [SleepDetection.GravitySample],
        hr: [(ts: Int, bpm: Int)],
        rr: [(ts: Int, rrMs: Int)]
    ) -> [StageSegment] {
        let gravSorted = gravity.filter { $0.ts >= sleepStart && $0.ts <= sleepEnd }
            .sorted { $0.ts < $1.ts }
        let hrSorted  = hr.filter { $0.ts >= sleepStart && $0.ts <= sleepEnd }.sorted { $0.ts < $1.ts }
        let rrSorted  = rr.filter { $0.ts >= sleepStart && $0.ts <= sleepEnd }.sorted { $0.ts < $1.ts }

        let deltas = SleepDetection.gravityDeltas(gravSorted)
        let epochs = buildEpochGrid(start: sleepStart, end: sleepEnd, gravity: gravSorted, deltas: deltas, hr: hrSorted, rr: rrSorted)

        guard !epochs.isEmpty else { return [StageSegment(start: sleepStart, end: sleepEnd, stage: "light")] }

        let counts = epochActivityCounts(epochs: epochs, gravity: gravSorted, deltas: deltas)
        let ckFlags = coleKripke(counts: counts)
        let (onsetIdx, finalIdx) = onsetAndFinalWake(ckFlags: ckFlags)

        var labels = classify(epochs: epochs)
        labels = smooth(labels: labels)
        labels = reimpose(labels: labels, onsetIdx: onsetIdx, finalIdx: finalIdx, sleepStart: sleepStart, sleepEnd: sleepEnd, epochs: epochs)

        return buildSegments(epochs: epochs, labels: labels, sleepStart: sleepStart, sleepEnd: sleepEnd)
    }

    static func buildEpochGrid(
        start: Int, end: Int,
        gravity: [SleepDetection.GravitySample],
        deltas: [Double],
        hr: [(ts: Int, bpm: Int)],
        rr: [(ts: Int, rrMs: Int)]
    ) -> [Epoch] {
        let sessionHrTimes  = hr.map { Double($0.ts) }
        let sessionHrValues = hr.map { Double($0.bpm) }

        var epochs: [Epoch] = []
        var t = start
        while t < end {
            let epochEnd = min(t + Int(epochS), end)
            let halfWindow = Int(featureWindowS / 2)
            let winStart = max(start, t - halfWindow)
            let winEnd   = min(end, epochEnd + halfWindow)

            let gravEpoch = gravity.filter { $0.ts >= t && $0.ts < epochEnd }
            let moveFrac: Double
            if gravEpoch.isEmpty {
                moveFrac = 1.0
            } else {
                let startIdx = gravity.firstIndex { $0.ts >= t } ?? 0
                let endIdx   = gravity.lastIndex  { $0.ts < epochEnd } ?? (gravity.count - 1)
                let epochDeltas = Array(deltas[max(0, startIdx)...min(deltas.count-1, endIdx)])
                let moving = epochDeltas.filter { $0 >= gravityStillThreshG }.count
                moveFrac = epochDeltas.isEmpty ? 0 : Double(moving) / Double(epochDeltas.count)
            }

            let hrWin = hr.filter { $0.ts >= winStart && $0.ts <= winEnd }.map { Double($0.bpm) }
            let meanHR: Double? = hrWin.isEmpty ? nil : hrWin.reduce(0,+) / Double(hrWin.count)

            let epochMidTs = Double(t + epochEnd) / 2.0
            let hrDoG: Double? = dogFilter(times: sessionHrTimes, values: sessionHrValues, center: epochMidTs)

            let rrWin = rr.filter { $0.ts >= winStart && $0.ts <= winEnd }
            let epochRMSSD = HRV.gapAwareRMSSD(rr: rrWin)

            epochs.append(Epoch(start: t, end: epochEnd, meanHR: meanHR, rmssd: epochRMSSD, moveFrac: moveFrac, hrStd: hrDoG))
            t = epochEnd
        }
        return epochs
    }

    static func dogFilter(times: [Double], values: [Double], center: Double, sigma1: Double = 120.0, sigma2: Double = 600.0) -> Double? {
        let cutoff = 3.0 * sigma2
        var s1 = 0.0, w1 = 0.0, s2 = 0.0, w2 = 0.0
        for (t, v) in zip(times, values) {
            let dt = t - center
            guard abs(dt) <= cutoff else { continue }
            let g1 = exp(-0.5 * (dt / sigma1) * (dt / sigma1))
            let g2 = exp(-0.5 * (dt / sigma2) * (dt / sigma2))
            s1 += g1 * v; w1 += g1
            s2 += g2 * v; w2 += g2
        }
        guard w1 > 0, w2 > 0 else { return nil }
        return abs(s1 / w1 - s2 / w2)
    }

    static func epochActivityCounts(epochs: [Epoch], gravity: [SleepDetection.GravitySample], deltas: [Double]) -> [Double] {
        epochs.map { epoch in
            guard let startIdx = gravity.firstIndex(where: { $0.ts >= epoch.start }),
                  let endIdx   = gravity.lastIndex(where:  { $0.ts < epoch.end }) else { return 0 }
            let epochDeltas = Array(deltas[startIdx...endIdx])
            return epochDeltas.reduce(0, +)
        }
    }

    static func coleKripke(counts: [Double]) -> [Bool] {
        let rescaled = counts.map { min($0 / ckCountDivisor, ckCountClip) }
        let n = rescaled.count
        return (0..<n).map { i in
            var si = 0.0
            for (k, w) in ckWeights.enumerated() {
                let j = i - ckBack + k
                let a = (j >= 0 && j < n) ? rescaled[j] : 0.0
                si += w * a
            }
            return si * ckScale < 1.0
        }
    }

    static func onsetAndFinalWake(ckFlags: [Bool]) -> (onset: Int, final: Int) {
        let n = ckFlags.count
        guard n > 0 else { return (0, 0) }

        var onset: Int? = nil
        var run = 0
        for (i, s) in ckFlags.enumerated() {
            run = s ? run + 1 : 0
            if run >= onsetPersistEpochs { onset = i - onsetPersistEpochs + 1; break }
        }

        var finalWake: Int? = nil
        for i in stride(from: n-1, through: 0, by: -1) {
            if ckFlags[i] { finalWake = i; break }
        }

        return (onset ?? 0, finalWake ?? n - 1)
    }

    static func classify(epochs: [Epoch]) -> [String] {
        let hrs   = epochs.compactMap { $0.meanHR }
        let rmssds = epochs.compactMap { $0.rmssd }
        let hrStds = epochs.compactMap { $0.hrStd }

        let hrLowP  = percentile(hrs, 0.25)
        let hrHighP = percentile(hrs, 0.70)
        let rmssdHighP = percentile(rmssds, 0.70)
        let hrStdHighP = percentile(hrStds, 0.65)

        return epochs.map { epoch in
            let moveFrac = epoch.moveFrac
            let hr = epoch.meanHR
            let rmssd = epoch.rmssd
            let hrStd = epoch.hrStd

            let hrHigh    = hr.map    { $0 >= hrHighP }    ?? false
            let hrVarHigh = hrStd.map { $0 >= hrStdHighP } ?? false

            if moveFrac >= wakeMoveThresh && (hr == nil || hrHigh || hrVarHigh) {
                return "wake"
            }

            let isStill = moveFrac <= stillMoveThresh
            let hrLow   = hr.map { $0 <= hrLowP }  ?? false
            let rmssdHigh = rmssd.map { $0 >= rmssdHighP } ?? false

            if isStill && hrLow && rmssdHigh { return "deep" }
            if isStill && !hrHigh && hrVarHigh { return "rem" }
            if isStill && hrHigh && hrVarHigh { return "rem" }
            return "light"
        }
    }

    static func smooth(labels: [String]) -> [String] {
        guard labels.count >= smoothEpochs else { return labels }
        let half = smoothEpochs / 2
        return (0..<labels.count).map { i in
            let lo = max(0, i - half)
            let hi = min(labels.count - 1, i + half)
            let window = Array(labels[lo...hi])
            var counts: [String: Int] = [:]
            window.forEach { counts[$0, default: 0] += 1 }
            return counts.max(by: { $0.value < $1.value })?.key ?? labels[i]
        }
    }

    static func reimpose(labels: [String], onsetIdx: Int, finalIdx: Int, sleepStart: Int, sleepEnd: Int, epochs: [Epoch]) -> [String] {
        var result = labels
        let n = labels.count
        let duration = Double(sleepEnd - sleepStart)
        let deepCutoffTs = sleepStart + Int(duration * deepFirstFraction)
        let noRemCutoffTs = sleepStart + Int(noRemAfterOnsetS)

        for i in 0..<n {
            if i < onsetIdx || i > finalIdx {
                result[i] = "wake"
                continue
            }
            if epochs[i].start < noRemCutoffTs && result[i] == "rem" {
                result[i] = "light"
            }
            if epochs[i].start >= deepCutoffTs && result[i] == "deep" {
                result[i] = "light"
            }
        }
        return result
    }

    static func buildSegments(epochs: [Epoch], labels: [String], sleepStart: Int, sleepEnd: Int) -> [StageSegment] {
        guard !epochs.isEmpty else { return [] }
        var segments: [StageSegment] = []
        var segStage = labels[0]
        var segStart = epochs[0].start

        for i in 1..<epochs.count {
            if labels[i] != segStage {
                segments.append(StageSegment(start: segStart, end: epochs[i].start, stage: segStage))
                segStage = labels[i]
                segStart = epochs[i].start
            }
        }
        segments.append(StageSegment(start: segStart, end: sleepEnd, stage: segStage))
        return segments
    }

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let idx = p * Double(sorted.count - 1)
        let lo = Int(idx)
        let hi = min(lo + 1, sorted.count - 1)
        let frac = idx - Double(lo)
        return sorted[lo] * (1 - frac) + sorted[hi] * frac
    }

    static func stddev(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }
}
