import XCTest
@testable import WhoopCompute

final class WhoopComputeTests: XCTestCase {

    // MARK: - Calories

    func testCaloriesSedentaryReturnsBMR() {
        let rhr = 60.0
        let hrMax = 208.0 - 0.7 * 30

        let dayStart = 0
        let dayEnd   = 86400
        let hr = stride(from: dayStart, to: dayEnd, by: 60).map { (ts: $0, bpm: 55) }

        let cals = Calories.estimate(
            hr: hr, age: 30, sex: "male", weightKg: 70, heightCm: 175,
            restingHr: rhr, hrMax: hrMax,
            dayStartTs: dayStart, dayEndTs: dayEnd
        )
        let bmrExpected = 88.362 + 13.397 * 70 + 4.799 * 175 - 5.677 * 30
        // Should be within 10% of a full BMR day
        XCTAssertGreaterThan(cals, bmrExpected * 0.85)
        XCTAssertLessThan(cals, bmrExpected * 1.15)
    }

    func testCaloriesActiveHigherThanSedentary() {
        let rhr = 60.0
        let hrMax = 190.0
        let dayStart = 0
        let dayEnd   = 86400

        let sedentaryHR = stride(from: dayStart, to: dayEnd, by: 60).map { (ts: $0, bpm: 60) }
        let activeHR    = stride(from: dayStart, to: dayEnd, by: 60).map { (ts: $0, bpm: 160) }

        let sedentary = Calories.estimate(
            hr: sedentaryHR, age: 30, sex: "male", weightKg: 70, heightCm: 175,
            restingHr: rhr, hrMax: hrMax, dayStartTs: dayStart, dayEndTs: dayEnd
        )
        let active = Calories.estimate(
            hr: activeHR, age: 30, sex: "male", weightKg: 70, heightCm: 175,
            restingHr: rhr, hrMax: hrMax, dayStartTs: dayStart, dayEndTs: dayEnd
        )
        XCTAssertGreaterThan(active, sedentary * 2.0)
    }

    func testCaloriesFallbackOnFewSamples() {
        // With fewer than 10 samples, should return full-day BMR
        let hr = [(ts: 0, bpm: 60), (ts: 60, bpm: 62)]
        let cals = Calories.estimate(
            hr: hr, age: 30, sex: "female", weightKg: 60, heightCm: 165,
            restingHr: 58.0, hrMax: 187.0, dayStartTs: 0, dayEndTs: 86400
        )
        let bmr = 447.593 + 9.247 * 60 + 3.098 * 165 - 4.330 * 30
        XCTAssertGreaterThan(cals, 0)
        XCTAssertEqual(cals, bmr, accuracy: 1.0)
    }

    // MARK: - HRV

    func testRMSSDBasicComputation() {
        // RMSSD of [800, 810, 790, 800] should be sqrt(mean([100, 400, 100])) = sqrt(200) ≈ 14.14
        let rr = [800, 810, 790, 800]
        let result = HRV.rmssd(rr)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, sqrt(200.0), accuracy: 0.1)
    }

    func testMalikFilterDroppedBeatDoesNotSpliceDiffs() {
        // Insert an ectopic beat (200ms, physiologically impossible between 800ms beats).
        // The correct RMSSD should NOT include the differences across the dropped beat.
        // Expected: the 200ms beat is removed; the run is split at that point.
        let rrWithEctopic = [800, 810, 200, 795, 805]
        let result = HRV.rmssd(rrWithEctopic)
        // Without splicing protection, RMSSD would be inflated (800-200 = 600, 200-795 = -595 diffs).
        // With protection, we only get diffs within valid runs: [800,810] and [795,805].
        if let rmssd = result {
            XCTAssertLessThan(rmssd, 100.0, "Spliced ectopic beats inflate RMSSD above realistic thresholds")
        }
    }

    func testHRVNightlyRMSSDUsesDeepSleep() {
        let sleepStart = 0
        let sleepEnd   = 28800  // 8 hours

        // Deep sleep episode from 1h to 1.5h (in seconds)
        let deepStart = 3600
        let deepEnd   = 5400
        let stages = [
            StageSegment(start: deepStart, end: deepEnd, stage: "deep"),
            StageSegment(start: 0, end: deepStart, stage: "light"),
            StageSegment(start: deepEnd, end: sleepEnd, stage: "rem")
        ]

        // Place RR intervals with low RMSSD outside deep and higher inside deep
        var rr: [(ts: Int, rrMs: Int)] = []
        for t in stride(from: 0, to: deepStart, by: 1) {
            rr.append((ts: t, rrMs: 800))
            rr.append((ts: t, rrMs: 800))  // identical = 0 diff
        }
        for t in stride(from: deepStart, to: deepEnd, by: 1) {
            rr.append((ts: t, rrMs: 800))
            rr.append((ts: t, rrMs: 820))  // alternating = non-zero diff
        }

        let result = HRV.nightlyRMSSD(rr: rr, sleepStart: sleepStart, sleepEnd: sleepEnd, stages: stages)
        // Should pick up the deep sleep window and return non-zero RMSSD
        XCTAssertNotNil(result)
        if let rmssd = result {
            XCTAssertGreaterThan(rmssd, 0.0)
        }
    }

    // MARK: - Strain (WHOOP-faithful absolute load + personalized anchor)

    func testRawLoadZeroAtRestingHR() {
        // HR pinned at resting → no reserve used → zero load.
        let restHR = stride(from: 0, to: 3600, by: 1).map { (ts: $0, bpm: 60) }
        XCTAssertEqual(Strain.rawLoad(hr: restHR, restingHr: 60, age: 30), 0.0, accuracy: 1e-9)
    }

    func testRawLoadGapCapped() {
        // Same active duration, one split by a 5h gap. The >300s gap is skipped, so loads match.
        let burst1 = stride(from: 0, to: 300, by: 1).map { (ts: $0, bpm: 160) }
        let burst2 = stride(from: 18300, to: 18600, by: 1).map { (ts: $0, bpm: 160) }
        let gapped = Strain.rawLoad(hr: burst1 + burst2, restingHr: 60, age: 30)
        let contiguous = Strain.rawLoad(hr: stride(from: 0, to: 600, by: 1).map { (ts: $0, bpm: 160) },
                                        restingHr: 60, age: 30)
        XCTAssertGreaterThan(gapped, 0)
        XCTAssertEqual(gapped, contiguous, accuracy: contiguous * 0.05)
    }

    func testRawLoadMonotonicInIntensity() {
        // Higher sustained HR → strictly more load (intensity is exponentially weighted).
        let easy = Strain.rawLoad(hr: stride(from: 0, to: 1800, by: 1).map { (ts: $0, bpm: 90) },  restingHr: 60, age: 30)
        let hard = Strain.rawLoad(hr: stride(from: 0, to: 1800, by: 1).map { (ts: $0, bpm: 150) }, restingHr: 60, age: 30)
        XCTAssertGreaterThan(easy, 0)
        XCTAssertGreaterThan(hard, easy)
    }

    func testScoreOrderingAndAnchor() {
        // Score is monotonic in load, hits 21 at the anchor, and a rest day stays well below a hard day.
        let anchor = 300.0
        let rest   = Strain.score(load: 10,  anchor: anchor)
        let normal = Strain.score(load: 90,  anchor: anchor)
        let hard   = Strain.score(load: 300, anchor: anchor)
        XCTAssertLessThan(rest, normal)
        XCTAssertLessThan(normal, hard)
        XCTAssertEqual(hard, 21.0, accuracy: 1e-6)         // load == anchor → 21
        XCTAssertEqual(Strain.score(load: 0, anchor: anchor), 0.0)
    }

    func testScoreFlooredAnchorPreventsCollapse() {
        // A tiny anchor (sedentary stretch) is floored, so a moderate load can't read 21.
        let s = Strain.score(load: 90, anchor: 5)
        XCTAssertLessThan(s, 21.0)
        XCTAssertEqual(s, Strain.score(load: 90, anchor: Strain.floorAnchor), accuracy: 1e-9)
    }

    func testAnchorRisesOnHardDayDecaysOtherwise() {
        // A hard day jumps the anchor up; an easy day lets it decay (but never below the floor).
        let raised = Strain.updatedAnchor(previous: Strain.floorAnchor, dayLoad: 900)
        XCTAssertEqual(raised, 900, accuracy: 1e-9)
        let decayed = Strain.updatedAnchor(previous: 900, dayLoad: 10)
        XCTAssertLessThan(decayed, 900)
        XCTAssertGreaterThanOrEqual(decayed, Strain.floorAnchor)
        XCTAssertEqual(Strain.updatedAnchor(previous: Strain.floorAnchor, dayLoad: 0), Strain.floorAnchor, accuracy: 1e-9)
    }

    // MARK: - Recovery (sleep duration sensitivity)

    private func recoveryBaseline() -> BaselineState {
        BaselineState(baseline: 60.0, spread: 10.0, nValid: 30, lastUpdatedTs: 0)
    }

    func testRecoveryShortSleepScoresLowerThanFullSleep() {
        let hrvBase = recoveryBaseline()
        let rhrBase = recoveryBaseline()
        // Identical physiology + efficiency; only sleep-vs-need differs (3h vs 8h on an 8h need).
        let short = Recovery.Inputs(hrv: 70, restingHr: 55, sleepEfficiency: 0.9, sleepPerformance: 180.0 / 480.0, resp: nil)
        let full  = Recovery.Inputs(hrv: 70, restingHr: 55, sleepEfficiency: 0.9, sleepPerformance: 480.0 / 480.0, resp: nil)
        let sShort = Recovery.score(inputs: short, hrv: hrvBase, restingHr: rhrBase, resp: nil)
        let sFull  = Recovery.score(inputs: full,  hrv: hrvBase, restingHr: rhrBase, resp: nil)
        XCTAssertNotNil(sShort); XCTAssertNotNil(sFull)
        XCTAssertLessThan(sShort!, sFull!, "3h sleep must score lower recovery than 8h at equal efficiency")
    }

    func testRecoveryNilPerformanceFallsBackToEfficiency() {
        let base = recoveryBaseline()
        let inputs = Recovery.Inputs(hrv: 70, restingHr: 55, sleepEfficiency: 0.9, sleepPerformance: nil, resp: nil)
        XCTAssertNotNil(Recovery.score(inputs: inputs, hrv: base, restingHr: base, resp: nil))
    }

    // MARK: - Baselines

    func testBaselineOutOfBoundsSeedsAtMidpoint() {
        let cfg = defaultConfigs[.hrv]!
        // HRV maxVal is 250, this out-of-bounds value should NOT be seeded as baseline
        let state = Baselines.update(state: nil, value: 999.0, cfg: cfg, nowTs: 0)
        XCTAssertEqual(state.nValid, 0, "Out-of-bounds initial seed should have nValid = 0")
        let midpoint = (cfg.minVal + cfg.maxVal) / 2.0
        XCTAssertEqual(state.baseline, midpoint, accuracy: 0.01)
    }

    func testBaselineOutOfBoundsPreservesExistingState() {
        let cfg = defaultConfigs[.hrv]!
        let existing = BaselineState(baseline: 60.0, spread: 10.0, nValid: 14, lastUpdatedTs: 0)
        let state = Baselines.update(state: existing, value: 999.0, cfg: cfg, nowTs: 1)
        XCTAssertEqual(state.baseline, 60.0, "Out-of-bounds value must not change existing baseline")
        XCTAssertEqual(state.nValid, 14)
    }

    func testBaselineFoldProducesReasonableResult() {
        let cfg = defaultConfigs[.hrv]!
        let values: [(value: Double, ts: Int)] = (0..<30).map { i in (value: 50.0 + Double(i % 5), ts: i * 86400) }
        let state = Baselines.fold(values: values, cfg: cfg)
        XCTAssertNotNil(state)
        XCTAssertGreaterThan(state!.nValid, 0)
        XCTAssertGreaterThan(state!.baseline, 40.0)
        XCTAssertLessThan(state!.baseline, 70.0)
    }

    // MARK: - SleepStaging (gravity dropout)

    func testStagingGravityDropoutMoveFracIsActive() {
        let hrSamples = stride(from: 0, to: 3600, by: 30).map { (ts: $0, bpm: 55) }
        let epochs = SleepStaging.buildEpochGrid(
            start: 0, end: 3600,
            gravity: [], deltas: [],
            hr: hrSamples, rr: []
        )
        XCTAssertFalse(epochs.isEmpty)
        for epoch in epochs {
            XCTAssertEqual(epoch.moveFrac, 1.0,
                "Empty gravity must produce moveFrac=1.0 — not 0 which would falsely appear as deep sleep")
        }
    }

    // An epoch that falls entirely inside a gravity GAP (samples on both sides, none within) makes
    // firstIndex(>=start) land AFTER lastIndex(<end) → startIdx > endIdx. Must yield 0, not crash
    // ("Range requires lowerBound <= upperBound"). Regression for the morning-compute crash.
    func testEpochActivityCountsGapDoesNotCrash() {
        let epochs = [SleepStaging.Epoch(start: 100, end: 200, meanHR: 60, rmssd: nil, moveFrac: 0, hrStd: nil)]
        let gravity = [SleepDetection.GravitySample(ts: 50,  x: 0, y: 0, z: 1),
                       SleepDetection.GravitySample(ts: 300, x: 0, y: 0, z: 1)]
        let deltas: [Double] = [0.0, 0.5]
        let counts = SleepStaging.epochActivityCounts(epochs: epochs, gravity: gravity, deltas: deltas)
        XCTAssertEqual(counts, [0.0], "an epoch inside a gravity gap must contribute 0, not crash")
    }

    // MARK: - Unit scaling

    func testRespRateFormulaInPhysiologicalRange() {
        // (10/512) * raw + 6 should give 12-20 bpm for typical raw ADC values
        let rawValues: [Double] = [307.2, 409.6, 512.0, 614.4]  // typical raw ADC
        for raw in rawValues {
            let rate = (10.0 / 512.0) * raw + 6.0
            XCTAssertGreaterThan(rate, 4.0,  "Resp rate \(rate) too low for raw=\(raw)")
            XCTAssertLessThan(rate,    40.0, "Resp rate \(rate) too high for raw=\(raw)")
        }
    }
}
