import NotchCore
import SwiftUI
import TimerCore

extension TimerModule {
    /// The Timer and Stopwatch widgets on Home (ADR-0042).
    public func homeWidget(_ kind: HomeWidgetKind, size: HomeWidgetSize, context: HomeWidgetContext) -> AnyView? {
        switch kind {
        case .timer: AnyView(TimerWidget(module: self, size: size, context: context))
        case .stopwatch: AnyView(StopwatchWidget(module: self, size: size, context: context))
        default: nil
        }
    }

    /// A click on the Stopwatch widget opens the Timer on its stopwatch; on the Timer widget, on the timer.
    public func openedFromHome(_ kind: HomeWidgetKind) {
        if kind == .stopwatch { showMode(.stopwatch) } else if kind == .timer { showMode(.timer) }
    }
}

/// Redraws on each whole second while `isOn`, lined up with `anchor` (a timer's end, a stopwatch's start),
/// so the digits change exactly when the real ones do. Otherwise draws once, at `now`.
private struct SecondTicks<Content: View>: View {
    let isOn: Bool
    let anchor: Date?
    let now: Date
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if isOn, let anchor {
            let start = anchor.addingTimeInterval((now.timeIntervalSince(anchor)).rounded(.down))
            TimelineView(.periodic(from: start, by: 1)) { timeline in content(timeline.date) }
        } else {
            content(now)
        }
    }
}

/// Small: the time left, or "Timer" when idle. Medium: the time left with pause and stop, or two presets.
/// Large: the ring with the time inside and the buttons, or up to four presets.
struct TimerWidget: View {
    let module: TimerModule
    let size: HomeWidgetSize
    let context: HomeWidgetContext

    private var timer: CountdownTimer { module.center.timer }
    // The center's own clock (a fixed one in snapshots).
    private var now: Date { module.center.now }

    var body: some View {
        if timer.isIdle {
            idle
        } else {
            SecondTicks(isOn: context.isLive && timer.isRunning, anchor: timer.end, now: now) { date in
                active(at: date)
            }
        }
    }

    // MARK: Idle

    @ViewBuilder private var idle: some View {
        switch size {
        case .small:
            HomeWidgetTile(symbol: "timer", title: String(localized: "Timer", comment: "Module name"),
                           line: String(localized: "Not running", comment: "Home widget: no timer"))
        case .medium:
            VStack(alignment: .leading, spacing: 6) {
                header(String(localized: "Timer", comment: "Module name"))
                presets(count: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .large:
            VStack(alignment: .leading, spacing: 6) {
                header(String(localized: "Timer", comment: "Module name"))
                Spacer(minLength: 0)
                presets(count: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func header(_ title: String) -> some View {
        HomeWidgetHeader(symbol: "timer", title: title)
    }

    /// The first presets, two to a row.
    private func presets(count: Int) -> some View {
        let shown = Array(module.settings.presets.prefix(count))
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(shown) { preset in
                PresetButton(preset: preset) { module.startPreset(preset) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Presets"))
    }

    // MARK: Running, paused, done

    @ViewBuilder private func active(at date: Date) -> some View {
        let remaining = timer.isDone ? 0 : timer.remaining(at: date)
        let time = TimerText.countdown(remaining)
        switch size {
        case .small:
            HomeSmallFace(caption: statusText) {
                ring(size: 13, lineWidth: 2)
            } value: {
                digits(time, size: 17)
            }
        case .medium:
            HStack(spacing: 10) {
                ring(size: 30, lineWidth: 3)
                VStack(alignment: .leading, spacing: 1) {
                    digits(time, size: 19)
                    status
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                buttons
            }
            .frame(maxHeight: .infinity)
        case .large:
            VStack(spacing: 8) {
                ZStack {
                    ring(size: 64, lineWidth: 4)
                    digits(time, size: 15)
                        .frame(width: 54)
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 8) { buttons }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func ring(size: CGFloat, lineWidth: CGFloat) -> some View {
        Group {
            if context.isLive || context.isSnapshot {
                DrainingRing(plan: RingPlan(timer), epoch: module.center.clockEpoch, lineWidth: lineWidth,
                             isSnapshot: context.isSnapshot || module.isSnapshot, now: { module.center.now })
            } else {
                // Not on screen: a still ring, so nothing animates out of sight.
                DrainingRing(plan: .still(timer.isDone ? 0 : timer.fractionLeft(at: now)), epoch: 0,
                             lineWidth: lineWidth, isSnapshot: true, now: { now })
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func digits(_ text: String, size: CGFloat) -> some View {
        DrumText(text: text, size: size, style: module.settings.digitAnimation)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(Text(timer.isDone ? String(localized: "Done") : TimerText.spoken(timer.remaining(at: now))))
    }

    private var statusText: String {
        timer.isDone ? String(localized: "Done") : timer.isPaused ? String(localized: "Paused") : String(localized: "Left")
    }

    private var status: some View {
        Text(statusText)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: timer.phase)
    }

    @ViewBuilder private var buttons: some View {
        if !timer.isDone {
            NotchRoundButton(symbol: timer.isPaused ? "play.fill" : "pause.fill",
                             label: timer.isPaused ? String(localized: "Resume") : String(localized: "Pause"),
                             size: 24) {
                module.user { timer.isPaused ? module.center.resumeTimer() : module.center.pauseTimer() }
            }
        }
        NotchRoundButton(symbol: "xmark", label: timer.isDone ? String(localized: "Stop the alarm") : String(localized: "Stop"),
                         prominent: timer.isDone, size: 24) {
            module.stopTimer()
        }
    }
}

/// Small: the time. Medium: the time with Start or Stop. Large: also Lap or Reset, and the last laps.
struct StopwatchWidget: View {
    let module: TimerModule
    let size: HomeWidgetSize
    let context: HomeWidgetContext

    private var stopwatch: Stopwatch { module.center.stopwatch }
    // The center's own clock (a fixed one in snapshots).
    private var now: Date { module.center.now }

    var body: some View {
        SecondTicks(isOn: context.isLive && stopwatch.isRunning, anchor: stopwatch.runningSince, now: now) { date in
            face(at: date)
        }
    }

    @ViewBuilder private func face(at date: Date) -> some View {
        let time = TimerText.elapsed(stopwatch.elapsed(at: date))
        switch size {
        case .small:
            // Before it starts, the symbol says what it is ("Stopwatch" doesn't fit beside it).
            HomeSmallFace(caption: stopwatch.isRunning || stopwatch.isStopped ? statusText : nil) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            } value: {
                digits(time, size: 17)
            }
        case .medium:
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    digits(time, size: 19)
                    status
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                startStop
            }
            .frame(maxHeight: .infinity)
        case .large:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        digits(time, size: 21)
                        status
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    lapOrReset
                    startStop
                }
                laps(at: date)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func digits(_ text: String, size: CGFloat) -> some View {
        DrumText(text: text, size: size, style: module.settings.digitAnimation, direction: .up)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(Text(TimerText.spoken(stopwatch.elapsed(at: now))))
    }

    private var statusText: String {
        stopwatch.isRunning ? String(localized: "Running") : stopwatch.isStopped ? String(localized: "Stopped")
            : String(localized: "Stopwatch", comment: "Home widget: the stopwatch hasn't started")
    }

    private var status: some View {
        Text(statusText)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: stopwatch.phase)
    }

    private var startStop: some View {
        NotchRoundButton(symbol: stopwatch.isRunning ? "stop.fill" : "play.fill",
                         label: stopwatch.isRunning ? String(localized: "Stop") : String(localized: "Start"),
                         prominent: !stopwatch.isRunning, size: 24) {
            module.user { stopwatch.isRunning ? module.center.stopStopwatch() : module.center.startStopwatch() }
        }
    }

    /// Lap while it runs, Reset once stopped; nothing before it starts, keeping the space.
    private var lapOrReset: some View {
        Group {
            if stopwatch.isRunning {
                NotchRoundButton(symbol: "flag.fill", label: String(localized: "Lap"), size: 24) {
                    module.user { module.center.lap() }
                }
                .disabled(!stopwatch.canLap)
                .opacity(stopwatch.canLap ? 1 : 0.35)
            } else if stopwatch.isStopped {
                NotchRoundButton(symbol: "arrow.counterclockwise", label: String(localized: "Reset"), size: 24) {
                    module.user { module.center.resetStopwatch() }
                }
            } else {
                Color.clear.frame(width: 24, height: 24)
            }
        }
        .transition(.opacity)
    }

    /// The most recent laps, newest first.
    @ViewBuilder private func laps(at date: Date) -> some View {
        let laps = stopwatch.laps(at: date).filter { !$0.isCurrent }.prefix(2)
        if laps.isEmpty {
            Text(stopwatch.isIdle ? String(localized: "Start, then press Lap to time each part.") : String(localized: "No laps yet."))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(2)
        } else {
            VStack(spacing: 2) {
                ForEach(Array(laps)) { lap in
                    HStack {
                        Text("Lap \(lap.number)")
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer(minLength: 0)
                        Text(TimerText.elapsed(lap.time))
                    }
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: laps.map(\.number))
        }
    }
}
