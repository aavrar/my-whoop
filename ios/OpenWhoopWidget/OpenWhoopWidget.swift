import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> MetricEntry {
        MetricEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (MetricEntry) -> Void) {
        completion(MetricEntry(date: Date(), snapshot: WidgetDataStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MetricEntry>) -> Void) {
        let entry = MetricEntry(date: Date(), snapshot: WidgetDataStore.read())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct MetricEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

// MARK: - Lock screen circular (recovery ring)

struct RecoveryCircularView: View {
    let entry: MetricEntry

    var recovery: Double? { entry.snapshot?.recovery }
    var band: String? { entry.snapshot?.recoveryBand }

    var ringColor: Color {
        switch band {
        case "green":  return Color(hex: "#16EC06")
        case "yellow": return Color(hex: "#FFDE00")
        default:       return Color(hex: "#FF0026")
        }
    }

    var body: some View {
        ZStack {
            if let r = recovery {
                Gauge(value: r, in: 0...100) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int(r))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(ringColor)
            } else {
                Gauge(value: 0, in: 0...100) {
                    EmptyView()
                } currentValueLabel: {
                    Text("—")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
                .tint(.secondary)
            }
        }
    }
}

// MARK: - Lock screen rectangular (recovery + HRV)

struct RecoveryRectangularView: View {
    let entry: MetricEntry

    var recovery: Double? { entry.snapshot?.recovery }
    var restingHr: Int?   { entry.snapshot?.restingHr }
    var hrv: Double?      { entry.snapshot?.avgHrv }
    var band: String?     { entry.snapshot?.recoveryBand }

    var bandColor: Color {
        switch band {
        case "green":  return Color(hex: "#16EC06")
        case "yellow": return Color(hex: "#FFDE00")
        default:       return Color(hex: "#FF0026")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RECOVERY")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let r = recovery {
                    Text("\(Int(r))%")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(bandColor)
                } else {
                    Text("—")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                if let rhr = restingHr {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("RHR")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("\(rhr)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                }
                if let h = hrv {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("HRV")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("\(Int(h))ms")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Home screen small

struct RecoverySmallView: View {
    let entry: MetricEntry

    var recovery: Double? { entry.snapshot?.recovery }
    var restingHr: Int?   { entry.snapshot?.restingHr }
    var strain: Double?   { entry.snapshot?.strain }
    var band: String?     { entry.snapshot?.recoveryBand }

    var bandColor: Color {
        switch band {
        case "green":  return Color(hex: "#16EC06")
        case "yellow": return Color(hex: "#FFDE00")
        default:       return Color(hex: "#FF0026")
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "#0B0B0F")
            VStack(spacing: 4) {
                Text("RECOVERY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "#8A8F98"))
                    .tracking(1)
                if let r = recovery {
                    Text("\(Int(r))%")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(bandColor)
                } else {
                    Text("—")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(Color(hex: "#8A8F98"))
                }
                HStack(spacing: 12) {
                    if let rhr = restingHr {
                        VStack(spacing: 1) {
                            Text("\(rhr)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("RHR")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color(hex: "#8A8F98"))
                        }
                    }
                    if let s = strain {
                        VStack(spacing: 1) {
                            Text(String(format: "%.1f", s))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(hex: "#0093E7"))
                            Text("STRAIN")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color(hex: "#8A8F98"))
                        }
                    }
                }
            }
            .padding()
        }
        .containerBackground(Color(hex: "#0B0B0F"), for: .widget)
    }
}

// MARK: - Widget entry point

struct OpenWhoopWidget: Widget {
    let kind = "OpenWhoopWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            OpenWhoopWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("OpenWhoop")
        .description("Recovery, resting HR, and strain at a glance.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}

struct OpenWhoopWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: MetricEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            RecoveryCircularView(entry: entry)
        case .accessoryRectangular:
            RecoveryRectangularView(entry: entry)
        default:
            RecoverySmallView(entry: entry)
        }
    }
}

// MARK: - Color hex (duplicated from main app — widget can't import WH tokens)

private extension Color {
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let scanner = Scanner(string: cleaned)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >>  8) & 0xFF) / 255
        let b = Double( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
