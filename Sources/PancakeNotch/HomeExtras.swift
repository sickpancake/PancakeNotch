import KeepAwakeCore
import NotchCore
import Stats
import SwiftUI

/// The number the Statistics widget shows, chosen in the Home editor (right-click → Show). Saved in the
/// layout's `statisticsMetric` as its raw value; anything unknown reads as notch opens.
enum HomeStatisticsMetric: String, CaseIterable, Identifiable {
    case opensToday
    case listeningThisWeek
    case shelvedThisWeek

    var id: String { rawValue }

    init(saved: String?) {
        self = saved.flatMap(Self.init(rawValue:)) ?? .opensToday
    }

    /// The menu item in the editor.
    var title: String {
        switch self {
        case .opensToday: String(localized: "Notch opens today", comment: "Statistics widget metric")
        case .listeningThisWeek: String(localized: "Listening this week", comment: "Statistics widget metric")
        case .shelvedThisWeek: String(localized: "Files shelved this week", comment: "Statistics widget metric")
        }
    }

    /// The small line under the number.
    var caption: String {
        switch self {
        case .opensToday: String(localized: "Opens today", comment: "Statistics widget caption")
        case .listeningThisWeek: String(localized: "Listened this week", comment: "Statistics widget caption")
        case .shelvedThisWeek: String(localized: "Shelved this week", comment: "Statistics widget caption")
        }
    }

    /// The caption on a Small widget, where only a word fits.
    var shortCaption: String {
        switch self {
        case .opensToday: String(localized: "Opens", comment: "Small Statistics widget caption: notch opens today")
        case .listeningThisWeek: String(localized: "Listened", comment: "Small Statistics widget caption: listening this week")
        case .shelvedThisWeek: String(localized: "Shelved", comment: "Small Statistics widget caption: files shelved this week")
        }
    }

    /// The number, from a summary of the last seven days (the last day is today).
    func value(in summary: StatsSummary) -> String {
        switch self {
        case .opensToday: (summary.opensPerDay.last ?? 0).formatted()
        case .listeningThisWeek: StatsFormat.duration(summary.listening.totalSeconds)
        case .shelvedThisWeek: summary.shelved.formatted()
        }
    }
}

/// The Home widgets that belong to no module: Battery and Statistics (ADR-0042).
@MainActor
enum HomeExtras {
    /// The real ones: the battery from IOKit, the statistics from the app's database.
    static func live(statistics: StatsStore, home: HomeSettings, readPower: @escaping () -> PowerState) -> HomeExtraWidgets {
        { kind, size, context in
            switch kind {
            case .battery:
                AnyView(HomeBatteryWidget(size: size, isLive: context.isLive, read: readPower))
            case .statistics:
                AnyView(HomeStatisticsWidget(size: size, isLive: context.isLive,
                                             metric: HomeStatisticsMetric(saved: home.layout.statisticsMetric),
                                             load: { await statistics.summary(days: 7) }))
            default:
                nil
            }
        }
    }

    /// Fixed numbers for pictures and practice: 76% on battery, 23 opens today, 4 h 12 min, 9 files.
    static func practice(home: HomeSettings? = nil) -> HomeExtraWidgets {
        { kind, size, _ in
            switch kind {
            case .battery:
                AnyView(HomeBatteryWidget(size: size, isLive: false, read: { PowerState(onBattery: true, percent: 76) }))
            case .statistics:
                AnyView(HomeStatisticsWidget(size: size, isLive: false,
                                             metric: HomeStatisticsMetric(saved: home?.layout.statisticsMetric),
                                             fixed: practiceSummary))
            default:
                nil
            }
        }
    }

    private static var practiceSummary: StatsSummary {
        var summary = StatsSummary(opensPerDay: [31, 18, 27, 12, 40, 22, 23])
        summary.totalOpens = summary.opensPerDay.reduce(0, +)
        summary.listening.totalSeconds = 4 * 3600 + 12 * 60
        summary.shelved = 9
        return summary
    }
}

// MARK: Battery

/// Small: the charge and whether it's on the battery. Medium: a ring with the same. It reads the battery
/// when it comes on screen and then only when macOS says the power changed (no polling, AGENTS.md rule 2).
private struct HomeBatteryWidget: View {
    let size: HomeWidgetSize
    let isLive: Bool
    let read: () -> PowerState

    @State private var power: PowerState?
    @State private var watcher = PowerSourceWatcher()

    var body: some View {
        let power = power ?? read()
        Group {
            switch size {
            case .small, .large:
                HomeSmallFace(caption: Self.source(power)) {
                    Image(systemName: Self.symbol(power))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                } value: {
                    Text(Self.percent(power))
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText(value: Double(power.percent ?? 0)))
                }
            case .medium:
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.2), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: max(0.02, Double(power.percent ?? 100) / 100))
                            .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: power.onBattery ? "battery.100percent" : "bolt.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.percent(power))
                            .font(.system(size: 17, weight: .semibold).monospacedDigit())
                            .contentTransition(.numericText(value: Double(power.percent ?? 0)))
                        Text(Self.source(power))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: power)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(localized: "Battery, \(Self.percent(power)), \(Self.source(power))",
                                        comment: "Battery widget, spoken")))
        .onChange(of: isLive, initial: true) { _, live in
            if live {
                self.power = read()
                watcher.start { self.power = read() }
            } else {
                watcher.stop()
            }
        }
        .onDisappear { watcher.stop() }
    }

    private static func percent(_ power: PowerState) -> String {
        power.percent.map { "\($0)%" } ?? String(localized: "No battery", comment: "Battery widget")
    }

    private static func source(_ power: PowerState) -> String {
        power.onBattery ? String(localized: "On battery", comment: "Battery widget")
            : String(localized: "Plugged in", comment: "Battery widget")
    }

    private static func symbol(_ power: PowerState) -> String {
        guard power.onBattery else { return "battery.100percent.bolt" }
        switch power.percent ?? 100 {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: Statistics

/// One number from the Statistics page, read each time Home opens (no repeating reads, ADR-0042).
private struct HomeStatisticsWidget: View {
    let size: HomeWidgetSize
    let isLive: Bool
    let metric: HomeStatisticsMetric
    var load: (@Sendable () async -> StatsSummary)?
    var fixed: StatsSummary?

    @State private var summary: StatsSummary?

    init(size: HomeWidgetSize, isLive: Bool, metric: HomeStatisticsMetric,
         load: (@Sendable () async -> StatsSummary)? = nil, fixed: StatsSummary? = nil) {
        self.size = size
        self.isLive = isLive
        self.metric = metric
        self.load = load
        self.fixed = fixed
        _summary = State(initialValue: fixed)
    }

    var body: some View {
        let value = summary.map(metric.value(in:)) ?? "–"
        Group {
            switch size {
            case .small, .large:
                HomeSmallFace(caption: metric.shortCaption) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                } value: {
                    Text(value)
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
            case .medium:
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(value)
                            .font(.system(size: 19, weight: .semibold).monospacedDigit())
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(metric.caption)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let summary, metric == .opensToday {
                        WeekBars(values: summary.opensPerDay.suffix(7).map(Double.init))
                            .frame(width: 58, height: 26)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(metric.caption): \(value)"))
        .accessibilityHint(Text("Opens the Statistics page."))
        .task(id: isLive) {
            guard isLive, fixed == nil, let load else { return }
            let next = await load()
            if !Task.isCancelled { summary = next }
        }
    }
}

/// The last seven days as small bars, today brightest.
private struct WeekBars: View {
    let values: [Double]

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(values.indices, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(index == values.count - 1 ? 0.9 : 0.3))
                    .frame(height: max(3, 26 * values[index] / top))
            }
        }
        .accessibilityHidden(true)
    }
}
