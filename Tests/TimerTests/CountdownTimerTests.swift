import Foundation
import Testing
@testable import TimerCore

struct CountdownTimerTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func countsDownFromItsEndDate() {
        var timer = CountdownTimer()
        timer.start(300, now: start)
        #expect(timer.remaining(at: start + 60) == 240)
        #expect(timer.fractionLeft(at: start + 150) == 0.5)
        #expect(!finish(&timer, at: start + 299.9))
        #expect(finish(&timer, at: start + 300))
        #expect(timer.phase == .done(endedAt: start + 300))
    }

    @Test func finishesOnlyOnce() {
        var timer = CountdownTimer()
        timer.start(60, now: start)
        #expect(finish(&timer, at: start + 61))
        // The wake, the clock check and the alarm all ask; only the first finishes it.
        #expect(!finish(&timer, at: start + 62))
        #expect(!finish(&timer, at: start + 3600))
    }

    @Test func pauseKeepsTheTimeLeft() {
        var timer = CountdownTimer()
        timer.start(100, now: start)
        timer.pause(now: start + 30)
        #expect(timer.phase == .paused(remaining: 70))
        // Paused, nothing finishes however long it waits.
        #expect(!finish(&timer, at: start + 10_000))
        timer.resume(now: start + 500)
        #expect(timer.end == start + 570)
    }

    @Test func pauseIsRefusedOnceTheEndHasCome() {
        var timer = CountdownTimer()
        timer.start(10, now: start)
        timer.pause(now: start + 10)
        #expect(timer.isRunning)
    }

    @Test func aRunningTimerCantBeReplaced() {
        var timer = CountdownTimer()
        timer.start(100, now: start)
        timer.start(5, now: start + 1)
        #expect(timer.end == start + 100)
    }

    @Test func doneCardActions() {
        var timer = CountdownTimer()
        timer.start(120, now: start)
        _ = timer.finishIfDue(now: start + 120)
        timer.addMinute(now: start + 200)
        #expect(timer.end == start + 260)
        #expect(timer.total == 60)
        _ = timer.finishIfDue(now: start + 260)
        timer.restart(now: start + 300)
        #expect(timer.end == start + 420)
        #expect(timer.total == 120)
        _ = timer.finishIfDue(now: start + 420)
        timer.stop()
        #expect(timer.isIdle)
    }

    @Test func lengthsAreWholeSecondsUpToADay() {
        var timer = CountdownTimer()
        timer.start(0.4, now: start)
        #expect(timer.isIdle)
        timer.start(100_000, now: start)
        #expect(timer.duration == CountdownTimer.longest)
    }

    @Test func keepsWorkingAfterSavingAndLoading() throws {
        var timer = CountdownTimer()
        timer.start(90, now: start)
        let loaded = try JSONDecoder().decode(CountdownTimer.self, from: JSONEncoder().encode(timer))
        #expect(loaded == timer)
    }
}

struct StopwatchTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    /// The clock set back after a lap: no negative lap, and no total below the last lap.
    @Test func aClockSetBackNeverMakesANegativeLap() {
        var watch = Stopwatch()
        watch.start(now: start)
        watch.lap(now: start + 10)
        #expect(watch.elapsed(at: start + 5) == 10)
        watch.lap(now: start + 5)
        #expect(watch.laps(at: start + 5).allSatisfy { $0.time >= 0 })
    }

    @Test func lapsStopAtTheLimit() {
        var watch = Stopwatch()
        watch.start(now: start)
        for index in 1...Stopwatch.mostLaps { watch.lap(now: start + Double(index)) }
        #expect(!watch.canLap)
        watch.lap(now: start + 5_000)
        #expect(watch.lapTotals.count == Stopwatch.mostLaps)
    }

    @Test func countsAndStops() {
        var watch = Stopwatch()
        watch.start(now: start)
        #expect(abs(watch.elapsed(at: start + 12.34) - 12.34) < 0.000_1)
        watch.stop(now: start + 20)
        #expect(watch.elapsed(at: start + 999) == 20)
        watch.start(now: start + 100)
        #expect(watch.elapsed(at: start + 105) == 25)
    }

    @Test func aClockMovedBackDoesntCountBackward() {
        var watch = Stopwatch()
        watch.start(now: start)
        #expect(watch.elapsed(at: start - 50) == 0)
    }

    @Test func lapsNewestFirstWithFastestAndSlowest() {
        var watch = Stopwatch()
        watch.start(now: start)
        watch.lap(now: start + 10) // 10
        watch.lap(now: start + 18) // 8, fastest
        #expect(watch.laps(at: start + 20).allSatisfy { $0.mark == nil })
        watch.lap(now: start + 30) // 12, slowest
        let laps = watch.laps(at: start + 31)
        #expect(laps.map(\.number) == [4, 3, 2, 1])
        #expect(laps[0].isCurrent && laps[0].time == 1)
        #expect(laps[1].mark == .slowest)
        #expect(laps[2].mark == .fastest)
        #expect(laps[3].mark == nil)
    }

    @Test func resetOnlyWhenStopped() {
        var watch = Stopwatch()
        watch.start(now: start)
        watch.lap(now: start + 5)
        watch.reset()
        #expect(watch.isRunning)
        watch.stop(now: start + 6)
        watch.reset()
        #expect(watch.isIdle && watch.lapTotals.isEmpty)
    }
}

struct TimerTextTests {
    @Test func countdownRoundsUpLikeAPhone() {
        #expect(TimerText.countdown(0.3) == "0:01")
        #expect(TimerText.countdown(0) == "0:00")
        #expect(TimerText.countdown(299.5) == "5:00")
        #expect(TimerText.countdown(3899) == "1:04:59")
    }

    @Test func stopwatchToTheHundredth() {
        #expect(TimerText.precise(12.345) == "00:12.34")
        #expect(TimerText.precise(3723.45) == "1:02:03.45")
        #expect(TimerText.elapsed(59.99) == "0:59")
    }
}

/// `finishIfDue` changes the timer, which `#expect` can't do inline.
private func finish(_ timer: inout CountdownTimer, at now: Date) -> Bool {
    timer.finishIfDue(now: now)
}
