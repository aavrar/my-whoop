import XCTest
import WhoopStore
@testable import OpenWhoop

final class TodayDashboardAdapterTests: XCTestCase {
    func testBuildsScoreCardsHealthCardsAndLiveChipsFromAvailableData() {
        let metric = DailyMetric(
            day: "2026-06-04",
            totalSleepMin: 436,
            efficiency: 0.83,
            deepMin: 82,
            remMin: 96,
            lightMin: 258,
            disturbances: 4,
            restingHr: 49,
            avgHrv: 61,
            recovery: 0.72,
            strain: 12.4,
            exerciseCount: 1,
            spo2Pct: 97.2,
            skinTempDevC: -0.3,
            respRateBpm: 14.6,
            calories: 842,
            sleepNeedMin: 480
        )
        let session = CachedSleepSession(
            startTs: 1_779_920_000,
            endTs: 1_779_946_200,
            efficiency: 0.82,
            restingHr: 51,
            avgHrv: 58,
            stagesJSON: nil
        )

        let dashboard = TodayDashboardAdapter.make(
            metric: metric,
            session: session,
            live: TodayDashboardLiveState(connected: true, heartRate: 64, batteryPct: 76)
        )

        XCTAssertTrue(dashboard.hasAnyData)
        XCTAssertEqual(dashboard.scoreCards.map(\.kind), [.sleep, .recovery, .strain])
        XCTAssertEqual(dashboard.card(kind: .sleep)?.value, "83")
        XCTAssertEqual(dashboard.card(kind: .sleep)?.unit, "%")
        XCTAssertEqual(dashboard.card(kind: .sleep)?.status, "Moderate sleep")
        XCTAssertEqual(dashboard.card(kind: .sleep)?.detail, "7h 16m asleep")
        XCTAssertEqual(dashboard.card(kind: .recovery)?.value, "72")
        XCTAssertEqual(dashboard.card(kind: .recovery)?.status, "Recovered")
        XCTAssertEqual(dashboard.card(kind: .strain)?.value, "12.4")
        XCTAssertEqual(dashboard.card(kind: .strain)?.unit, "/21")
        XCTAssertEqual(dashboard.card(kind: .heartRateVariability)?.value, "61")
        XCTAssertEqual(dashboard.card(kind: .restingHeartRate)?.value, "49")
        XCTAssertEqual(dashboard.card(kind: .calories)?.value, "842")
        XCTAssertEqual(dashboard.card(kind: .respiratoryRate)?.value, "14.6")
        XCTAssertEqual(dashboard.card(kind: .skinTemperature)?.value, "-0.3")
        XCTAssertEqual(dashboard.liveChips.map(\.value), ["64 BPM", "76%"])
    }

    func testFallsBackToSleepSessionWhenDailySleepValuesAreMissing() {
        let metric = DailyMetric(
            day: "2026-06-04",
            totalSleepMin: nil,
            efficiency: nil,
            deepMin: nil,
            remMin: nil,
            lightMin: nil,
            disturbances: nil,
            restingHr: nil,
            avgHrv: nil,
            recovery: nil,
            strain: nil,
            exerciseCount: nil
        )
        let session = CachedSleepSession(
            startTs: 1_779_920_000,
            endTs: 1_779_948_800,
            efficiency: 0.88,
            restingHr: 52,
            avgHrv: 63,
            stagesJSON: nil
        )

        let dashboard = TodayDashboardAdapter.make(
            metric: metric,
            session: session,
            live: .disconnected
        )

        XCTAssertEqual(dashboard.card(kind: .sleep)?.value, "88")
        XCTAssertEqual(dashboard.card(kind: .sleep)?.detail, "8h asleep")
        XCTAssertEqual(dashboard.card(kind: .heartRateVariability)?.value, "63")
        XCTAssertEqual(dashboard.card(kind: .restingHeartRate)?.value, "52")
    }

    func testBuildsUnavailableCardsWhenDataIsMissing() {
        let dashboard = TodayDashboardAdapter.make(
            metric: nil,
            session: nil,
            live: .disconnected
        )

        XCTAssertFalse(dashboard.hasAnyData)
        XCTAssertEqual(dashboard.scoreCards.map(\.value), ["--", "--", "--"])
        XCTAssertEqual(dashboard.scoreCards.map(\.status), ["No data", "No data", "No data"])
        XCTAssertTrue(dashboard.liveChips.isEmpty)
    }
}
