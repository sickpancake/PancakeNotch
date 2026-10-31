import NotchCore
import SwiftUI
import TimerCore

/// A ring that drains as the timer runs (a stopwatch's sweeps once a minute). White on a faint track:
/// monochrome like everything else (ADR-0029). It moves in steps with the time, never animating on its own.
struct TimerRing: View {
    /// 0…1.
    let fraction: Double
    let size: CGFloat
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Where an ear view goes: sharing the ears with another module (`shared`, one ear), or alone with both:
/// the time in its own ear (`solo`) and the ring or a sign in the other (`companion`).
enum TimerEarRole {
    case shared, solo, companion
}

/// The Timer's compact ear. Shows the timer while it isn't idle, else the stopwatch. Ticks once a second
/// only while it's on screen and counting (`TimerModule.earTicks`, AGENTS.md rule 2).
struct TimerEar: View {
    let module: TimerModule
    let role: TimerEarRole
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if module.earTicks, let start = tickStart {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    content(now: context.date)
                }
            } else {
                content(now: module.center.now)
            }
        }
        .frame(width: width, height: height)
        .foregroundStyle(.white)
        .accessibilityHidden(true)
    }

    /// A moment that's a whole number of seconds from the timer's end (or the stopwatch's start), so each
    /// tick lands just as the shown second changes.
    private var tickStart: Date? {
        let center = module.center
        let now = center.now
        if let end = center.timer.end {
            // Past the end (the alarm hasn't run yet), not a start in the future.
            return end.addingTimeInterval(-(max(0, end.timeIntervalSince(now)).rounded(.down) + 1))
        }
        if center.timer.isIdle, center.stopwatch.isRunning {
            let elapsed = center.stopwatch.elapsed(at: now)
            return now.addingTimeInterval(-(elapsed - elapsed.rounded(.down)))
        }
        return nil
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let center = module.center
        let timer = center.timer
        if timer.isDone {
            done
        } else if !timer.isIdle {
            timerFace(timer, now: now)
        } else if !center.stopwatch.isIdle {
            stopwatchFace(center.stopwatch, now: now)
        } else if role != .companion {
            // The short shrink after a click while nothing runs.
            Image(systemName: module.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    @ViewBuilder
    private var done: some View {
        if role == .companion || (role == .shared && module.settings.earContent == .ring) {
            sign("bell.fill")
        } else {
            Text("Done", comment: "Timer ear: the timer finished")
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private func timerFace(_ timer: CountdownTimer, now: Date) -> some View {
        let paused = timer.isPaused
        let content = module.settings.earContent
        let text = TimerText.countdown(timer.remaining(at: now))
        let ring = TimerRing(fraction: timer.fractionLeft(at: now), size: 10)
        switch role {
        case .companion:
            if paused { sign("pause.fill") } else if content == .ringAndTime || content == .ring {
                TimerRing(fraction: timer.fractionLeft(at: now), size: 13)
            } else {
                sign(module.symbol)
            }
        case .solo:
            if content == .ring, !paused {
                TimerRing(fraction: timer.fractionLeft(at: now), size: 13)
            } else if content == .endTime, let end = timer.end {
                fitting(lead: nil, text: TimerText.shortTime(end), animated: false)
            } else {
                fitting(lead: nil, text: text)
            }
        case .shared:
            if paused {
                fitting(lead: AnyView(sign("pause.fill", size: 7)), text: text)
            } else {
                switch content {
                case .ringAndTime: fitting(lead: AnyView(ring), text: text)
                case .time: fitting(lead: nil, text: text)
                case .ring: TimerRing(fraction: timer.fractionLeft(at: now), size: 12)
                case .endTime: fitting(lead: nil, text: timer.end.map(TimerText.shortTime) ?? text, animated: false)
                }
            }
        }
    }

    @ViewBuilder
    private func stopwatchFace(_ stopwatch: Stopwatch, now: Date) -> some View {
        let elapsed = stopwatch.elapsed(at: now)
        let text = TimerText.elapsed(elapsed)
        let sweep = (elapsed.truncatingRemainder(dividingBy: 60)) / 60
        let ringOnly = module.settings.earContent == .ring
        switch role {
        case .companion:
            if stopwatch.isStopped { sign("pause.fill") } else { TimerRing(fraction: sweep, size: 13) }
        case .solo:
            if ringOnly, stopwatch.isRunning {
                TimerRing(fraction: sweep, size: 13)
            } else {
                fitting(lead: nil, text: text, direction: .up)
            }
        case .shared:
            if stopwatch.isStopped {
                fitting(lead: AnyView(sign("pause.fill", size: 7)), text: text, direction: .up)
            } else if ringOnly {
                TimerRing(fraction: sweep, size: 12)
            } else {
                fitting(lead: module.settings.earContent == .time ? nil : AnyView(TimerRing(fraction: sweep, size: 10)), text: text, direction: .up)
            }
        }
    }

    /// The sign and the time if they fit in one ear, else the time alone, smaller for long times.
    private func fitting(lead: AnyView?, text: String, direction: DrumDirection = .down, animated: Bool = true) -> some View {
        ViewThatFits(in: .horizontal) {
            if let lead {
                HStack(spacing: 2) {
                    lead
                    time(text, direction: direction, animated: animated)
                }
                ForEach([9.5, 8.5] as [CGFloat], id: \.self) { size in
                    HStack(spacing: 1.5) {
                        lead.scaleEffect(0.8).frame(width: 8, height: 8)
                        time(text, size: size, direction: direction, animated: animated)
                    }
                }
            }
            time(text, direction: direction, animated: animated)
            time(text, size: 9, direction: direction, animated: animated)
            // The last choice must shrink even a many-hour stopwatch into the available ear.
            Text(text)
                .font(.system(size: 8, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(width: max(0, width - 4))
    }

    private func time(_ text: String, size: CGFloat = 10.5, direction: DrumDirection = .down, animated: Bool = true) -> some View {
        DrumText(
            text: text,
            size: size,
            weight: .semibold,
            style: animated ? module.settings.digitAnimation : .off,
            direction: direction
        )
        .lineLimit(1)
        .fixedSize()
    }

    private func sign(_ symbol: String, size: CGFloat = 11) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white.opacity(0.85))
    }
}

/// The strip under the compact notch when a timer finished while the open notch showed another module.
struct TimerPeek: View {
    let module: TimerModule

    var body: some View {
        let detail = TimerDoneText.detail(module.center)
        HStack(spacing: 6) {
            Image(systemName: "bell.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text("Timer done")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize()
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Timer done, \(detail)"))
    }
}

/// What the Done card and the peek say under "Done": the timer's length, and when it ended if that
/// wasn't just now ("5 min timer · ended 3:42 PM").
@MainActor
enum TimerDoneText {
    static func detail(_ center: TimerCenter) -> String {
        let length = String(localized: "\(TimerText.length(center.timer.total)) timer", comment: "Done card: e.g. 5 min timer")
        guard case .done(let endedAt) = center.timer.phase,
              center.finishedWhileAway || center.now.timeIntervalSince(endedAt) >= 60 else { return length }
        return length + " · " + String(localized: "ended \(TimerText.time(endedAt))", comment: "Done card: when the timer ended")
    }
}
