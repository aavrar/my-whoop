import Foundation

public enum RestingHR {
    static let windowS: Double = 5 * 60

    public static func compute(hr: [(ts: Int, bpm: Int)], sleepStart: Int, sleepEnd: Int) -> Int? {
        let window = hr.filter { $0.ts >= sleepStart && $0.ts <= sleepEnd }
        guard !window.isEmpty else { return nil }

        let sorted = window.sorted { $0.ts < $1.ts }
        let start = Double(sleepStart)
        let end = Double(sleepEnd)

        var means: [Double] = []
        var t = start
        while t < end {
            let bucketEnd = t + windowS
            let bucket = sorted.filter { Double($0.ts) >= t && Double($0.ts) < bucketEnd }
            if !bucket.isEmpty {
                let mean = Double(bucket.map { $0.bpm }.reduce(0, +)) / Double(bucket.count)
                means.append(mean)
            }
            t = bucketEnd
        }

        guard !means.isEmpty else {
            let fallback = sorted.map { Double($0.bpm) }.reduce(0, +) / Double(sorted.count)
            return Int(fallback.rounded())
        }
        return Int(means.min()!.rounded())
    }
}
