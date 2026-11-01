import NotchCore
import SwiftUI
import TimerCore

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
        // The widest the countdown will be: the layout is chosen for that, so it doesn't change size
        // when 10:00 becomes 9:59.
        let widest = TimerText.countdown(timer.total)
        switch role {
        case .companion:
            if paused { sign("pause.fill") } else if content == .ringAndTime || content == .ring {
                TimerRing(module: module, size: 13)
            } else {
                sign(module.symbol)
            }
        case .solo:
            if content == .ring, !paused {
                TimerRing(module: module, size: 13)
            } else if content == .endTime, let end = timer.end {
                fitting(lead: nil, text: TimerText.shortTime(end), animated: false)
            } else {
                fitting(lead: nil, text: text, widest: widest)
            }
        case .shared:
            if paused {
                fitting(lead: .pause, text: text, widest: widest)
            } else {
                switch content {
                case .ringAndTime: fitting(lead: .ring, text: text, widest: widest)
                case .time: fitting(lead: nil, text: text, widest: widest)
                case .ring: TimerRing(module: module, size: 12)
                case .endTime: fitting(lead: nil, text: timer.end.map(TimerText.shortTime) ?? text, animated: false)
                }
            }
        }
    }

    /// The stopwatch has no ring (nothing to fill up): a stopwatch sign where the timer has its ring, a pause
    /// sign while it's stopped. "Ring only" has nothing to show for it, so it shows the sign and the time.
    @ViewBuilder
    private func stopwatchFace(_ stopwatch: Stopwatch, now: Date) -> some View {
        let text = TimerText.elapsed(stopwatch.elapsed(at: now))
        // Sized for "00:00", so the size holds from 0:00 to 59:59 (a longer time is sized for itself).
        let widest = "00:00"
        switch role {
        case .companion:
            sign(stopwatch.isStopped ? "pause.fill" : "stopwatch")
        case .solo:
            fitting(lead: nil, text: text, widest: widest, direction: .up)
        case .shared:
            if stopwatch.isStopped {
                fitting(lead: .pause, text: text, widest: widest, direction: .up)
            } else {
                fitting(lead: module.settings.earContent == .time ? nil : .stopwatch, text: text, widest: widest, direction: .up)
            }
        }
    }

    /// What can go in front of the time when the ear is shared.
    private enum Lead {
        case ring, pause, stopwatch
    }

    /// The sign and the time if they fit in one ear, else the time alone, smaller for long times. What fits is
    /// worked out from `widest` (the longest the time will be), never from the time shown, so the size
    /// doesn't jump when the time gets a digit shorter or longer.
    private func fitting(lead: Lead?, text: String, widest: String? = nil, direction: DrumDirection = .down, animated: Bool = true) -> some View {
        let fit = EarFit.choose(
            widest: widest.map { $0.count > text.count ? $0 : text } ?? text,
            hasLead: lead != nil,
            available: width - 4
        )
        return HStack(spacing: fit.spacing) {
            if let lead, fit.showsLead {
                leadView(lead).scaleEffect(fit.leadSide / EarFit.leadSide).frame(width: fit.leadSide, height: fit.leadSide)
            }
            time(text, size: fit.size, direction: direction, animated: animated)
        }
        .frame(width: max(0, width - 4))
    }

    @ViewBuilder
    private func leadView(_ lead: Lead) -> some View {
        switch lead {
        case .ring: TimerRing(module: module, size: 10)
        case .pause: sign("pause.fill", size: 7)
        case .stopwatch: sign("stopwatch", size: 9)
        }
    }

    private func time(_ text: String, size: CGFloat, direction: DrumDirection, animated: Bool) -> some View {
        DrumText(
            text: text,
            size: size,
            weight: .semibold,
            style: animated ? module.settings.digitAnimation : .off,
            direction: direction
        )
    }

    private func sign(_ symbol: String, size: CGFloat = 11) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white.opacity(0.85))
    }
}

/// The strip under the compact notch for a finished timer: when it finished while the open notch showed
/// another module, or when "When a timer ends" is "Show a strip". Hovering or clicking the notch opens the
/// Done card.
struct TimerPeek: View {
    let module: TimerModule

    var body: some View {
        let detail = TimerDoneText.detail(module.center)
        // The strip is only as wide as the compact notch: when "ended 3:42 PM" doesn't fit after a long
        // length, the length alone does (the Done card has the rest).
        ViewThatFits(in: .horizontal) {
            line(detail)
            line(TimerDoneText.length(module.center))
            line(TimerDoneText.length(module.center), truncates: true)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Timer done, \(detail)"))
    }

    private func line(_ detail: String, truncates: Bool = false) -> some View {
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
                .fixedSize(horizontal: !truncates, vertical: false)
        }
    }
}

/// What the Done card and the peek say under "Done": the timer's length, and when it ended if that
/// wasn't just now ("5 min timer · ended 3:42 PM").
@MainActor
enum TimerDoneText {
    static func length(_ center: TimerCenter) -> String {
        String(localized: "\(TimerText.length(center.timer.total)) timer", comment: "Done card: e.g. 5 min timer")
    }

    static func detail(_ center: TimerCenter) -> String {
        let length = length(center)
        guard case .done(let endedAt) = center.timer.phase,
              center.finishedWhileAway || center.now.timeIntervalSince(endedAt) >= 60 else { return length }
        return length + " · " + String(localized: "ended \(TimerText.time(endedAt))", comment: "Done card: when the timer ended")
    }
}

/// How the time fits in one ear, with or without a sign in front. Pure: it measures the text in the font it's
/// drawn in and picks the biggest size that fits, so it can be checked without drawing.
enum EarFit {
    struct Choice: Equatable {
        var size: CGFloat
        var showsLead: Bool
        var leadSide: CGFloat
        var spacing: CGFloat
    }

    /// The sign's full size, and the smaller one used when space is short.
    static let leadSide: CGFloat = 10
    static let smallLeadSide: CGFloat = 8

    /// - Parameters:
    ///   - widest: the longest the text will be.
    ///   - hasLead: a sign could go before it.
    ///   - available: the width of the ear.
    ///   - measure: how wide the text is at a size (the real font by default).
    static func choose(
        widest: String,
        hasLead: Bool,
        available: CGFloat,
        measure: (String, CGFloat) -> CGFloat = { DrumMetrics.width(of: $0, size: $1, weight: .semibold) }
    ) -> Choice {
        if hasLead {
            for (size, side, spacing) in [(10.5, leadSide, 2.0), (9.5, smallLeadSide, 1.5), (8.5, smallLeadSide, 1.5)] as [(CGFloat, CGFloat, CGFloat)]
            where side + spacing + measure(widest, size) <= available {
                return Choice(size: size, showsLead: true, leadSide: side, spacing: spacing)
            }
        }
        for size in [10.5, 9] as [CGFloat] where measure(widest, size) <= available {
            return Choice(size: size, showsLead: false, leadSide: leadSide, spacing: 0)
        }
        // Even a many-hour stopwatch has to fit: shrink from 8 until it does (widths don't scale evenly
        // with the size, as the font's spacing changes with it).
        var size: CGFloat = 8
        while size > 4, measure(widest, size) > available { size -= 0.25 }
        return Choice(size: size, showsLead: false, leadSide: leadSide, spacing: 0)
    }
}
