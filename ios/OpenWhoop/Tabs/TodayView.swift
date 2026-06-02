import SwiftUI
import WhoopStore

struct TodayView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var live: LiveViewModel

    // Day browsing — 0 = today (UTC), negative = days into the past. Anchored to the actual
    // calendar day in UTC (daily rows are keyed by UTC day strings), so the label always matches
    // the data shown. Today legitimately reads "pending" until last night's sleep has synced.
    @State private var dayOffset = 0
    @State private var browsedMetric: DailyMetric?
    @State private var browsedSession: CachedSleepSession?
    @State private var isLoadingDay = false
    @State private var navDirection = 0  // -1 going back, +1 going forward, for transition

    private var shownMetric: DailyMetric? { browsedMetric }
    private var shownSession: CachedSleepSession? { browsedSession }

    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current; return c
    }
    private var anchorToday: Date { utcCalendar.startOfDay(for: Date()) }

    var body: some View {
        NavigationStack {
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
                                removal:   .move(edge: navDirection < 0 ? .leading  : .trailing)
                            ))
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { v in
                        guard abs(v.translation.width) > abs(v.translation.height) * 1.2 else { return }
                        if v.translation.width < -40 { navigateDay(by: -1) }
                        else if v.translation.width > 40 { navigateDay(by: 1) }
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
            await metrics.refresh()
            await loadBrowsedDay(offset: dayOffset)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: WH.Spacing.md) {
            ProgressView().tint(WH.Color.textSecondary)
            Text("Loading metrics…")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WH.Spacing.lg) {

                ScreenHeader(headerTitle) {
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

                if isLoadingDay {
                    HStack { Spacer(); ProgressView().tint(WH.Color.textSecondary); Spacer() }
                        .padding(.vertical, WH.Spacing.xl)
                } else {
                    heroSection

                    NavigationLink(destination: MetricDetailView(kind: .strain)) {
                        strainCard
                    }.buttonStyle(.plain)

                    NavigationLink(destination: MetricDetailView(kind: .sleepDuration)) {
                        sleepCard
                    }.buttonStyle(.plain)

                    hrvAndRhrRow

                    if dayOffset == 0 { processButton }
                }

                if let err = metrics.lastError { errorBanner(err) }

                if shownMetric == nil && shownSession == nil && !metrics.isRefreshing && !isLoadingDay {
                    emptyState
                }

                strapNote
                if dayOffset == 0 { syncFooter }

                Spacer(minLength: WH.Spacing.xl)
            }
            .padding(WH.Spacing.md)
        }
        .background(WH.Color.background)
    }

    // MARK: - Day navigation

    private func browsedDate(_ offset: Int) -> Date? {
        utcCalendar.date(byAdding: .day, value: offset, to: anchorToday)
    }

    private var headerTitle: String {
        if dayOffset == 0 { return "Today" }
        if dayOffset == -1 { return "Yesterday" }
        guard let d = browsedDate(dayOffset) else { return "—" }
        let fmt = DateFormatter(); fmt.timeZone = TimeZone.current; fmt.dateFormat = "EEE, MMM d"
        return fmt.string(from: d)
    }

    private var dateLabel: String {
        guard let d = browsedDate(dayOffset) else { return "—" }
        let fmt = DateFormatter(); fmt.timeZone = TimeZone.current; fmt.dateFormat = "MM/dd/yy"
        return fmt.string(from: d)
    }

    private func navigateDay(by delta: Int) {
        let next = dayOffset + delta
        guard next <= 0 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            navDirection = delta
            dayOffset = next
        }
        Task { await loadBrowsedDay(offset: next) }
    }

    private func loadBrowsedDay(offset: Int) async {
        isLoadingDay = true
        let fmt = DateFormatter()
        fmt.calendar = utcCalendar
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        guard let targetDate = browsedDate(offset) else { isLoadingDay = false; return }
        let day = fmt.string(from: targetDate)
        let (daily, session) = await metrics.metricsForDay(day)
        // Wall-clock "today" may have no daily row yet while the band RTC was ahead; fall back to
        // the most-recent computed day so recovery/strain aren't blank after a skew repair.
        if offset == 0, daily == nil, let latest = metrics.today {
            browsedMetric = latest
        } else {
            browsedMetric = daily
        }
        browsedSession = session ?? (offset == 0 ? metrics.lastNight : nil)
        isLoadingDay = false
    }

    // MARK: - Hero (recovery ring)

    private var heroSection: some View {
        HStack {
            Spacer()
            NavigationLink(destination: MetricDetailView(kind: .recovery)) {
                if let recovery = shownMetric?.recovery {
                    RecoveryRing(percent: recovery * 100, size: 200, strokeWidth: 16)
                } else {
                    pendingRecoveryRing
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, WH.Spacing.sm)
    }

    private var pendingRecoveryRing: some View {
        ZStack {
            Circle().stroke(WH.Color.ringTrack, lineWidth: 16)
            Circle().stroke(WH.Color.ringTrack.opacity(0.5), lineWidth: 24).blur(radius: 6)
            VStack(spacing: WH.Spacing.xs) {
                Text("—")
                    .font(WH.Font.metricHero(size: 64))
                    .foregroundStyle(WH.Color.textSecondary)
                    .monospacedDigit()
                Text("RECOVERY")
                    .font(WH.Font.cardTitle)
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.5)
                Text("Pending")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.7))
            }
        }
        .frame(width: 200, height: 200)
    }

    // MARK: - Strain card

    private var strainCard: some View {
        let value: String = {
            guard let s = shownMetric?.strain else { return "—" }
            return String(format: "%.1f", s)
        }()
        let hasStrain = shownMetric?.strain != nil
        return VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            MetricCard(title: "Day Strain",
                       value: value,
                       unit: hasStrain ? "/ 21" : nil,
                       accentColor: hasStrain ? WH.Color.strainBlue : WH.Color.textSecondary)
            if let cal = shownMetric?.calories {
                Text("\(Int(cal)) cal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary)
                    .padding(.horizontal, WH.Spacing.md)
                    .padding(.bottom, WH.Spacing.xs)
            }
        }
    }

    // MARK: - Sleep card

    private var sleepCard: some View {
        let sleepMin: Double? = {
            if let m = shownMetric?.totalSleepMin, m > 0 { return m }
            if let s = shownSession { let d = Double(s.endTs - s.startTs) / 60; return d > 0 ? d : nil }
            return nil
        }()
        let efficiency: Double? = {
            guard sleepMin != nil else { return nil }
            if let e = shownMetric?.efficiency, e > 0 { return e }
            if let e = shownSession?.efficiency, e > 0 { return e }
            return nil
        }()
        return VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            HStack {
                Text("LAST NIGHT")
                    .font(WH.Font.cardTitle)
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.2)
                Spacer()
            }
            if let min = sleepMin {
                HStack(alignment: .lastTextBaseline, spacing: WH.Spacing.sm) {
                    Text(formatSleepMinutes(min))
                        .font(WH.Font.metricLarge())
                        .foregroundStyle(WH.Color.textPrimary)
                        .monospacedDigit()
                    if let eff = efficiency {
                        Text("·  \(Int((eff * 100).rounded()))% efficiency")
                            .font(WH.Font.unit)
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("No sleep data")
                    .font(WH.Font.metricMedium())
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface, in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    // MARK: - HRV + RHR row

    private var hrvAndRhrRow: some View {
        HStack(spacing: WH.Spacing.sm) {
            NavigationLink(destination: MetricDetailView(kind: .hrv)) {
                hrvCard.frame(maxWidth: .infinity)
            }.buttonStyle(.plain)
            NavigationLink(destination: MetricDetailView(kind: .rhr)) {
                rhrCard.frame(maxWidth: .infinity)
            }.buttonStyle(.plain)
        }
    }

    private var hrvCard: some View {
        let hrv = shownMetric?.avgHrv ?? shownSession?.avgHrv
        return MetricCard(title: "HRV",
                          value: hrv.map { String(format: "%.0f", $0) } ?? "—",
                          unit: hrv != nil ? "ms" : nil,
                          accentColor: hrv != nil ? WH.Color.recoveryGreen : WH.Color.textSecondary)
    }

    private var rhrCard: some View {
        let rhr = shownMetric?.restingHr ?? shownSession?.restingHr
        return MetricCard(title: "Resting HR",
                          value: rhr.map { "\($0)" } ?? "—",
                          unit: rhr != nil ? "bpm" : nil,
                          accentColor: rhr != nil ? WH.Color.textPrimary : WH.Color.textSecondary)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: WH.Spacing.sm) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(WH.Color.textSecondary)
                Text(dayOffset == 0 ? "No metrics yet" : "No data for this day")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                if dayOffset == 0 {
                    Text("Pull down to refresh")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }
            .padding(.vertical, WH.Spacing.xxl)
            Spacer()
        }
    }

    // MARK: - Live strap chips

    private func liveChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: WH.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, WH.Spacing.sm)
        .padding(.vertical, WH.Spacing.xs)
        .background(WH.Color.surface2, in: Capsule())
    }

    private var strapNote: some View {
        Group {
            if live.state.connected, let hr = live.state.heartRate {
                HStack(spacing: WH.Spacing.sm) {
                    liveChip(icon: "heart.fill", label: "\(hr) BPM LIVE", color: WH.Color.recoveryRed)
                    if let bat = live.state.batteryPct {
                        let pct = Int(bat.rounded())
                        let batColor: Color = pct > 30 ? WH.Color.recoveryGreen : WH.Color.recoveryYellow
                        let batIcon = pct > 70 ? "battery.100" : pct > 30 ? "battery.50" : "battery.25"
                        liveChip(icon: batIcon, label: "\(pct)%", color: batColor)
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: WH.Spacing.xs) {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
                    Text("Live HR & battery appear when your strap is connected (Device tab)")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary.opacity(0.5))
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Process + sync footer

    private var processButton: some View {
        Button { Task { await metrics.refresh(); await loadBrowsedDay(offset: dayOffset) } } label: {
            HStack(spacing: WH.Spacing.sm) {
                if metrics.isRefreshing {
                    ProgressView().scaleEffect(0.8).tint(.white)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(metrics.isRefreshing ? "Processing…" : "Process Sleep Data")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(WH.Color.surface)
            .foregroundStyle(WH.Color.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(metrics.isRefreshing)
    }

    private var syncFooter: some View {
        HStack {
            if metrics.isRefreshing {
                HStack(spacing: WH.Spacing.xs) {
                    ProgressView().scaleEffect(0.7).tint(WH.Color.textSecondary)
                    Text("Updating…").font(WH.Font.caption).foregroundStyle(WH.Color.textSecondary)
                }
            } else if let at = metrics.lastRefreshedAt {
                Text("Updated \(relativeTime(from: at))")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WH.Color.recoveryYellow)
            Text(message).font(WH.Font.caption).foregroundStyle(WH.Color.textSecondary).lineLimit(2)
            Spacer()
        }
        .padding(WH.Spacing.sm)
        .background(WH.Color.surface2, in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
    }

    // MARK: - Formatting

    private func formatSleepMinutes(_ totalMin: Double) -> String {
        guard totalMin > 0 else { return "—" }
        let hours = Int(totalMin) / 60
        let mins  = Int(totalMin) % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0              { return "\(hours)h" }
        return "\(mins)m"
    }

    private func relativeTime(from date: Date) -> String {
        let elapsed = Int(-date.timeIntervalSinceNow)
        switch elapsed {
        case ..<5:    return "just now"
        case ..<60:   return "\(elapsed)s ago"
        case ..<3600: return "\(elapsed / 60)m ago"
        default:      return "\(elapsed / 3600)h ago"
        }
    }
}

#Preview("Today — empty") {
    TodayView()
        .environmentObject(MetricsRepository(deviceId: "preview"))
        .environmentObject(LiveViewModel())
}
