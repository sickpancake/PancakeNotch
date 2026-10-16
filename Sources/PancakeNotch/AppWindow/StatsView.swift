import AppKit
import Charts
import Stats
import SwiftUI

/// The Statistics page (ADR-0018): what was listened to, how the notch is used, and how much memory
/// and CPU PancakeNotch itself takes. Everything comes from the local statistics file; nothing is
/// sent anywhere. The only thing that refreshes on its own is the live memory and CPU read-out,
/// once a second and only while this page is on screen.
struct StatsView: View {
    let store: StatsStore
    /// The Now Playing helper's process id, for the live memory figure (nil when it isn't running).
    let helperPID: () -> pid_t?

    @State private var range: StatsRange = .week
    @State private var summary: StatsSummary?
    /// The listening and usage sections fade in once the first summary has loaded.
    @State private var isShown = false
    /// Clear Statistics just ran: says so until the page is left.
    @State private var justCleared = false
    /// Bumped after Clear, so the summary loads again.
    @State private var generation = 0
    @State private var apps: [String: ListeningApp] = [:]
    @State private var confirmingClear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let data = summary ?? .empty
        AppPage(
            title: String(localized: "Statistics"),
            subtitle: String(localized: "What you listened to and how you use the notch. Kept only on this Mac.")
        ) {
            StatsSection(title: String(localized: "Listening")) {
                MonochromeSegmented(
                    title: String(localized: "Time range"),
                    options: StatsRange.allCases.map { (value: $0, label: $0.label) },
                    selection: $range
                )
            } content: {
                ListeningContent(summary: data, range: range, apps: apps)
            }
            .opacity(isShown ? 1 : 0)
            .accessibilityHidden(!isShown)

            StatsSection(title: String(localized: "Usage")) {
                UsageContent(summary: data, range: range)
            }
            .opacity(isShown ? 1 : 0)
            .accessibilityHidden(!isShown)

            StatsSection(title: String(localized: "App health")) {
                HealthContent(samples: data.health, range: range, helperPID: helperPID)
            }

            SettingsCard {
                SettingsRow(
                    title: String(localized: "Your statistics"),
                    subtitle: justCleared
                        ? String(localized: "Cleared. New statistics start from now.")
                        : String(localized: "Kept for 90 days, only on this Mac. Nothing is ever sent anywhere.")
                ) {
                    // Two clicks, like Clear Shelf.
                    Button(confirmingClear ? String(localized: "Clear All Statistics?") : String(localized: "Clear Statistics")) {
                        if confirmingClear {
                            store.clear()
                            generation += 1
                            justCleared = true
                            AccessibilityNotification.Announcement(String(localized: "Statistics cleared")).post()
                        }
                        confirmingClear.toggle()
                    }
                    .accessibilityHint(Text(confirmingClear
                        ? String(localized: "Click again to delete all statistics.")
                        : String(localized: "Deletes everything on this page. Asks once more first.")))
                }
            }
        }
        .task(id: LoadKey(range: range, generation: generation)) {
            let loaded = await store.summary(days: range.days)
            guard !Task.isCancelled else { return }
            var resolved = apps
            for app in loaded.topApps where resolved[app.id] == nil {
                resolved[app.id] = ListeningApp.resolve(app.id)
            }
            apps = resolved
            // The first summary fills the sections while they're still hidden, so their "Nothing yet"
            // cards don't cross-fade with the real numbers as the page appears.
            if summary == nil { summary = loaded }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                summary = loaded
                isShown = true
            }
        }
        .onChange(of: range) { confirmingClear = false }
        .onDisappear { confirmingClear = false }
    }
}

// MARK: - Range

private enum StatsRange: Int, Hashable, CaseIterable {
    case week = 7
    case month = 30
    case quarter = 90

    var days: Int { rawValue }

    var label: String {
        switch self {
        case .week: String(localized: "7 days")
        case .month: String(localized: "30 days")
        case .quarter: String(localized: "90 days")
        }
    }

    /// Under the big numbers: "in the last 7 days".
    var caption: String {
        switch self {
        case .week: String(localized: "in the last 7 days")
        case .month: String(localized: "in the last 30 days")
        case .quarter: String(localized: "in the last 90 days")
        }
    }

    /// Every how many days the charts label a bar, counting back from today.
    var labelStride: Int {
        switch self {
        case .week: 1
        case .month: 7
        case .quarter: 15
        }
    }
}

private struct LoadKey: Hashable {
    let range: StatsRange
    let generation: Int
}

// MARK: - Listening

private struct ListeningContent: View {
    let summary: StatsSummary
    let range: StatsRange
    let apps: [String: ListeningApp]

    var body: some View {
        if summary.totalPlays == 0 {
            EmptyCard(symbol: "music.note", text: String(localized: "Nothing yet. Play some music and it shows up here."))
        } else {
            HStack(spacing: 12) {
                StatsTile(
                    label: String(localized: "Time listened"),
                    symbol: "headphones",
                    value: StatsFormat.duration(summary.totalListeningSeconds),
                    caption: range.caption
                )
                StatsTile(
                    label: String(localized: "Songs played"),
                    symbol: "music.note",
                    value: summary.totalPlays.formatted(),
                    caption: range.caption
                )
                topAppTile
            }
            .fixedSize(horizontal: false, vertical: true)

            let hours = (summary.listeningSecondsPerDay.max() ?? 0) > 3 * 3_600
            DailyBarCard(
                title: hours ? String(localized: "Hours listened per day") : String(localized: "Minutes listened per day"),
                days: summary.days,
                values: summary.listeningSecondsPerDay.map { hours ? $0 / 3_600 : $0 / 60 },
                range: range,
                minimumTop: hours ? 4 : 10,
                axisName: hours ? String(localized: "Hours") : String(localized: "Minutes"),
                valueText: { value in StatsFormat.duration(hours ? value * 3_600 : value * 60) },
                detail: String(localized: "About \(StatsFormat.duration(summary.totalListeningSeconds / Double(max(summary.days.count, 1)))) a day")
            )

            HStack(alignment: .top, spacing: 12) {
                RankedCard(title: String(localized: "Top songs")) {
                    ForEach(Array(summary.topSongs.enumerated()), id: \.element.id) { index, song in
                        RankedRow(
                            rank: index + 1,
                            title: song.title,
                            subtitle: song.subtitle,
                            value: StatsFormat.duration(song.value),
                            fraction: fraction(song, in: summary.topSongs)
                        )
                    }
                }
                RankedCard(title: String(localized: "Top artists")) {
                    ForEach(Array(summary.topArtists.enumerated()), id: \.element.id) { index, artist in
                        RankedRow(
                            rank: index + 1,
                            title: artist.title,
                            subtitle: StatsFormat.plays(artist.count),
                            value: StatsFormat.duration(artist.value),
                            fraction: fraction(artist, in: summary.topArtists)
                        )
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if !summary.topApps.isEmpty {
                RankedCard(title: String(localized: "Top apps")) {
                    ForEach(Array(summary.topApps.enumerated()), id: \.element.id) { index, app in
                        let info = apps[app.id] ?? ListeningApp(name: app.id, icon: nil)
                        RankedRow(
                            rank: index + 1,
                            title: info.name,
                            subtitle: StatsFormat.plays(app.count),
                            value: StatsFormat.duration(app.value),
                            fraction: fraction(app, in: summary.topApps),
                            icon: { ListeningAppIcon(image: info.icon) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var topAppTile: some View {
        if let top = summary.topApps.first {
            let info = apps[top.id] ?? ListeningApp(name: top.id, icon: nil)
            StatsTile(
                label: String(localized: "Top app"),
                symbol: "play.circle",
                value: info.name,
                caption: String(localized: "\(StatsFormat.duration(top.value)) listened"),
                icon: info.icon
            )
        } else {
            StatsTile(
                label: String(localized: "Top app"),
                symbol: "play.circle",
                value: "–",
                caption: String(localized: "No app known yet")
            )
        }
    }

    private func fraction(_ item: RankedItem, in items: [RankedItem]) -> Double {
        let top = items.map(\.value).max() ?? 0
        return top > 0 ? item.value / top : 0
    }
}

// MARK: - Usage

private struct UsageContent: View {
    let summary: StatsSummary
    let range: StatsRange

    var body: some View {
        HStack(spacing: 12) {
            StatsTile(
                label: String(localized: "Notch opens"),
                symbol: "cursorarrow.rays",
                value: summary.totalOpens.formatted(),
                caption: range.caption
            )
            StatsTile(
                label: String(localized: "Files shelved"),
                symbol: "tray.and.arrow.down",
                value: summary.shelved.formatted(),
                caption: range.caption
            )
            StatsTile(
                label: String(localized: "AirDropped"),
                symbol: "dot.radiowaves.left.and.right",
                value: summary.airDropped.formatted(),
                caption: range.caption
            )
        }
        .fixedSize(horizontal: false, vertical: true)

        DailyBarCard(
            title: String(localized: "Notch opens per day"),
            days: summary.days,
            values: summary.opensPerDay.map(Double.init),
            range: range,
            minimumTop: 4,
            axisName: String(localized: "Opens"),
            valueText: { StatsFormat.opens(Int($0.rounded())) },
            detail: String(localized: "About \(Self.average(summary.totalOpens, over: summary.days.count)) a day"),
            emptyText: String(localized: "The notch hasn't opened yet in this time.")
        )

        RankedCard(title: String(localized: "Most-used modules")) {
            if summary.moduleUses.isEmpty {
                Text("No modules used yet. They show up here once the notch opens with them.")
                    .font(.app(size: 12.5))
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let top = summary.moduleUses.map(\.value).max() ?? 0
                ForEach(Array(summary.moduleUses.enumerated()), id: \.element.id) { index, module in
                    RankedRow(
                        rank: index + 1,
                        title: StatsFormat.moduleName(module.id),
                        subtitle: nil,
                        value: StatsFormat.times(module.count),
                        fraction: top > 0 ? module.value / top : 0,
                        icon: { SymbolIcon(symbol: StatsFormat.moduleSymbol(module.id)) }
                    )
                }
            }
        }
    }

    private static func average(_ total: Int, over days: Int) -> String {
        let value = Double(total) / Double(max(days, 1))
        return value.formatted(.number.precision(.fractionLength(value < 10 ? 0...1 : 0...0)))
    }
}

// MARK: - App health

private struct HealthContent: View {
    let samples: [HealthSample]
    let range: StatsRange
    let helperPID: () -> pid_t?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                LiveHealth(helperPID: helperPID)
                AppPalette.hairline.frame(height: 1)
                MemoryHistory(samples: samples, range: range)
                    .padding(AppMetrics.cardInset)
            }
            .glassPanel()
            Text("Memory is how much PancakeNotch uses, music helper included (Activity Monitor shows the same number). In the background it should stay under 50 MB; with this window open it uses a bit more. CPU near 0% means it's resting. A reading is saved now and then when the notch opens.")
                .font(.app(size: 12.5))
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppMetrics.cardInset)
        }
    }
}

/// Memory and CPU right now, read once a second while this page is on screen. The loop belongs
/// to `.task`, so it stops as soon as the page goes away.
private struct LiveHealth: View {
    let helperPID: () -> pid_t?
    @State private var latest: HealthSample?
    /// The window is on screen (not minimised, hidden or covered): only then does the read-out tick.
    @State private var isVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let total = latest?.totalFootprintBytes ?? 0
        let budgetFraction = Double(total) / Double(StatsFormat.idleBudgetBytes)
        let memoryText = latest.map { StatsFormat.megabytes($0.totalFootprintBytes) } ?? "–"
        let cpuText = latest.map { StatsFormat.percent($0.cpuPercent) } ?? "–"
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TileHeading(label: String(localized: "Memory now"), symbol: "memorychip")
                Text(memoryText)
                    .font(.app(size: 34, weight: .bold))
                    .kerning(-0.8)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.top, 14)
                BudgetMeter(fraction: budgetFraction)
                    .padding(.top, 12)
                Text(caption(total: total))
                    .font(.app(size: 12))
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .padding(.horizontal, AppMetrics.cardInset)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Memory now"))
            .accessibilityValue(Text(latest.map { "\(StatsFormat.megabytes($0.totalFootprintBytes)). \(caption(total: total))" } ?? ""))

            AppPalette.hairline.frame(width: 1)

            VStack(alignment: .leading, spacing: 0) {
                TileHeading(label: String(localized: "CPU now"), symbol: "cpu")
                Text(cpuText)
                    .font(.app(size: 34, weight: .bold))
                    .kerning(-0.8)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.top, 14)
                Text("of one processor core, over the last second")
                    .font(.app(size: 12))
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .padding(.horizontal, AppMetrics.cardInset)
            .padding(.vertical, 18)
            .frame(width: 230, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("CPU now"))
            .accessibilityValue(Text(latest.map { StatsFormat.percent($0.cpuPercent) } ?? ""))
        }
        .fixedSize(horizontal: false, vertical: true)
        // Animates when a shown number changes, not on every reading (each one has a new time).
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: [memoryText, cpuText])
        .task(id: isVisible) {
            guard isVisible else { return }
            var sampler = HealthSampler(interval: 0)
            // The first reading averages CPU since launch: it only sets the baseline.
            var isFirst = true
            while !Task.isCancelled {
                let sample = sampler.sample(now: .now, helperPID: helperPID())
                if isFirst {
                    isFirst = false
                    if latest == nil { latest = sample.map { HealthSample(date: $0.date, footprintBytes: $0.footprintBytes, helperFootprintBytes: $0.helperFootprintBytes, cpuPercent: 0) } }
                } else {
                    latest = sample
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        // Minimised, hidden (⌘H) or covered: the window's still there, but nobody sees the numbers.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            // Only the app window: Sparkle's update window or others would stop (or restart) the readings.
            guard let window = note.object as? NSWindow, window.frameAutosaveName == "AppWindow" else { return }
            let visible = window.occlusionState.contains(.visible)
            if visible != isVisible { isVisible = visible }
        }
    }

    private func caption(total: UInt64) -> String {
        guard let latest else { return String(localized: "Reading…") }
        let budget = StatsFormat.megabytes(StatsFormat.idleBudgetBytes)
        let parts = latest.helperFootprintBytes > 0
            ? String(localized: "App \(StatsFormat.megabytes(latest.footprintBytes)), Now Playing helper \(StatsFormat.megabytes(latest.helperFootprintBytes)).")
            : ""
        let budgetLine = total > StatsFormat.idleBudgetBytes
            ? String(localized: "Over the \(budget) background limit, because this window is open.")
            : String(localized: "Under the \(budget) background limit.")
        return parts.isEmpty ? budgetLine : "\(parts) \(budgetLine)"
    }
}

/// A slim white-on-grey bar: how much of the idle memory budget is used.
private struct BudgetMeter: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AppPalette.rail)
                Capsule()
                    .fill(AppPalette.ink)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// The stored samples as a line, with a dashed rule at the idle budget.
private struct MemoryHistory: View {
    let samples: [HealthSample]
    let range: StatsRange
    @State private var selectedDate: Date?

    private var budgetMB: Double { Double(StatsFormat.idleBudgetBytes) / 1_048_576 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ChartHeading(title: String(localized: "Memory over time"), detail: detail)
            if samples.isEmpty {
                Text("No history yet. It builds up as you open the notch.")
                    .font(.app(size: 12.5))
                    .foregroundStyle(AppPalette.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                chart
            }
        }
    }

    private var chart: some View {
        let highest = samples.map { Double($0.totalFootprintBytes) / 1_048_576 }.max() ?? 0
        let selected = selectedSample
        return Chart {
            ForEach(samples, id: \.date) { sample in
                LineMark(
                    x: .value("Time", sample.date),
                    y: .value("Memory", Double(sample.totalFootprintBytes) / 1_048_576)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(AppPalette.ink.opacity(0.85))
            }
            RuleMark(y: .value("Background limit", budgetMB))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(AppPalette.secondaryText)
                .annotation(position: .top, alignment: .leading, spacing: 3) {
                    Text("Background limit")
                        .font(.app(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppPalette.secondaryText)
                }
            if let point = selected ?? samples.last {
                PointMark(
                    x: .value("Time", point.date),
                    y: .value("Memory", Double(point.totalFootprintBytes) / 1_048_576)
                )
                .symbolSize(36)
                .foregroundStyle(AppPalette.ink)
            }
            if let selected {
                RuleMark(x: .value("Time", selected.date))
                    .foregroundStyle(AppPalette.hairlineStrong)
            }
        }
        .chartYScale(domain: 0...max(budgetMB * 1.2, highest * 1.15))
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(AppPalette.hairline)
                AxisValueLabel().font(.app(size: 10.5)).foregroundStyle(AppPalette.secondaryText)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: range == .week
                    ? .dateTime.weekday(.abbreviated)
                    : .dateTime.month(.abbreviated).day())
                    .font(.app(size: 10.5))
                    .foregroundStyle(AppPalette.secondaryText)
            }
        }
        .frame(height: 150)
        .accessibilityLabel(Text("Memory over time"))
        .accessibilityValue(Text(accessibilitySummary))
    }

    private var selectedSample: HealthSample? {
        guard let selectedDate else { return nil }
        return samples.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private var detail: String? {
        if let sample = selectedSample {
            let when = sample.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            return "\(when) · \(StatsFormat.megabytes(sample.totalFootprintBytes))"
        }
        guard let last = samples.last else { return nil }
        return String(localized: "Latest \(StatsFormat.megabytes(last.totalFootprintBytes))")
    }

    private var accessibilitySummary: String {
        let values = samples.map(\.totalFootprintBytes)
        guard let low = values.min(), let high = values.max(), let last = values.last else { return "" }
        let count = samples.count == 1 ? String(localized: "1 sample") : String(localized: "\(samples.count) samples")
        return String(localized: "\(count), between \(StatsFormat.megabytes(low)) and \(StatsFormat.megabytes(high)), latest \(StatsFormat.megabytes(last)). The idle budget is \(StatsFormat.megabytes(StatsFormat.idleBudgetBytes)).")
    }
}

// MARK: - Bar chart

/// A glass card with a title and one bar per day; the newest (today) is full white. Hovering a
/// bar shows its day and value in the title row.
private struct DailyBarCard: View {
    let title: String
    let days: [Date]
    /// In the unit shown on the y axis, aligned with `days`.
    let values: [Double]
    let range: StatsRange
    /// The y axis goes at least this high, so a quiet week doesn't look like a busy one.
    let minimumTop: Double
    let axisName: String
    let valueText: (Double) -> String
    var detail: String?
    var emptyText: String?

    @State private var selectedKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ChartHeading(title: title, detail: selectedDetail ?? detail)
            chart
                .overlay {
                    if let emptyText, values.allSatisfy({ $0 == 0 }) {
                        Text(emptyText)
                            .font(.app(size: 12.5))
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                }
        }
        .padding(AppMetrics.cardInset)
        .glassPanel()
    }

    private var points: [DayPoint] {
        zip(days.indices, zip(days, values)).map { index, pair in
            DayPoint(key: String(index), date: pair.0, value: pair.1, isToday: index == days.count - 1)
        }
    }

    private var chart: some View {
        let points = points
        let top = max(values.max() ?? 0, minimumTop)
        return Chart(points) { point in
            BarMark(
                x: .value("Day", point.key),
                y: .value(axisName, point.value)
            )
            .cornerRadius(3)
            .foregroundStyle(AppPalette.ink.opacity(isHighlighted(point) ? 1 : 0.8))
        }
        .chartYScale(domain: 0...top * 1.05)
        .chartXSelection(value: $selectedKey)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(AppPalette.hairline)
                AxisValueLabel().font(.app(size: 10.5)).foregroundStyle(AppPalette.secondaryText)
            }
        }
        .chartXAxis {
            AxisMarks(values: labelledKeys(points)) { value in
                AxisValueLabel {
                    if let key = value.as(String.self), let point = points.first(where: { $0.key == key }) {
                        Text(label(for: point))
                    }
                }
                .font(.app(size: 10.5))
                .foregroundStyle(AppPalette.secondaryText)
            }
        }
        .frame(height: 150)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(detail ?? ""))
        .accessibilityChartDescriptor(DailyChartDescriptor(
            title: title,
            axisName: axisName,
            points: points.map { (label: $0.date.formatted(.dateTime.weekday(.wide).month(.wide).day()), value: $0.value) },
            valueText: valueText
        ))
    }

    private func isHighlighted(_ point: DayPoint) -> Bool {
        if let selectedKey { return point.key == selectedKey }
        return point.isToday
    }

    /// Today and every `labelStride`-th day before it.
    private func labelledKeys(_ points: [DayPoint]) -> [String] {
        let stride = range.labelStride
        return points.indices.filter { (points.count - 1 - $0) % stride == 0 }.map { points[$0].key }
    }

    private func label(for point: DayPoint) -> String {
        if point.isToday && range == .week { return String(localized: "Today") }
        return range == .week
            ? point.date.formatted(.dateTime.weekday(.abbreviated))
            : point.date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var selectedDetail: String? {
        guard let selectedKey, let point = points.first(where: { $0.key == selectedKey }) else { return nil }
        return "\(point.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(valueText(point.value))"
    }
}

private struct DayPoint: Identifiable {
    /// The day's position as text: the x axis is one category per day, so bars sit centred on
    /// their labels.
    let key: String
    let date: Date
    let value: Double
    let isToday: Bool
    var id: String { key }
}

/// Lets VoiceOver users explore the bars, and play them as an audio graph.
private struct DailyChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let axisName: String
    let points: [(label: String, value: Double)]
    let valueText: (Double) -> String

    func makeChartDescriptor() -> AXChartDescriptor {
        let top = max(points.map(\.value).max() ?? 0, 1)
        let format = valueText
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: String(localized: "Day"),
            categoryOrder: points.map(\.label)
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: axisName,
            range: 0...top,
            gridlinePositions: []
        ) { format($0) }
        let series = AXDataSeriesDescriptor(
            name: title,
            isContinuous: false,
            dataPoints: points.map { AXDataPoint(x: $0.label, y: $0.value) }
        )
        return AXChartDescriptor(title: title, summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}

// MARK: - Building blocks

/// A small all-caps header over a group of cards, with an optional control on the right.
private struct StatsSection<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SectionLabel(title: title)
                    .padding(.leading, AppMetrics.cardInset)
                Spacer(minLength: 12)
                accessory
            }
            .frame(minHeight: 30)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
    }
}

extension StatsSection where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}

/// A chart card's title, with a grey detail (an average, or the hovered day) on the right.
private struct ChartHeading: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.app(size: 13.5, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.app(size: 12))
                    .foregroundStyle(AppPalette.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

/// A big number with a label above and a grey caption below, like the tiles on Home.
private struct StatsTile: View {
    let label: String
    let symbol: String
    let value: String
    let caption: String
    /// An app's own icon beside the value (the only colour on the page, like file previews).
    var icon: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TileHeading(label: label, symbol: symbol)
            HStack(spacing: 10) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .grayscale(1)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                }
                Text(value)
                    .font(.app(size: 34, weight: .bold))
                    .kerning(-0.8)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            }
            .padding(.top, 14)
            Text(caption)
                .font(.app(size: 12))
                .foregroundStyle(AppPalette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 1)
        }
        .padding(.horizontal, AppMetrics.cardInset)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label): \(value) \(caption)"))
    }
}

private struct TileHeading: View {
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.app(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(label)
                .font(.app(size: 12, weight: .semibold))
        }
        .foregroundStyle(AppPalette.secondaryText)
    }
}

/// A glass card with a title over ranked rows.
private struct RankedCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.app(size: 13.5, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 14) {
                content
            }
        }
        .padding(AppMetrics.cardInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel()
        .accessibilityElement(children: .contain)
    }
}

/// One entry in a top list: rank, optional icon, title and grey subtitle, the figure on the right,
/// and a thin bar underneath as long as its share of the top entry.
private struct RankedRow<Icon: View>: View {
    let rank: Int
    let title: String
    let subtitle: String?
    let value: String
    /// 0…1, compared with the first entry.
    let fraction: Double
    @ViewBuilder var icon: () -> Icon
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(rank.formatted())
                .font(.app(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.tertiaryText)
                .monospacedDigit()
                .frame(width: 14, alignment: .trailing)
                .padding(.top, 1)
            icon()
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.app(size: 13.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let subtitle {
                            Text(subtitle)
                                .font(.app(size: 12))
                                .foregroundStyle(AppPalette.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    Text(value)
                        .font(.app(size: 12.5, weight: .medium))
                        .foregroundStyle(AppPalette.secondaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppPalette.hover)
                        Capsule()
                            .fill(AppPalette.ink.opacity(0.85))
                            .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), 3))
                    }
                }
                .frame(height: 3)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fraction)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(subtitle.map { "\(rank). \(title), \($0)" } ?? "\(rank). \(title)"))
        .accessibilityValue(Text(value))
    }
}

extension RankedRow where Icon == EmptyView {
    init(rank: Int, title: String, subtitle: String?, value: String, fraction: Double) {
        self.init(rank: rank, title: title, subtitle: subtitle, value: value, fraction: fraction) { EmptyView() }
    }
}

/// An app's icon, or a plain app symbol when the app isn't installed any more.
private struct ListeningAppIcon: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .grayscale(1)
            } else {
                Image(systemName: "app")
                    .font(.app(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.secondaryText)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// A module's symbol in a small rounded square, like the cards on Modules.
private struct SymbolIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.app(size: 11, weight: .semibold))
            .frame(width: 24, height: 24)
            .background(AppPalette.selection, in: .rect(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A calm line where a section has nothing to show yet.
private struct EmptyCard: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.app(size: 13, weight: .semibold))
                .foregroundStyle(AppPalette.secondaryText)
                .frame(width: 30, height: 30)
                .background(AppPalette.selection, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text(text)
                .font(.app(size: 13.5))
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.cardInset)
        .padding(.vertical, 22)
        .glassPanel()
    }
}

// MARK: - Names and numbers

/// An app's name and icon, looked up from its bundle ID. Falls back to the bundle ID.
private struct ListeningApp {
    let name: String
    let icon: NSImage?

    @MainActor
    static func resolve(_ bundleID: String) -> ListeningApp {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return ListeningApp(name: bundleID, icon: nil)
        }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        return ListeningApp(name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
    }
}

private enum StatsFormat {
    /// The idle memory budget (ADR-0006), in the same MB (MiB) the memory check uses.
    static let idleBudgetBytes: UInt64 = 50 * 1_048_576

    /// "4 h 12 min", "35 min", "Under 1 min".
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes == 0 {
            return seconds > 0 ? String(localized: "Under 1 min") : String(localized: "0 min")
        }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return String(localized: "\(rest) min") }
        if rest == 0 { return String(localized: "\(hours) h") }
        return String(localized: "\(hours) h \(rest) min")
    }

    static func megabytes(_ bytes: UInt64) -> String {
        let value = Double(bytes) / 1_048_576
        return String(localized: "\(value.formatted(.number.precision(.fractionLength(value < 100 ? 1 : 0)))) MB")
    }

    static func percent(_ value: Double) -> String {
        String(localized: "\(value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0))))%")
    }

    static func plays(_ count: Int) -> String {
        count == 1 ? String(localized: "1 play") : String(localized: "\(count) plays")
    }

    static func opens(_ count: Int) -> String {
        count == 1 ? String(localized: "1 open") : String(localized: "\(count) opens")
    }

    static func times(_ count: Int) -> String {
        count == 1 ? String(localized: "1 time") : String(localized: "\(count) times")
    }

    static func moduleName(_ id: String) -> String {
        switch id {
        case "nowPlaying": String(localized: "Now Playing")
        case "shelf": String(localized: "Shelf")
        default: id
        }
    }

    static func moduleSymbol(_ id: String) -> String {
        switch id {
        case "nowPlaying": "music.note"
        case "shelf": "tray"
        default: "square.grid.2x2"
        }
    }
}
