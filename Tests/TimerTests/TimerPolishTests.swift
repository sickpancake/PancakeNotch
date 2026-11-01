import AppKit
import SwiftUI
import Testing
import TimerCore
@testable import ModuleTimer

/// Rolling digits, the ring's smooth drain and the ear's sizing: the parts that can be checked without
/// drawing anything.
@MainActor
struct TimerPolishTests {
    let start = Date(timeIntervalSinceReferenceDate: 900_000_000)

    // MARK: Rolling digits

    @Test func onlyChangedCharactersRoll() {
        #expect(DrumRoll(from: "4:59", to: "4:58", steadyDigits: 0)?.changed == [3])
        // The minute change: three characters roll together, the colon stays.
        #expect(DrumRoll(from: "5:00", to: "4:59", steadyDigits: 0)?.changed == [0, 2, 3])
        #expect(DrumRoll(from: "0:10", to: "0:09", steadyDigits: 0)?.changed == [2, 3])
    }

    @Test func aChangeOfLengthDoesNotRoll() {
        #expect(DrumRoll(from: "10:00", to: "9:59", steadyDigits: 0) == nil)
        #expect(DrumRoll(from: "59:59", to: "1:00:00", steadyDigits: 0) == nil)
    }

    @Test func steadyDigitsNeverRoll() {
        // A stopwatch: the hundredths change every frame and don't roll; the seconds do.
        #expect(DrumRoll(from: "00:00:01.99", to: "00:00:02.00", steadyDigits: 2)?.changed == [7])
        #expect(DrumRoll(from: "00:00:01.50", to: "00:00:01.51", steadyDigits: 2) == nil)
        #expect(DrumRoll(from: "4:59", to: "4:59", steadyDigits: 0) == nil)
    }

    @Test func trackerKeepsARollWhileOnlyTheTailChanges() {
        let tracker = DrumTracker()
        let begin = Date(timeIntervalSinceReferenceDate: 1)
        #expect(tracker.observe("00:00:01.98", steadyDigits: 2, size: 40, weight: .medium, now: begin) == nil)
        let roll = tracker.observe("00:00:02.01", steadyDigits: 2, size: 40, weight: .medium, now: begin)
        #expect(roll?.changed == [7])
        let generation = tracker.generation
        // The next frame changes only the hundredths: same roll, same start, no restart.
        let later = tracker.observe("00:00:02.04", steadyDigits: 2, size: 40, weight: .medium, now: begin + 0.1)
        #expect(later == roll)
        #expect(tracker.startedAt == begin)
        #expect(tracker.generation == generation)
        // The rolling slot shows the old digit with today's hundredths.
        #expect(tracker.oldText(steadyDigits: 2, now: "00:00:02.04") == "00:00:01.04")
        // A change of length ends it.
        #expect(tracker.observe("0:09", steadyDigits: 0, size: 40, weight: .medium, now: begin + 1) == nil)
    }

    @Test func slotsLineUpWithTheText() {
        let edges = DrumMetrics.edges(of: "10:05", size: 44, weight: .medium)
        #expect(edges.count == 6)
        #expect(edges.first == 0)
        #expect(zip(edges, edges.dropFirst()).allSatisfy { $0 < $1 })
        #expect(abs(edges.last! - DrumMetrics.width(of: "10:05", size: 44, weight: .medium)) < 0.01)
        // Digits are as wide as each other, so a rolling digit's window never changes size.
        let widths = zip(edges, edges.dropFirst()).map { $1 - $0 }
        #expect(abs(widths[0] - widths[1]) < 0.01 && abs(widths[1] - widths[3]) < 0.01)
    }

    @Test func theOpenStopwatchFitsItsPaneWithoutShrinking() {
        // 11 characters at the sizes StopwatchPane uses, in the room each layout has (body 684 wide, 20 padding).
        let text = TimerText.precise(0)
        let alone = DrumMetrics.width(of: text, size: 40, weight: .medium)
        let compact = DrumMetrics.width(of: text, size: 26, weight: .medium)
        #expect(alone < 644 - 22 - 200)
        // Side by side: half the panel less the divider's padding, with the two buttons and a gap beside it.
        #expect(compact + 10 + (30 + 10 + 30) < (644 - 1) / 2 - 14)
    }

    // MARK: The ring

    @Test func aRunningTimersRingDrainsToItsEnd() {
        var timer = CountdownTimer()
        timer.start(60, now: start)
        let plan = RingPlan(timer)
        #expect(plan == .drain(end: start + 60, total: 60))
        #expect(plan.fraction(at: start) == 1)
        #expect(abs(plan.fraction(at: start + 15) - 0.75) < 1e-9)
        #expect(plan.secondsLeft(at: start + 45) == 15)
        #expect(plan.fraction(at: start + 90) == 0)
        #expect(plan.secondsLeft(at: start + 90) == 0)
    }

    @Test func aPausedRingHoldsTheExactFraction() {
        var timer = CountdownTimer()
        timer.start(60, now: start)
        timer.pause(now: start + 15)
        let plan = RingPlan(timer)
        #expect(plan == .still(0.75))
        // Whenever it's asked, however much later.
        #expect(plan.fraction(at: start + 1000) == 0.75)
        #expect(plan.secondsLeft(at: start + 1000) == 0)
        timer.resume(now: start + 100)
        #expect(RingPlan(timer) == .drain(end: start + 145, total: 60))
    }

    @Test func plusOneMinuteStartsAFreshRing() {
        var timer = CountdownTimer()
        timer.start(5, now: start)
        let finished = timer.finishIfDue(now: start + 5)
        #expect(finished)
        #expect(RingPlan(timer) == .still(0))
        timer.addMinute(now: start + 6)
        #expect(RingPlan(timer) == .drain(end: start + 66, total: 60))
        #expect(RingPlan(timer).fraction(at: start + 6) == 1)
    }

    @Test func idleAndDoneRingsAreEmpty() {
        #expect(RingPlan(CountdownTimer()) == .still(0))
    }

    @Test func aShortTimerMovesSmoothlyAndALongOneRedrawsRarely() {
        // 3 seconds, a 64 pt ring at 2x: one step a frame (60 a second), ~1 px apart, so it looks continuous.
        let short = RingSteps.make(fraction: 1, seconds: 3, travelPixels: 2 * .pi * 32 * 2)
        #expect(short.values.count == 180)
        #expect(short.times.count == 181)
        // An hour on the 10 pt ear ring: a step per pixel of travel, not per frame.
        let long = RingSteps.make(fraction: 1, seconds: 3600, travelPixels: 2 * .pi * 5 * 2)
        #expect(long.values.count == 63)
        // It starts where the ring is now, only goes down, and its moments run from 0 to 1.
        #expect(long.values.first == 1)
        #expect(zip(long.values, long.values.dropFirst()).allSatisfy { $0 > $1 })
        #expect(long.times.first == 0 && long.times.last == 1)
        #expect(zip(long.times, long.times.dropFirst()).allSatisfy { $0 < $1 })
        // Half a ring left: it starts at a half.
        #expect(RingSteps.make(fraction: 0.5, seconds: 10, travelPixels: 100).values.first == 0.5)
        // Never an empty list, even for a sliver of time.
        #expect(RingSteps.make(fraction: 0.01, seconds: 0.001, travelPixels: 0.2).values.count == 1)
    }

    @Test func theRingViewFollowsThePlanAndStartsAgainWhenAsked() {
        let view = RingView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        var clock = start
        let now = { clock }
        view.apply(plan: .drain(end: start + 10, total: 20), epoch: 0, lineWidth: 4, now: now)
        #expect(view.arc.animation(forKey: "drain") != nil)
        #expect(view.arc.strokeEnd == 0)
        // Paused: no animation, held at the exact fraction.
        view.apply(plan: .still(0.375), epoch: 0, lineWidth: 4, now: now)
        #expect(view.arc.animation(forKey: "drain") == nil)
        #expect(view.arc.strokeEnd == 0.375)
        // Resumed.
        view.apply(plan: .drain(end: start + 20, total: 20), epoch: 0, lineWidth: 4, now: now)
        #expect(view.arc.animation(forKey: "drain") != nil)
        // A clock jump: same plan, new epoch: it starts again from the real time (here, 4 s in).
        clock = start + 4
        view.apply(plan: .drain(end: start + 20, total: 20), epoch: 1, lineWidth: 4, now: now)
        let drain = view.arc.animation(forKey: "drain") as? CAKeyframeAnimation
        #expect(drain?.duration == 16)
        #expect(drain?.values?.first as? Double == 0.8)
        // Past the end: nothing left to drain.
        clock = start + 30
        view.apply(plan: .drain(end: start + 20, total: 20), epoch: 2, lineWidth: 4, now: now)
        #expect(view.arc.animation(forKey: "drain") == nil)
        #expect(view.arc.strokeEnd == 0)
    }

    @Test func aWakeOrClockChangeBumpsTheEpoch() {
        let center = TimerCenter(now: { Date(timeIntervalSinceReferenceDate: 900_000_000) })
        let before = center.clockEpoch
        center.timeMayHaveJumped()
        #expect(center.clockEpoch == before + 1)
    }

    // MARK: The ear's size

    @Test func theEarKeepsItsSizeAsTheCountdownLosesADigit() {
        // Sized for the widest the countdown gets, so 10:00 → 9:59 never changes the size.
        let wide = EarFit.choose(widest: "25:00", hasLead: true, available: 40)
        let again = EarFit.choose(widest: "25:00", hasLead: true, available: 40)
        #expect(wide == again)
        // Choices differ only when the widest text differs.
        #expect(EarFit.choose(widest: "9:59", hasLead: true, available: 40).size >= wide.size)
    }

    @Test func theEarShrinksLongTimesToFitAndDropsTheSignFirst() {
        let measure: (String, CGFloat) -> CGFloat = { DrumMetrics.width(of: $0, size: $1, weight: .semibold) }
        for widest in ["0:42", "25:00", "1:04:59", "23:59:59", "24:00:00"] {
            for hasLead in [false, true] {
                for available in [30, 36, 44, 52] as [CGFloat] {
                    let fit = EarFit.choose(widest: widest, hasLead: hasLead, available: available)
                    let used = measure(widest, fit.size) + (fit.showsLead ? fit.leadSide + fit.spacing : 0)
                    #expect(used <= available + 0.01, "\(widest) lead \(hasLead) in \(available)")
                    #expect(fit.size <= 10.5)
                    if !hasLead { #expect(!fit.showsLead) }
                }
            }
        }
        // Plenty of room: full size with the sign. Less: the sign goes before the digits shrink below 9.
        let roomy = EarFit.choose(widest: "0:42", hasLead: true, available: 60)
        #expect(roomy.size == 10.5 && roomy.showsLead)
        let tight = EarFit.choose(widest: "23:59:59", hasLead: true, available: 40)
        #expect(!tight.showsLead)
    }
}
