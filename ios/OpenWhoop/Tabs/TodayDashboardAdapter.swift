import SwiftUI
import WhoopStore

struct TodayDashboardLiveState: Equatable {
    let connected: Bool
    let heartRate: Int?
    let batteryPct: Double?

    static let disconnected = TodayDashboardLiveState(connected: false, heartRate: nil, batteryPct: nil)
}

enum TodayDashboardMetricKind: String, Equatable, Hashable, Identifiable {
    case sleep
    case recovery
    case strain
    case heartRateVariability
    case restingHeartRate
    case calories
    case respiratoryRate
    case skinTemperature

    var id: String { rawValue }
}

enum TodayDashboardTint: Equatable {
    case sleep
    case recoveryGreen
    case recoveryYellow
    case recoveryRed
    case strain
    case heartRate
    case teal
    case yellow
    case primary
    case muted

    var color: Color {
        switch self {
        case .sleep:
            return WH.Color.sleepPurple
        case .recoveryGreen:
            return WH.Color.recoveryGreen
        case .recoveryYellow:
            return WH.Color.recoveryYellow
        case .recoveryRed:
            return WH.Color.recoveryRed
        case .strain:
            return WH.Color.strainBlue
        case .heartRate:
            return WH.Color.recoveryRed
        case .teal:
            return WH.Color.teal
        case .yellow:
            return WH.Color.recoveryYellow
        case .primary:
            return WH.Color.textPrimary
        case .muted:
            return WH.Color.textSecondary
        }
    }
}

struct TodayDashboardMetricCard: Identifiable, Equatable {
    let kind: TodayDashboardMetricKind
    let title: String
    let value: String
    let unit: String
    let status: String
    let detail: String
    let progress: Double
    let systemImage: String
    let tint: TodayDashboardTint

    var id: TodayDashboardMetricKind { kind }
}

struct TodayDashboardLiveChip: Identifiable, Equatable {
    let id: String
    let value: String
    let systemImage: String
    let tint: TodayDashboardTint
}

struct TodayDashboardTimelineItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let time: String
    let systemImage: String
    let tint: TodayDashboardTint
    let metricKind: TodayDashboardMetricKind
}

struct TodayDashboardModel: Equatable {
    let scoreCards: [TodayDashboardMetricCard]
    let healthCards: [TodayDashboardMetricCard]
    let timelineItems: [TodayDashboardTimelineItem]
    let liveChips: [TodayDashboardLiveChip]
    let hasAnyData: Bool

    func card(kind: TodayDashboardMetricKind) -> TodayDashboardMetricCard? {
        (scoreCards + healthCards).first { metricCard in
            metricCard.kind == kind
        }
    }
}

enum TodayDashboardAdapter {
    static func make(
        metric: DailyMetric?,
        session: CachedSleepSession?,
        live: TodayDashboardLiveState
    ) -> TodayDashboardModel {
        let sleepCard = makeSleepCard(metric: metric, session: session)
        let recoveryCard = makeRecoveryCard(metric: metric)
        let strainCard = makeStrainCard(metric: metric)
        let healthCards = [
            makeHRVCard(metric: metric, session: session),
            makeRestingHeartRateCard(metric: metric, session: session),
            makeCaloriesCard(metric: metric),
            makeRespiratoryRateCard(metric: metric),
            makeSkinTemperatureCard(metric: metric),
        ]
        let scoreCards = [sleepCard, recoveryCard, strainCard]
        let liveChips = makeLiveChips(live: live)
        let hasAnyData = scoreCards.contains { metricCard in metricCard.value != "--" }
            || healthCards.contains { metricCard in metricCard.value != "--" }
            || !liveChips.isEmpty

        return TodayDashboardModel(
            scoreCards: scoreCards,
            healthCards: healthCards,
            timelineItems: makeTimelineItems(sleep: sleepCard, recovery: recoveryCard, strain: strainCard, session: session),
            liveChips: liveChips,
            hasAnyData: hasAnyData
        )
    }

    private static func makeSleepCard(metric: DailyMetric?, session: CachedSleepSession?) -> TodayDashboardMetricCard {
        let efficiency = validFraction(metric?.efficiency) ?? validFraction(session?.efficiency)
        let sleepMinutes = validMinutes(metric?.totalSleepMin) ?? sessionDurationMinutes(session)
        let score = efficiency.map { Int(($0 * 100).rounded()) }
        return TodayDashboardMetricCard(
            kind: .sleep,
            title: "Sleep",
            value: score.map(String.init) ?? "--",
            unit: "%",
            status: score.map(sleepStatus) ?? "No data",
            detail: sleepMinutes.map { "\(formatMinutes($0)) asleep" } ?? "No sleep data",
            progress: score.map { clamped(Double($0) / 100) } ?? 0,
            systemImage: "moon.fill",
            tint: .sleep
        )
    }

    private static func makeRecoveryCard(metric: DailyMetric?) -> TodayDashboardMetricCard {
        let recoveryPercent = metric?.recovery.map { Int(($0 * 100).rounded()) }
        let tint = recoveryPercent.map(recoveryTint) ?? .muted
        return TodayDashboardMetricCard(
            kind: .recovery,
            title: "Recovery",
            value: recoveryPercent.map(String.init) ?? "--",
            unit: "%",
            status: recoveryPercent.map(recoveryStatus) ?? "No data",
            detail: recoveryPercent.map { "\($0)% readiness" } ?? "Waiting for recovery",
            progress: recoveryPercent.map { clamped(Double($0) / 100) } ?? 0,
            systemImage: "battery.100percent",
            tint: tint
        )
    }

    private static func makeStrainCard(metric: DailyMetric?) -> TodayDashboardMetricCard {
        let strain = metric?.strain
        return TodayDashboardMetricCard(
            kind: .strain,
            title: "Strain",
            value: strain.map { String(format: "%.1f", min(max($0, 0), 21)) } ?? "--",
            unit: "/21",
            status: strain.map(strainStatus) ?? "No data",
            detail: strain.map { _ in "Day strain" } ?? "No strain yet",
            progress: strain.map { clamped($0 / 21) } ?? 0,
            systemImage: "figure.run",
            tint: .strain
        )
    }

    private static func makeHRVCard(metric: DailyMetric?, session: CachedSleepSession?) -> TodayDashboardMetricCard {
        let heartRateVariability = metric?.avgHrv ?? session?.avgHrv
        return makeHealthCard(
            kind: .heartRateVariability,
            title: "HRV",
            value: heartRateVariability.map { String(format: "%.0f", $0) },
            unit: "ms",
            status: heartRateVariability == nil ? "Unavailable" : "Recorded",
            detail: "Overnight average",
            progress: heartRateVariability.map { clamped($0 / 100) } ?? 0,
            systemImage: "waveform.path.ecg",
            tint: .teal
        )
    }

    private static func makeRestingHeartRateCard(metric: DailyMetric?, session: CachedSleepSession?) -> TodayDashboardMetricCard {
        let restingHeartRate = metric?.restingHr ?? session?.restingHr
        return makeHealthCard(
            kind: .restingHeartRate,
            title: "Resting HR",
            value: restingHeartRate.map(String.init),
            unit: "bpm",
            status: restingHeartRate == nil ? "Unavailable" : "Recorded",
            detail: "During sleep",
            progress: restingHeartRate.map { clamped(1 - Double($0 - 35) / 65) } ?? 0,
            systemImage: "heart.fill",
            tint: .heartRate
        )
    }

    private static func makeCaloriesCard(metric: DailyMetric?) -> TodayDashboardMetricCard {
        let calories = metric?.calories
        return makeHealthCard(
            kind: .calories,
            title: "Calories",
            value: calories.map { String(format: "%.0f", $0) },
            unit: "kcal",
            status: calories == nil ? "Unavailable" : "Estimated",
            detail: "Active burn",
            progress: calories.map { clamped($0 / 1000) } ?? 0,
            systemImage: "flame.fill",
            tint: .yellow
        )
    }

    private static func makeRespiratoryRateCard(metric: DailyMetric?) -> TodayDashboardMetricCard {
        let respiratoryRate = metric?.respRateBpm
        return makeHealthCard(
            kind: .respiratoryRate,
            title: "Respiratory Rate",
            value: respiratoryRate.map { String(format: "%.1f", $0) },
            unit: "br/min",
            status: respiratoryRate == nil ? "Unavailable" : "Recorded",
            detail: "Sleep average",
            progress: respiratoryRate.map { clamped(($0 - 8) / 16) } ?? 0,
            systemImage: "lungs.fill",
            tint: .primary
        )
    }

    private static func makeSkinTemperatureCard(metric: DailyMetric?) -> TodayDashboardMetricCard {
        let skinTemperature = metric?.skinTempDevC
        return makeHealthCard(
            kind: .skinTemperature,
            title: "Skin Temp",
            value: skinTemperature.map { String(format: "%.1f", $0) },
            unit: "C",
            status: skinTemperature == nil ? "Unavailable" : "Deviation",
            detail: "From baseline",
            progress: skinTemperature.map { clamped((abs($0) + 0.2) / 2.2) } ?? 0,
            systemImage: "thermometer.medium",
            tint: .primary
        )
    }

    private static func makeHealthCard(
        kind: TodayDashboardMetricKind,
        title: String,
        value: String?,
        unit: String,
        status: String,
        detail: String,
        progress: Double,
        systemImage: String,
        tint: TodayDashboardTint
    ) -> TodayDashboardMetricCard {
        TodayDashboardMetricCard(
            kind: kind,
            title: title,
            value: value ?? "--",
            unit: value == nil ? "" : unit,
            status: status,
            detail: value == nil ? "No data" : detail,
            progress: progress,
            systemImage: systemImage,
            tint: value == nil ? .muted : tint
        )
    }

    private static func makeLiveChips(live: TodayDashboardLiveState) -> [TodayDashboardLiveChip] {
        guard live.connected else { return [] }
        var liveChips: [TodayDashboardLiveChip] = []
        if let heartRate = live.heartRate {
            liveChips.append(TodayDashboardLiveChip(id: "heart-rate", value: "\(heartRate) BPM", systemImage: "heart.fill", tint: .heartRate))
        }
        if let batteryPct = live.batteryPct {
            liveChips.append(TodayDashboardLiveChip(id: "battery", value: "\(Int(batteryPct.rounded()))%", systemImage: batteryIcon(for: batteryPct), tint: batteryTint(for: batteryPct)))
        }
        return liveChips
    }

    private static func makeTimelineItems(
        sleep: TodayDashboardMetricCard,
        recovery: TodayDashboardMetricCard,
        strain: TodayDashboardMetricCard,
        session: CachedSleepSession?
    ) -> [TodayDashboardTimelineItem] {
        [
            TodayDashboardTimelineItem(
                id: "sleep",
                title: "Sleep summary",
                subtitle: "\(sleep.value)\(sleep.unit) - \(sleep.detail)",
                time: session.map { clockTime($0.endTs) } ?? "--:--",
                systemImage: sleep.systemImage,
                tint: sleep.tint,
                metricKind: .sleep
            ),
            TodayDashboardTimelineItem(
                id: "recovery",
                title: "Recovery update",
                subtitle: "\(recovery.value)\(recovery.unit) - \(recovery.status)",
                time: "AM",
                systemImage: recovery.systemImage,
                tint: recovery.tint,
                metricKind: .recovery
            ),
            TodayDashboardTimelineItem(
                id: "strain",
                title: "Activity load",
                subtitle: "\(strain.value)\(strain.unit) - \(strain.detail)",
                time: "Now",
                systemImage: strain.systemImage,
                tint: strain.tint,
                metricKind: .strain
            ),
        ]
    }

    private static func validFraction(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value > 1 ? value / 100 : value
    }

    private static func validMinutes(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func sessionDurationMinutes(_ session: CachedSleepSession?) -> Double? {
        guard let session else { return nil }
        let durationMinutes = Double(session.endTs - session.startTs) / 60
        return durationMinutes > 0 ? durationMinutes : nil
    }

    private static func formatMinutes(_ totalMinutes: Double) -> String {
        let roundedMinutes = max(Int(totalMinutes.rounded()), 0)
        let hours = roundedMinutes / 60
        let minutes = roundedMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

    private static func clockTime(_ epochSeconds: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    private static func sleepStatus(_ score: Int) -> String {
        if score >= 85 { return "Good sleep" }
        if score >= 70 { return "Moderate sleep" }
        return "Low sleep"
    }

    private static func recoveryStatus(_ score: Int) -> String {
        if score >= 67 { return "Recovered" }
        if score >= 34 { return "Moderate recovery" }
        return "Low recovery"
    }

    private static func strainStatus(_ strain: Double) -> String {
        if strain >= 18 { return "All out" }
        if strain >= 14 { return "High strain" }
        if strain >= 10 { return "Moderate strain" }
        return "Low strain"
    }

    private static func recoveryTint(_ score: Int) -> TodayDashboardTint {
        if score >= 67 { return .recoveryGreen }
        if score >= 34 { return .recoveryYellow }
        return .recoveryRed
    }

    private static func batteryIcon(for batteryPct: Double) -> String {
        if batteryPct > 70 { return "battery.100" }
        if batteryPct > 30 { return "battery.50" }
        return "battery.25"
    }

    private static func batteryTint(for batteryPct: Double) -> TodayDashboardTint {
        batteryPct > 30 ? .recoveryGreen : .recoveryYellow
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
