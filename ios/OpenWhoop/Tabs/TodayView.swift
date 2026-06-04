import SwiftUI
import WhoopStore

struct TodayView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var live: LiveViewModel

    @State private var dayOffset = 0
    @State private var browsedMetric: DailyMetric?
    @State private var browsedSession: CachedSleepSession?
    @State private var isLoadingDay = false
    @State private var navDirection = 0
    @State private var dashboardPath: [TodayDashboardMetricKind] = []

    private var shownMetric: DailyMetric? { browsedMetric }
    private var shownSession: CachedSleepSession? { browsedSession }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }

    private var anchorToday: Date {
        calendar.startOfDay(for: Date())
    }

    private var dashboardModel: TodayDashboardModel {
        TodayDashboardAdapter.make(
            metric: shownMetric,
            session: shownSession,
            live: TodayDashboardLiveState(
                connected: live.state.connected,
                heartRate: live.state.heartRate,
                batteryPct: live.state.batteryPct
            )
        )
    }

    var body: some View {
        NavigationStack(path: $dashboardPath) {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                Group {
                    if metrics.isRefreshing && metrics.today == nil && metrics.lastNight == nil {
                        loadingView
                    } else {
                        scrollContent
                            .id(dayOffset)
                            .transition(.asymmetric(
                                insertion: .move(edge: navDirection < 0 ? .trailing : .leading),
                                removal: .move(edge: navDirection < 0 ? .leading : .trailing)
                            ))
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TodayDashboardMetricKind.self) { metricKind in
                dashboardDestination(for: metricKind)
            }
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                        if value.translation.width < -40 {
                            navigateDay(by: -1)
                        } else if value.translation.width > 40 {
                            navigateDay(by: 1)
                        }
                    }
            )
        }
        .preferredColorScheme(.dark)
        .task {
            await metrics.load()
            await loadBrowsedDay(offset: dayOffset)
        }
        .refreshable {
            guard dayOffset == 0 else { return }
            await refreshCurrentDay()
        }
    }

    private var loadingView: some View {
        VStack(spacing: WH.Spacing.md) {
            ProgressView().tint(WH.Color.textSecondary)
            Text("Loading metrics...")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(headerTitle) {
                    headerControls
                }

                if isLoadingDay {
                    HStack {
                        Spacer()
                        ProgressView().tint(WH.Color.textSecondary)
                        Spacer()
                    }
                    .padding(.vertical, WH.Spacing.xl)
                } else {
                    let dashboard = dashboardModel

                    TodayDashboardScoreSection(cards: dashboard.scoreCards, onOpen: openDashboardMetric)

                    if !dashboard.liveChips.isEmpty {
                        TodayDashboardLiveChipRow(liveChips: dashboard.liveChips)
                    }

                    TodayDashboardHealthMonitorSection(cards: dashboard.healthCards, onOpen: openDashboardMetric)

                    TodayDashboardTimelineSection(items: dashboard.timelineItems, onOpen: openDashboardMetric)

                    if dayOffset == 0 {
                        processButton
                    }
                }

                if let errorMessage = metrics.lastError {
                    errorBanner(errorMessage)
                }

                syncFooter

                Spacer(minLength: WH.Spacing.xl)
            }
            .padding(.horizontal, WH.Spacing.md)
            .padding(.vertical, WH.Spacing.md)
        }
        .background(WH.Color.background)
    }

    private var headerControls: some View {
        HStack(spacing: WH.Spacing.sm) {
            if dayOffset < 0 {
                Button { navigateDay(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WH.Color.strainBlue)
                }
            }
            Text(dateLabel)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .animation(nil, value: dayOffset)
            Button { navigateDay(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WH.Color.strainBlue)
            }
        }
    }

    private var processButton: some View {
        Button { Task { await refreshCurrentDay() } } label: {
            HStack(spacing: WH.Spacing.sm) {
                if metrics.isRefreshing {
                    ProgressView().scaleEffect(0.8).tint(.white)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(metrics.isRefreshing ? "Processing..." : "Process Sleep Data")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(WH.Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(WH.Color.textPrimary)
        }
        .disabled(metrics.isRefreshing)
    }

    private var syncFooter: some View {
        HStack {
            if metrics.isRefreshing {
                HStack(spacing: WH.Spacing.xs) {
                    ProgressView().scaleEffect(0.7).tint(WH.Color.textSecondary)
                    Text("Updating").font(WH.Font.caption).foregroundStyle(WH.Color.textSecondary)
                }
            } else if let lastRefreshedAt = metrics.lastRefreshedAt {
                Text("Updated \(relativeTime(from: lastRefreshedAt))")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }
            Spacer()
        }
    }

    private var headerTitle: String {
        if dayOffset == 0 { return "Today" }
        if dayOffset == -1 { return "Yesterday" }
        guard let browsedDate = browsedDate(dayOffset) else { return "--" }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: browsedDate)
    }

    private var dateLabel: String {
        guard let browsedDate = browsedDate(dayOffset) else { return "--" }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MM/dd/yy"
        return formatter.string(from: browsedDate)
    }

    private func browsedDate(_ offset: Int) -> Date? {
        calendar.date(byAdding: .day, value: offset, to: anchorToday)
    }

    private func navigateDay(by delta: Int) {
        let nextOffset = dayOffset + delta
        guard nextOffset <= 0 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            navDirection = delta
            dayOffset = nextOffset
        }
        Task { await loadBrowsedDay(offset: nextOffset) }
    }

    private func loadBrowsedDay(offset: Int) async {
        isLoadingDay = true
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let targetDate = browsedDate(offset) else {
            isLoadingDay = false
            return
        }
        let day = formatter.string(from: targetDate)
        let (dailyMetric, sleepSession) = await metrics.metricsForDay(day)
        if offset == 0, dailyMetric == nil, let latestMetric = metrics.today {
            browsedMetric = latestMetric
        } else {
            browsedMetric = dailyMetric
        }
        browsedSession = sleepSession ?? (offset == 0 ? metrics.lastNight : nil)
        isLoadingDay = false
    }

    private func refreshCurrentDay() async {
        await metrics.refresh()
        await loadBrowsedDay(offset: dayOffset)
    }

    private func openDashboardMetric(_ metricKind: TodayDashboardMetricKind) {
        dashboardPath.append(metricKind)
    }

    @ViewBuilder
    private func dashboardDestination(for metricKind: TodayDashboardMetricKind) -> some View {
        switch metricKind {
        case .sleep, .respiratoryRate, .skinTemperature:
            MetricDetailView(kind: .sleepDuration)
        case .recovery:
            MetricDetailView(kind: .recovery)
        case .strain, .calories:
            MetricDetailView(kind: .strain)
        case .heartRateVariability:
            MetricDetailView(kind: .hrv)
        case .restingHeartRate:
            MetricDetailView(kind: .rhr)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WH.Color.recoveryYellow)
            Text(message)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(WH.Spacing.sm)
        .background(WH.Color.surface2, in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
    }

    private func relativeTime(from date: Date) -> String {
        let elapsedSeconds = max(Int(-date.timeIntervalSinceNow), 0)
        if elapsedSeconds < 5 { return "just now" }
        if elapsedSeconds < 60 { return "\(elapsedSeconds)s ago" }
        if elapsedSeconds < 3600 { return "\(elapsedSeconds / 60)m ago" }
        return "\(elapsedSeconds / 3600)h ago"
    }
}

#Preview("Today") {
    TodayView()
        .environmentObject(MetricsRepository(deviceId: "preview"))
        .environmentObject(LiveViewModel())
}
