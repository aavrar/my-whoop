import Foundation
import HealthKit
import WhoopStore

@MainActor
final class HealthKitSync {
    static let shared = HealthKitSync()

    private let store = HKHealthStore()
    private var authorized = false

    private static let writeTypes: Set<HKSampleType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKCategoryType(.sleepAnalysis),
    ]

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: Self.writeTypes, read: [])
            authorized = true
        } catch {
            authorized = false
        }
    }

    // MARK: - Write after on-device compute

    func sync(session: CachedSleepSession, daily: DailyMetric) async {
        guard HKHealthStore.isHealthDataAvailable(), authorized else { return }

        var samples: [HKSample] = []

        if let stages = decodeStages(session.stagesJSON) {
            samples.append(contentsOf: sleepSamples(stages: stages, startTs: session.startTs, endTs: session.endTs))
        }

        if let hrv = daily.avgHrv {
            let sleepMid = Date(timeIntervalSince1970: TimeInterval((session.startTs + session.endTs) / 2))
            samples.append(hrvSample(rmssd: hrv, date: sleepMid))
        }

        if let rhr = daily.restingHr {
            let sleepMid = Date(timeIntervalSince1970: TimeInterval((session.startTs + session.endTs) / 2))
            samples.append(restingHRSample(bpm: rhr, date: sleepMid))
        }

        guard !samples.isEmpty else { return }
        try? await store.save(samples)
    }

    func writeHRSamples(_ hr: [(ts: Int, bpm: Int)]) async {
        guard HKHealthStore.isHealthDataAvailable(), authorized, !hr.isEmpty else { return }
        let type = HKQuantityType(.heartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples: [HKQuantitySample] = hr.map { s in
            let date = Date(timeIntervalSince1970: TimeInterval(s.ts))
            let qty  = HKQuantity(unit: unit, doubleValue: Double(s.bpm))
            return HKQuantitySample(type: type, quantity: qty, start: date, end: date)
        }
        try? await store.save(samples)
    }

    // MARK: - Helpers

    private func sleepSamples(stages: [StageSegmentCodable], startTs: Int, endTs: Int) -> [HKCategorySample] {
        let type = HKCategoryType(.sleepAnalysis)
        var samples: [HKCategorySample] = []

        let inBed = HKCategorySample(
            type: type,
            value: HKCategoryValueSleepAnalysis.inBed.rawValue,
            start: Date(timeIntervalSince1970: TimeInterval(startTs)),
            end:   Date(timeIntervalSince1970: TimeInterval(endTs))
        )
        samples.append(inBed)

        for seg in stages {
            let value: HKCategoryValueSleepAnalysis
            switch seg.stage {
            case "deep":  value = .asleepDeep
            case "rem":   value = .asleepREM
            case "wake":  value = .awake
            default:      value = .asleepCore
            }
            let sample = HKCategorySample(
                type: type,
                value: value.rawValue,
                start: Date(timeIntervalSince1970: TimeInterval(seg.start)),
                end:   Date(timeIntervalSince1970: TimeInterval(seg.end))
            )
            samples.append(sample)
        }
        return samples
    }

    private func hrvSample(rmssd: Double, date: Date) -> HKQuantitySample {
        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let qty  = HKQuantity(unit: .secondUnit(with: .milli), doubleValue: rmssd)
        return HKQuantitySample(type: type, quantity: qty, start: date, end: date)
    }

    private func restingHRSample(bpm: Int, date: Date) -> HKQuantitySample {
        let type = HKQuantityType(.restingHeartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let qty  = HKQuantity(unit: unit, doubleValue: Double(bpm))
        return HKQuantitySample(type: type, quantity: qty, start: date, end: date)
    }

    private func decodeStages(_ json: String?) -> [StageSegmentCodable]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([StageSegmentCodable].self, from: data)
    }
}

private struct StageSegmentCodable: Codable {
    let start: Int
    let end: Int
    let stage: String
}
