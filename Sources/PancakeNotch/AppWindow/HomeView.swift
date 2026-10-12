import Learn
import ModuleShelf
import NotchCore
import SwiftUI

/// The window's first page: a greeting, the notch's on/off switch with a live preview, a few
/// usage numbers and tips.
struct HomeView: View {
    let context: AppContext
    @Binding var section: AppSection
    let openLesson: (LessonID) -> Void

    var body: some View {
        PageScroll {
            HomeHeader()
            if !context.progress.homeBoxHidden {
                LearnBox(progress: context.progress, openLesson: openLesson)
                    .padding(.top, 26)
                    .transition(.opacity)
            }
            NotchHero(context: context)
                .padding(.top, 26)
            StatsRow(stats: context.stats, shelfSettings: context.shelfSettings, shelfStore: context.shelfStore)
                .padding(.top, 14)
            TipsCard(
                preferences: context.preferences,
                shortcuts: context.shortcuts,
                showsNowPlayingTips: context.nowPlayingSettings.isEnabled,
                showsShelfTips: context.shelfSettings.isEnabled
            ) { section = .keyboard }
                .padding(.top, 14)
        }
    }
}

/// Today's date over a time-of-day greeting.
private struct HomeHeader: View {
    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 6) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.app(size: 11, weight: .semibold))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppPalette.secondaryText)
            Text(Self.greeting(at: now))
                .font(.app(size: 34, weight: .bold))
                .kerning(-0.6)
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityElement(children: .combine)
    }

    static func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: String(localized: "Good morning")
        case 12..<17: String(localized: "Good afternoon")
        case 17..<22: String(localized: "Good evening")
        default: String(localized: "Hello, night owl")
        }
    }
}

/// Points new people at the lessons: how many are done, a way to carry on, and a way to hide it.
/// When everything is done it shows a checkmark and offers to go away.
private struct LearnBox: View {
    let progress: LearnProgress
    let openLesson: (LessonID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let total = LessonID.allCases.count
        let done = progress.doneCount
        HStack(spacing: 14) {
            Image(systemName: progress.allDone ? "checkmark" : "graduationcap")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(progress.allDone ? Color.black : AppPalette.primaryText)
                .frame(width: 42, height: 42)
                .background(progress.allDone ? Color.white : AppPalette.selection, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(progress.allDone ? String(localized: "You've learned the basics") : String(localized: "Learn PancakeNotch"))
                    .font(.app(size: 15, weight: .bold))
                Text(progress.allDone
                    ? String(localized: "Every lesson done. They stay in Learn if you want a refresher.")
                    : String(localized: "\(done) of \(total) lessons done. Each takes about a minute, hands on."))
                    .font(.app(size: 12.5))
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressSegments(done: done, total: total)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            if progress.allDone {
                Button(String(localized: "Hide"), action: hide)
                    .accessibilityHint(Text("Removes this box from Home. Lessons stay in Learn."))
            } else {
                Button(done == 0 ? String(localized: "Start") : String(localized: "Continue")) {
                    openLesson(LessonID.allCases.first { !progress.isDone($0) } ?? .basics)
                }
                .buttonStyle(ProminentPillButtonStyle())
                Button(action: hide) {
                    Image(systemName: "xmark")
                        .font(.app(size: 11, weight: .bold))
                        .foregroundStyle(AppPalette.secondaryText)
                        .frame(width: 26, height: 26)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(Text("Hide"))
                .accessibilityLabel(Text("Hide"))
                .accessibilityHint(Text("Removes this box from Home. Lessons stay in Learn."))
            }
        }
        .padding(.horizontal, AppMetrics.cardInset)
        .padding(.vertical, 16)
        .glassPanel()
    }

    private func hide() {
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.25)) { progress.homeBoxHidden = true }
    }
}

/// A short bar split into one piece per lesson, done pieces filled.
private struct ProgressSegments: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < done ? AppPalette.ink : AppPalette.rail)
                    .frame(width: 28, height: 4)
            }
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }
}

/// The big switch: a pretend screen with the live notch on top, its state and the toggle below.
private struct NotchHero: View {
    let context: AppContext
    /// What the real notch shows (Now Playing, the Shelf), on the user's real data, while Home is up.
    @State private var liveModules: [any NotchModule] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    private var preferences: Preferences { context.preferences }

    /// Which modules are on: the live notch follows the switches.
    private var enabledModules: [Bool] {
        [context.nowPlayingSettings.isEnabled, context.shelfSettings.isEnabled]
    }

    var body: some View {
        let isOn = preferences.notchEnabled
        VStack(spacing: 0) {
            NotchStage(
                behavior: preferences.notchBehavior,
                arrangement: context.arrangement,
                isActive: isOn,
                modules: liveModules,
                activeHint: String(localized: "This is your real notch: hover to open it. What you do here happens in your notch too.")
            )
            .onAppear { liveModules = context.makeLiveModules() }
            .onChange(of: enabledModules) { liveModules = context.makeLiveModules() }
            .onDisappear { liveModules = [] }

        HStack(spacing: 14) {
                StatusBadge(isOn: isOn)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isOn ? String(localized: "Notch is on") : String(localized: "Notch is off"))
                        .font(.app(size: 21, weight: .bold))
                        .kerning(-0.3)
                        .contentTransition(.opacity)
                    Text(isOn
                        ? String(localized: "Move the pointer to the top of your screen and the notch opens.")
                        : String(localized: "The notch is hidden, but PancakeNotch keeps running. Turn it back on any time."))
                        .font(.app(size: 13))
                        .foregroundStyle(AppPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 12)

                Toggle(String(localized: "Notch"), isOn: Bindable(preferences).notchEnabled)
                    .toggleStyle(MonochromeSwitchStyle(size: .large))
                    .labelsHidden()
                    .accessibilityHint(Text("Shows or hides the notch without quitting PancakeNotch."))
            }
            .padding(.horizontal, AppMetrics.cardInset)
            .padding(.vertical, 18)
            .background(Color.white.opacity(0.035))
            .overlay(alignment: .top) {
                AppPalette.hairline.frame(height: 1)
            }
        }
        .background {
            // Glossy black: pure black at the top, lifting slightly towards the bottom edge.
            LinearGradient(colors: [.black, Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(LinearGradient(
                colors: [.white.opacity(isOn ? 0.24 : 0.14), .white.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
        .shadow(color: .white.opacity(isOn ? 0.07 : 0), radius: 40, y: 0)
        .shadow(color: .black.opacity(0.6), radius: 24, y: 14)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isOn)
    }
}

/// A power badge: solid white when the notch is on, an outline when it's off.
private struct StatusBadge: View {
    let isOn: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        Image(systemName: "power")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(isOn ? Color.black : AppPalette.secondaryText)
            .frame(width: 42, height: 42)
            .background(shape.fill(isOn ? Color.white : Color.white.opacity(0.06)))
            .overlay(shape.strokeBorder(isOn ? .clear : AppPalette.hairlineStrong, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Big-number tiles: notch opens, days together, and what's on the Shelf.
private struct StatsRow: View {
    let stats: UsageStats
    let shelfSettings: ShelfSettings
    let shelfStore: ShelfStore

    var body: some View {
        HStack(spacing: 12) {
            StatTile(
                label: String(localized: "Today"),
                symbol: "sun.max",
                value: stats.opensToday.formatted(),
                caption: Self.opens(stats.opensToday)
            )
            StatTile(
                label: String(localized: "All time"),
                symbol: "chart.bar",
                value: stats.opensTotal.formatted(),
                caption: Self.opens(stats.opensTotal)
            )
            StatTile(
                label: String(localized: "Together"),
                symbol: "calendar",
                value: daysTogether.formatted(),
                caption: daysTogether == 1
                    ? String(localized: "day, since \(stats.firstLaunch.formatted(.dateTime.month(.abbreviated).day()))")
                    : String(localized: "days, since \(stats.firstLaunch.formatted(.dateTime.month(.abbreviated).day()))")
            )
            StatTile(
                label: String(localized: "Shelf"),
                symbol: "tray",
                value: shelfStore.items.count.formatted(),
                caption: shelfSettings.isEnabled
                    ? String(localized: "of \(ShelfStore.capacity) on the Shelf")
                    : String(localized: "Shelf is off")
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private static func opens(_ count: Int) -> String {
        count == 1 ? String(localized: "notch open") : String(localized: "notch opens")
    }

    /// Calendar days since the first launch, counting today.
    private var daysTogether: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: stats.firstLaunch),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        return max(days, 0) + 1
    }
}

private struct StatTile: View {
    let label: String
    let symbol: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TileLabel(label: label, symbol: symbol)
            Text(value)
                .font(.app(size: 34, weight: .bold))
                .kerning(-0.8)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
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

private struct TileLabel: View {
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

/// The user's shortcut (or a way to set one) beside a few tips.
private struct TipsCard: View {
    let preferences: Preferences
    let shortcuts: ShortcutController
    let showsNowPlayingTips: Bool
    let showsShelfTips: Bool
    let openKeyboardSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            shortcut
                .padding(AppMetrics.cardInset)
                .frame(width: 250, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            AppPalette.hairline.frame(width: 1)

            VStack(alignment: .leading, spacing: 16) {
                SectionLabel(title: String(localized: "Tips"))
                ForEach(tips, id: \.title) { tip in
                    TipRow(symbol: tip.symbol, title: tip.title, detail: tip.detail)
                }
            }
            .padding(AppMetrics.cardInset)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .glassPanel()
    }

    @ViewBuilder
    private var shortcut: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: String(localized: "Your shortcut"))
            if let hotKey = shortcuts.shortcut {
                KeyCombo(keys: hotKey.keyCaps, large: true)
                    .accessibilityLabel(Text(hotKey.displayString))
                    .padding(.top, 16)
                Text("Opens and closes the notch from any app.")
                    .font(.app(size: 12.5))
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Spacer(minLength: 14)
                Button(String(localized: "Change…"), action: openKeyboardSettings)
            } else {
                Text("No shortcut yet")
                    .font(.app(size: 17, weight: .bold))
                    .padding(.top, 14)
                Text("Pick a key combination to open and close the notch from any app.")
                    .font(.app(size: 12.5))
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                Spacer(minLength: 14)
                Button(String(localized: "Set a Shortcut"), action: openKeyboardSettings)
                    .buttonStyle(ProminentPillButtonStyle())
            }
        }
    }

    private var tips: [(symbol: String, title: String, detail: String)] {
        let shelf: [(symbol: String, title: String, detail: String)] = showsShelfTips ? [
            ("tray.and.arrow.down", String(localized: "Drop things on the notch"),
             String(localized: "Drag files, images, text or links to the notch to keep them on the Shelf.")),
        ] + (showsNowPlayingTips ? [] : [
            ("hand.point.up.left", String(localized: "Click an item to open it"),
             String(localized: "See a big preview or edit a note or link. Right-click for Copy, AirDrop and more.")),
        ]) : []
        let nowPlaying: [(symbol: String, title: String, detail: String)] = showsNowPlayingTips ? [
            ("music.note", String(localized: "Your music, in the notch"),
             String(localized: "Album art and sound bars show while something plays. Open the notch to pause, skip or jump around.")),
            ("rectangle.2.swap", String(localized: "Switch modules"),
             String(localized: "Pick one at the top left of the open notch, or swipe sideways there with two fingers.")),
        ] : []
        return [
            ("cursorarrow.rays", String(localized: "Hover to open"),
             String(localized: "Rest the pointer on the notch and it slides open.")),
            ("hand.tap", String(localized: "Click to keep it small"),
             String(localized: "Click the open notch and it stays small: hover to open it, click again to close it fully.")),
        ] + nowPlaying + shelf + [
            preferences.showMenuBarIcon
                ? ("menubar.rectangle", String(localized: "Switch it off from the menu bar"),
                   String(localized: "The PancakeNotch menu bar icon turns the notch on or off."))
                : ("arrow.uturn.backward", String(localized: "Find your way back"),
                   String(localized: "Open PancakeNotch from Applications to see this window again.")),
        ]
    }
}

private struct TipRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.app(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(AppPalette.selection, in: .rect(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppPalette.hairline)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(size: 13.5, weight: .semibold))
                Text(detail)
                    .font(.app(size: 12.5))
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
