import SwiftUI

struct TodayDashboardScoreSection: View {
    let cards: [TodayDashboardMetricCard]
    let onOpen: (TodayDashboardMetricKind) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(cards) { metricCard in
                Button {
                    onOpen(metricCard.kind)
                } label: {
                    TodayDashboardScoreDial(metricCard: metricCard)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct TodayDashboardScoreDial: View {
    let metricCard: TodayDashboardMetricCard

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(metricCard.tint.color.opacity(0.15), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: metricCard.progress)
                    .stroke(metricCard.tint.color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(metricCard.value)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(8)
            }
            .frame(width: 88, height: 88)

            HStack(spacing: 4) {
                Image(systemName: metricCard.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(metricCard.tint.color)
                Text(metricCard.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WH.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct TodayDashboardLiveChipRow: View {
    let liveChips: [TodayDashboardLiveChip]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(liveChips) { liveChip in
                HStack(spacing: 6) {
                    Image(systemName: liveChip.systemImage)
                        .font(.caption.weight(.bold))
                    Text(liveChip.value)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }
                .foregroundStyle(liveChip.tint.color)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(liveChip.tint.color.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }
}

struct TodayDashboardHealthMonitorSection: View {
    let cards: [TodayDashboardMetricCard]
    let onOpen: (TodayDashboardMetricKind) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TodayDashboardSectionHeader(title: "Health Monitor")

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(cards) { metricCard in
                    Button {
                        onOpen(metricCard.kind)
                    } label: {
                        TodayDashboardHealthMetricCard(metricCard: metricCard)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct TodayDashboardHealthMetricCard: View {
    let metricCard: TodayDashboardMetricCard

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: metricCard.systemImage)
                        .foregroundStyle(metricCard.tint.color)
                    Text(metricCard.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WH.Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 2)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(metricCard.value)
                        .font(.title3.bold())
                        .foregroundStyle(WH.Color.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    if !metricCard.unit.isEmpty {
                        Text(metricCard.unit)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WH.Color.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                Label(metricCard.status, systemImage: metricCard.value == "--" ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(metricCard.tint.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            Capsule()
                .fill(metricCard.tint.color.opacity(0.18))
                .frame(width: 8)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(metricCard.tint.color)
                        .frame(height: max(12, 52 * metricCard.progress))
                }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(12)
        .todayDashboardCardSurface(tint: metricCard.tint.color)
        .accessibilityElement(children: .combine)
    }
}

struct TodayDashboardTimelineSection: View {
    let items: [TodayDashboardTimelineItem]
    let onOpen: (TodayDashboardMetricKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TodayDashboardSectionHeader(title: "Timeline")

            VStack(spacing: 8) {
                ForEach(items) { item in
                    TodayDashboardTimelineRow(item: item) {
                        onOpen(item.metricKind)
                    }
                }
            }
        }
    }
}

struct TodayDashboardTimelineRow: View {
    let item: TodayDashboardTimelineItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.tint.color)
                    .frame(width: 36, height: 36)
                    .background(item.tint.color.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WH.Color.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(item.time)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WH.Color.textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }

                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.55))
            }
            .padding(14)
            .todayDashboardCardSurface(tint: item.tint.color)
        }
        .buttonStyle(.plain)
    }
}

struct TodayDashboardSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(WH.Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }
}

extension View {
    func todayDashboardCardSurface(tint: Color, prominent: Bool = false) -> some View {
        modifier(TodayDashboardCardSurfaceModifier(tint: tint, prominent: prominent))
    }
}

struct TodayDashboardCardSurfaceModifier: ViewModifier {
    let tint: Color
    let prominent: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(WH.Color.surface.opacity(prominent ? 1.0 : 0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(prominent ? 0.11 : 0.07),
                                        tint.opacity(prominent ? 0.04 : 0.025),
                                        .clear,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(prominent ? 0.18 : 0.10), radius: prominent ? 6 : 2, x: 0, y: prominent ? 4 : 1)
    }
}
