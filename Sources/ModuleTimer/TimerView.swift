import NotchCore
import SwiftUI
import TimerCore

/// Where things sit in the open Timer panel (origin top-left, y down): a band beside the hardware notch,
/// then the Timer or Stopwatch page (or both, side by side) under it.
struct TimerLayout: Equatable {
    static let sidePadding: CGFloat = 20
    static let bottomPadding: CGFloat = 14

    let body: CGSize
    let bandHeight: CGFloat
    let notchWidth: CGFloat

    init(_ layout: NotchLayout) {
        body = layout.bodySize(for: .expanded)
        bandHeight = layout.geometry.notchRect.height
        notchWidth = layout.geometry.notchRect.width
    }

    var contentHeight: CGFloat { body.height - bandHeight - Self.bottomPadding }
    var bandSideWidth: CGFloat { max(0, (body.width - notchWidth) / 2 - Self.sidePadding) }
}

/// The open Timer panel: the Timer | Stopwatch switch beside the notch, and the page under it. With
/// "Side by side" both pages show, each in half the panel.
struct TimerView: View {
    let module: TimerModule
    let layout: TimerLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sideBySide = module.settings.sideBySide
        VStack(spacing: 0) {
            band(showsSwitch: !sideBySide)
                .frame(height: layout.bandHeight)
                .padding(.horizontal, TimerLayout.sidePadding)
            Group {
                if sideBySide {
                    HStack(spacing: 0) {
                        // Room on each side of the line, so neither page runs into it.
                        TimerPane(module: module, isCompact: true)
                            .padding(.trailing, 12)
                            .frame(maxWidth: .infinity)
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 1).padding(.vertical, 6)
                        StopwatchPane(module: module, isCompact: true)
                            .padding(.leading, 14)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ZStack {
                        switch module.mode {
                        case .timer: TimerPane(module: module, isCompact: false).transition(pageTransition(forward: false))
                        case .stopwatch: StopwatchPane(module: module, isCompact: false).transition(pageTransition(forward: true))
                        }
                    }
                    .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.86), value: module.mode)
                }
            }
            .padding(.horizontal, TimerLayout.sidePadding)
            .padding(.bottom, TimerLayout.bottomPadding)
            .frame(maxHeight: .infinity)
        }
        .frame(width: layout.body.width, height: layout.body.height, alignment: .top)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Timer"))
    }

    private func pageTransition(forward: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: forward ? 24 : -24))
    }

    /// Beside the notch: nothing on the left (the module tabs live there), the switch on the right.
    private func band(showsSwitch: Bool) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Color.clear.frame(width: layout.notchWidth)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if showsSwitch { ModeSwitch(module: module) }
            }
            .frame(width: layout.bandSideWidth)
        }
    }
}

/// Timer · Stopwatch, in the style of AI Usage's range switch. A dot marks the other page while something
/// is on it (running, paused, done or stopped); VoiceOver says which.
private struct ModeSwitch: View {
    let module: TimerModule

    var body: some View {
        HStack(spacing: 2) {
            segment(.timer, title: String(localized: "Timer"), status: timerStatus)
            segment(.stopwatch, title: String(localized: "Stopwatch"), status: stopwatchStatus)
        }
        .padding(2)
        .background(.white.opacity(0.08), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Mode"))
    }

    private var timerStatus: String? {
        switch module.center.timer.phase {
        case .idle: nil
        case .running: String(localized: "Running")
        case .paused: String(localized: "Paused")
        case .done: String(localized: "Done")
        }
    }

    private var stopwatchStatus: String? {
        let stopwatch = module.center.stopwatch
        if stopwatch.isRunning { return String(localized: "Running") }
        return stopwatch.isStopped ? String(localized: "Stopped") : nil
    }

    private func segment(_ mode: TimerMode, title: String, status: String?) -> some View {
        ModeSegment(title: title, isSelected: module.mode == mode, status: module.mode == mode ? nil : status) {
            module.showMode(mode)
        }
    }
}

private struct ModeSegment: View {
    let title: String
    let isSelected: Bool
    /// What's on the other page ("Paused"), shown as a dot.
    let status: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                if status != nil {
                    Circle().fill(.white).frame(width: 4, height: 4)
                }
            }
            .foregroundStyle(.white.opacity(isSelected ? 1 : isHovered ? 0.85 : 0.6))
            .padding(.horizontal, 10)
            .frame(height: 20)
            .background(.white.opacity(isSelected ? 0.18 : 0), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(Text(status ?? ""))
    }
}

// MARK: Buttons

// MARK: Timer

/// The Timer page: presets and wheels before it starts (or for "+ New timer"), the countdown while one
/// runs, the list while several do (issue #70), and Done for each one that ends, oldest first.
struct TimerPane: View {
    let module: TimerModule
    let isCompact: Bool

    var body: some View {
        let page = Page(module)
        ZStack {
            switch page {
            case .setup:
                TimerSetup(module: module, isCompact: isCompact)
                    .transition(.opacity)
            case .counting:
                TimerRunning(module: module, isCompact: isCompact)
                    .transition(.opacity)
            case .list:
                TimerList(module: module, isCompact: isCompact)
                    .transition(.opacity)
            case .done:
                TimerDone(module: module, isCompact: isCompact)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: page)
    }

    /// Which page, without dates, so a change of end time (+1 min) doesn't count as a new page.
    enum Page: Equatable {
        case setup, counting, list, done

        @MainActor init(_ module: TimerModule) {
            let center = module.center
            if center.timer.isDone {
                self = .done
            } else if module.showsSetup {
                self = .setup
            } else {
                self = center.timers.count > 1 ? .list : .counting
            }
        }
    }
}

/// Before a timer starts: the presets, and the wheels for any other time with Start.
private struct TimerSetup: View {
    let module: TimerModule
    let isCompact: Bool

    var body: some View {
        let presets = module.presets
        // "+ New timer" beside running ones: fewer preset rows, room for the way back.
        let adding = !module.center.timers.isEmpty
        HStack(alignment: .center, spacing: isCompact ? 12 : 22) {
            if !presets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if adding { backButton }
                    PresetGrid(module: module, presets: presets, columns: isCompact ? 2 : 3, isCompact: isCompact, rows: adding ? (isCompact ? 2 : 3) : nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: isCompact ? 6 : 8) {
                if presets.isEmpty, adding { backButton }
                if !isCompact { TimerNameField(module: module) }
                TimerWheels(module: module, isCompact: isCompact)
                NotchPill(title: String(localized: "Start"), symbol: "play.fill", prominent: true) {
                    module.startWheels()
                }
                .disabled(!module.canStartWheels)
                .opacity(module.canStartWheels ? 1 : 0.4)
                .accessibilityHint(Text("Starts a timer for the time on the wheels."))
            }
            .frame(maxWidth: presets.isEmpty ? .infinity : nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // While typing, a click beside the wheels ends it, like leaving a text field. Not otherwise:
            // a click on the open notch shrinks it (ADR-0011).
            if module.editing != nil || module.editingName {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { module.endEditing() }
            }
        }
    }

    private var backButton: some View {
        Button { module.cancelAdding() } label: {
            Label {
                Text("\(module.center.timers.count) running", comment: "Timer: back from a new timer to the ones running")
            } icon: {
                Image(systemName: "chevron.left")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text("Back to timers"))
        .accessibilityHint(Text("Shows the timers that are running without starting another."))
    }
}

/// The next timer's name. Clicking it takes the keyboard (the notch gets it, as for the wheels' digits):
/// letters type, Delete erases, Tab goes to the wheels, Return starts, Esc stops typing.
private struct TimerNameField: View {
    let module: TimerModule
    @State private var isHovered = false

    var body: some View {
        let editing = module.editingName
        let name = module.newName
        Button { module.beginEditingName() } label: {
            HStack(spacing: 1) {
                Text(name.isEmpty && !editing ? String(localized: "Name", comment: "Timer: placeholder for the new timer's name") : name)
                    .foregroundStyle(.white.opacity(name.isEmpty ? 0.4 : 0.9))
                    .lineLimit(1)
                    .truncationMode(.head)
                if editing {
                    Rectangle().fill(.white).frame(width: 1.5, height: 12)
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 8)
            .frame(width: 128, height: 22, alignment: .leading)
            .background(.white.opacity(editing ? 0.16 : (isHovered ? 0.14 : 0.08)), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(editing ? 0.5 : 0), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: editing)
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text("Timer name"))
        .accessibilityValue(Text(name.isEmpty ? String(localized: "None", comment: "Timer name: empty") : name))
        .accessibilityHint(Text("Type a name for the next timer, then press Return to start it."))
    }
}

/// The quick-start times as small buttons: all 12 at full size, the first 6 side by side (Settings says so).
private struct PresetGrid: View {
    let module: TimerModule
    let presets: [TimerPreset]
    let columns: Int
    let isCompact: Bool
    var rows: Int?

    var body: some View {
        let rows = rows ?? (isCompact ? 3 : 4)
        let shown = Array(presets.prefix(columns * rows))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), alignment: .leading, spacing: 6) {
            ForEach(shown) { preset in
                PresetButton(preset: preset) { module.startPreset(preset) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Presets"))
    }
}

struct PresetButton: View {
    let preset: TimerPreset
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(TimerText.length(preset.seconds))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                if !preset.name.isEmpty {
                    Text(preset.name)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: preset.name.isEmpty ? 26 : 30)
            .background(.white.opacity(isHovered ? 0.2 : 0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text("Start \(TimerText.preset(preset))"))
    }
}

/// A timer counting down (or paused): the ring, the rolling digits with the end time, and the buttons.
private struct TimerRunning: View {
    let module: TimerModule
    let isCompact: Bool

    var body: some View {
        let timer = module.center.timer
        Group {
            if let end = timer.end, module.pageTicks {
                // Ticks on each whole second before the end, only while this page shows (AGENTS.md rule 2).
                TimelineView(.periodic(from: end.addingTimeInterval(-max(0, end.timeIntervalSince(module.center.now)).rounded(.up)), by: 1)) { context in
                    face(now: context.date)
                }
            } else {
                face(now: module.center.now)
            }
        }
    }

    private func face(now: Date) -> some View {
        let timer = module.center.timer
        let remaining = timer.remaining(at: now)
        let ringSize: CGFloat = isCompact ? 38 : 64
        let layout = isCompact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 18))
        return layout {
            HStack(spacing: isCompact ? 10 : 18) {
                ZStack {
                    TimerRing(module: module, size: ringSize, lineWidth: isCompact ? 3 : 4)
                    Image(systemName: timer.isPaused ? "pause.fill" : module.symbol)
                        .font(.system(size: ringSize * 0.3, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    DrumText(
                        text: TimerText.countdown(remaining),
                        size: isCompact ? 28 : 44,
                        weight: .medium,
                        style: module.settings.digitAnimation
                    )
                    Text(timer.name.isEmpty ? statusLine(timer) : timer.name + " · " + statusLine(timer))
                        .font(.system(size: isCompact ? 10.5 : 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                // Rounded up, as the digits show it; with the end time the screen shows under them.
                .accessibilityLabel(Text(timer.isPaused
                    ? String(localized: "\(TimerText.label(timer)) paused, \(TimerText.spoken(remaining.rounded(.up))) left")
                    : TimerText.label(timer) + ", " + String(localized: "\(TimerText.spoken(remaining.rounded(.up))) left") + ", " + statusLine(timer)))
            }
            if !isCompact { Spacer(minLength: 0) }
            controls(timer)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusLine(_ timer: CountdownTimer) -> String {
        if let end = timer.end { return String(localized: "Ends \(TimerText.time(end))", comment: "Timer: when it will end") }
        return String(localized: "Paused", comment: "Timer: paused")
    }

    @ViewBuilder
    private func controls(_ timer: CountdownTimer) -> some View {
        let size: CGFloat = isCompact ? 30 : 38
        HStack(spacing: 10) {
            if module.center.canAddTimer {
                NotchRoundButton(symbol: "plus", label: String(localized: "New timer"), size: size) {
                    module.beginAdding()
                }
                .accessibilityHint(Text("Starts another timer beside this one."))
            }
            NotchRoundButton(symbol: "xmark", label: String(localized: "Cancel timer"), size: size) {
                module.user { module.center.cancelTimer() }
            }
            if timer.isPaused {
                NotchRoundButton(symbol: "play.fill", label: String(localized: "Resume"), prominent: true, size: size) {
                    module.user { module.center.resumeTimer() }
                }
            } else {
                NotchRoundButton(symbol: "pause.fill", label: String(localized: "Pause"), prominent: true, size: size) {
                    module.user { module.center.pauseTimer() }
                }
            }
        }
    }
}

/// The timer ended: Done, what it was, and Stop (the main button), +1 min and Repeat.
private struct TimerDone: View {
    let module: TimerModule
    let isCompact: Bool

    var body: some View {
        let ringSize: CGFloat = isCompact ? 38 : 64
        HStack(spacing: isCompact ? 10 : 18) {
            ZStack {
                Circle().stroke(.white, lineWidth: isCompact ? 3 : 4)
                Image(systemName: "bell.fill")
                    .font(.system(size: ringSize * 0.32, weight: .semibold))
            }
            .frame(width: ringSize, height: ringSize)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Done", comment: "Timer: it finished")
                    .font(.system(size: isCompact ? 28 : 44, weight: .medium))
                // Redrawn once, a minute after the end, when "ended 3:42 PM" joins the line.
                TimelineView(.explicit(module.center.timer.endedAt.map { [$0.addingTimeInterval(60)] } ?? [])) { _ in
                    Text(doneLine)
                        .font(.system(size: isCompact ? 10.5 : 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            let layout = isCompact ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 5)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                if !isCompact {
                    NotchPill(title: String(localized: "+1 min")) { module.addMinute() }
                        .accessibilityLabel(Text("Add 1 minute"))
                    NotchPill(title: String(localized: "Repeat"), symbol: "arrow.clockwise") { module.repeatTimer() }
                        .accessibilityHint(Text("Starts the same timer again."))
                } else {
                    HStack(spacing: 5) {
                        NotchPill(title: String(localized: "+1 min")) { module.addMinute() }
                            .accessibilityLabel(Text("Add 1 minute"))
                        NotchRoundButton(symbol: "arrow.clockwise", label: String(localized: "Repeat"), size: 24) { module.repeatTimer() }
                    }
                }
                NotchPill(title: String(localized: "Stop"), symbol: "stop.fill", prominent: true) { module.stopTimer() }
                    .accessibilityLabel(Text("Stop timer"))
            }
            // The buttons keep their size; a long name and length shrink first.
            .layoutPriority(1)
        }
    }
}

/// What the Done card says under "Done": the name and length, and how many more are done.
extension TimerDone {
    @MainActor var doneLine: String {
        let center = module.center
        var parts = [TimerDoneText.detail(center)]
        if !center.timer.name.isEmpty { parts.insert(center.timer.name, at: 0) }
        let more = center.doneTimers.count - 1
        if more > 0 { parts.append(String(localized: "\(more) more done", comment: "Done card: other timers also finished")) }
        return parts.joined(separator: " · ")
    }
}

/// Several timers at once (issue #70): a row each, ending soonest first, with +1 min, pause and cancel, and
/// "+ New timer" under them.
private struct TimerList: View {
    let module: TimerModule
    let isCompact: Bool

    var body: some View {
        rows
    }

    private var rows: some View {
        let center = module.center
        let timers = center.sortedTimers
        let rowHeight: CGFloat = isCompact ? 26 : 30
        let spacing: CGFloat = 5
        // As many rows as fit above the bottom line; the rest are counted there (soonest first, so the
        // ones hidden end last).
        return GeometryReader { proxy in
            let room = proxy.size.height - 26 - spacing
            let fit = max(1, Int((room + spacing) / (rowHeight + spacing)))
            let shown = timers.count > fit ? Array(timers.prefix(fit)) : timers
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(shown, id: \.id) { timer in
                    TimerRow(module: module, timer: timer, isCompact: isCompact)
                        .frame(height: rowHeight)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if center.canAddTimer {
                        NotchPill(title: String(localized: "New timer"), symbol: "plus") { module.beginAdding() }
                            .accessibilityHint(Text("Starts another timer beside these."))
                    }
                    Spacer(minLength: 0)
                    if timers.count > shown.count {
                        Text("\(timers.count - shown.count) more", comment: "Timer list: timers that don't fit")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(height: 26)
            }
            .animation(.easeInOut(duration: 0.2), value: shown.map(\.id))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One timer in the list: its ring, name, time left and end, and its buttons.
private struct TimerRow: View {
    let module: TimerModule
    let timer: CountdownTimer
    let isCompact: Bool

    var body: some View {
        if let end = timer.end, module.pageTicks {
            // Each row ticks on its own whole seconds before its end, only while the page shows (AGENTS.md
            // rule 2): one shared tick would show other rows a second early or late.
            TimelineView(.periodic(from: end.addingTimeInterval(-max(0, end.timeIntervalSince(module.center.now)).rounded(.up)), by: 1)) { context in
                row(now: context.date)
            }
        } else {
            row(now: module.center.now)
        }
    }

    @ViewBuilder
    private func row(now: Date) -> some View {
        let remaining = timer.remaining(at: now)
        let label = TimerText.label(timer)
        let status = timer.end.map { String(localized: "Ends \(TimerText.time($0))", comment: "Timer: when it will end") }
            ?? String(localized: "Paused", comment: "Timer: paused")
        let buttonSize: CGFloat = isCompact ? 20 : 22
        HStack(spacing: isCompact ? 8 : 12) {
            ZStack {
                TimerRing(module: module, size: isCompact ? 16 : 18, lineWidth: 2, timer: timer)
                if timer.isPaused {
                    Image(systemName: "pause.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .accessibilityHidden(true)
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: isCompact ? 10.5 : 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(timer.name.isEmpty ? 0.6 : 0.9))
                if !isCompact {
                    Text(status)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Text(TimerText.countdown(remaining))
                .font(.system(size: isCompact ? 14 : 17, weight: .medium).monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
            .accessibilityElement(children: .ignore)
            HStack(spacing: 6) {
                if !isCompact {
                    NotchPill(title: String(localized: "+1 min")) { module.addMinute(timer.id) }
                        .accessibilityLabel(Text("Add 1 minute to \(label)"))
                }
                if timer.isPaused {
                    NotchRoundButton(symbol: "play.fill", label: String(localized: "Resume \(label)"), size: buttonSize) { module.resumeTimer(timer.id) }
                } else {
                    NotchRoundButton(symbol: "pause.fill", label: String(localized: "Pause \(label)"), size: buttonSize) { module.pauseTimer(timer.id) }
                }
                NotchRoundButton(symbol: "xmark", label: String(localized: "Cancel \(label)"), size: buttonSize) { module.cancelTimer(timer.id) }
            }
        }
        .padding(.horizontal, isCompact ? 6 : 10)
        .frame(maxHeight: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label + ", " + String(localized: "\(TimerText.spoken(remaining.rounded(.up))) left") + ", " + status))
    }
}

// MARK: Stopwatch

/// The Stopwatch page: the time to the hundredth, Lap/Reset and Start/Stop, and the laps.
struct StopwatchPane: View {
    let module: TimerModule
    let isCompact: Bool

    var body: some View {
        let stopwatch = module.center.stopwatch
        let ticks = stopwatch.isRunning && module.pageTicks
        let now = module.center.now
        // Only the time and the lap being timed tick; the done laps are drawn once.
        let doneLaps = Array(stopwatch.laps(at: now).dropFirst())
        let lapList = LapList(
            current: stopwatch.lapTotals.isEmpty ? nil : Ticking(ticks: ticks, now: now) { now in
                if let current = stopwatch.currentLap(at: now) { LapRow(lap: current, isRunning: stopwatch.isRunning, isCompact: isCompact) }
            },
            done: doneLaps,
            isSnapshot: module.isSnapshot,
            isCompact: isCompact
        )
        if isCompact {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Ticking(ticks: ticks, now: now) { digits(now: $0) }
                    Spacer(minLength: 0)
                    controls(stopwatch)
                }
                lapList
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Ticking(ticks: ticks, now: now) { digits(now: $0) }
                    controls(stopwatch)
                }
                lapList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func digits(now: Date) -> some View {
        let elapsed = module.center.stopwatch.elapsed(at: now)
        // Always hours, minutes, seconds and hundredths ("00:00:00.00"), so it's as wide at the start as after
        // ten hours: nothing shrinks, nothing moves.
        return DrumText(
            text: TimerText.precise(elapsed),
            size: isCompact ? 26 : 40,
            weight: .medium,
            style: module.settings.digitAnimation,
            direction: .up,
            steadyDigits: 2
        )
        .accessibilityLabel(Text("Stopwatch, \(TimerText.spoken(elapsed.rounded(.down)))"))
    }

    private func controls(_ stopwatch: Stopwatch) -> some View {
        let size: CGFloat = isCompact ? 30 : 38
        return HStack(spacing: 10) {
            if stopwatch.isStopped {
                NotchRoundButton(symbol: "arrow.counterclockwise", label: String(localized: "Reset"), size: size) {
                    module.user { module.center.resetStopwatch() }
                }
            } else {
                NotchRoundButton(symbol: "flag.fill", label: String(localized: "Lap"), size: size) {
                    module.user { module.center.lap() }
                }
                .disabled(!stopwatch.canLap)
                .opacity(stopwatch.canLap ? 1 : 0.35)
            }
            if stopwatch.isRunning {
                NotchRoundButton(symbol: "stop.fill", label: String(localized: "Stop stopwatch"), prominent: true, size: size) {
                    module.user { module.center.stopStopwatch() }
                }
            } else {
                NotchRoundButton(symbol: "play.fill", label: String(localized: "Start stopwatch"), prominent: true, size: size) {
                    module.user { module.center.startStopwatch() }
                }
            }
        }
    }
}

/// Redraws its content about 30 times a second while `ticks` (a running stopwatch on screen, ADR-0040).
private struct Ticking<Content: View>: View {
    let ticks: Bool
    let now: Date
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !ticks)) { context in
            content(ticks ? context.date : now)
        }
    }
}

/// Laps, newest first: the one being timed, then the done ones with Fastest/Slowest tags.
private struct LapList<Current: View>: View {
    let current: Current?
    let done: [Stopwatch.Lap]
    let isSnapshot: Bool
    let isCompact: Bool

    var body: some View {
        if current == nil {
            Text("Laps show here")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isCompact ? .topLeading : .center)
        } else {
            // The lap being timed stays above the list: it ticks 30 times a second, and inside the scroll
            // view each tick would re-measure every row (AGENTS.md rule 2).
            VStack(spacing: 0) {
                current
                if isSnapshot {
                    rows.frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView { rows }
                        .scrollIndicators(.never)
                }
            }
        }
    }

    private var rows: some View {
        LazyVStack(spacing: 0) {
            ForEach(done) { lap in
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                LapRow(lap: lap, isRunning: false, isCompact: isCompact)
            }
        }
    }
}

private struct LapRow: View {
    let lap: Stopwatch.Lap
    /// The stopwatch runs: the current lap is being timed (stopped, it just waits).
    let isRunning: Bool
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("Lap \(lap.number)")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(lap.isCurrent ? 0.6 : 0.9))
            if let mark = lap.mark {
                Text(mark == .fastest ? String(localized: "Fastest") : String(localized: "Slowest"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .frame(height: 14)
                    .background(.white.opacity(mark == .fastest ? 0.9 : 0.55), in: Capsule())
            }
            Spacer(minLength: 4)
            Text(TimerText.precise(lap.time))
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(lap.isCurrent ? 0.6 : 0.9))
            if !isCompact {
                Text(TimerText.precise(lap.total))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .lineLimit(1)
        .frame(height: isCompact ? 18 : 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }

    private var spoken: String {
        var parts = [String(localized: "Lap \(lap.number)"), TimerText.spoken(lap.time.rounded(.down))]
        if lap.isCurrent, isRunning { parts.append(String(localized: "running")) }
        if let mark = lap.mark { parts.append(mark == .fastest ? String(localized: "Fastest") : String(localized: "Slowest")) }
        return parts.joined(separator: ", ")
    }
}
