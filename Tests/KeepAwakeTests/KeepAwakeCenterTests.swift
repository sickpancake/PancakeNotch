import Foundation
import Testing
@testable import KeepAwakeCore

/// A clock the test moves by hand.
@MainActor
final class TestClock {
    var now = Date(timeIntervalSinceReferenceDate: 900_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Keep Awake's rules (ADR-0041), without IOKit: a pretend hold, a hand-moved clock, hand-set power.
@MainActor
struct KeepAwakeCenterTests {
    let clock = TestClock()
    let hold = PretendPowerHold()
    let defaults: UserDefaults
    let settings: KeepAwakeSettings

    init() {
        let name = "KeepAwakeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = KeepAwakeSettings(defaults: defaults)
    }

    func makeCenter(boot: Date? = Date(timeIntervalSinceReferenceDate: 899_000_000), power: PowerState = .pluggedIn) -> KeepAwakeCenter {
        let clock = clock
        return KeepAwakeCenter(settings: settings, defaults: defaults, holder: hold, now: { clock.now }, power: { power }, bootTime: { boot })
    }

    @Test func startsOffAndTurnOnHoldsTheScreen() {
        let center = makeCenter()
        #expect(!center.isHolding)
        #expect(hold.kind == nil)
        center.turnOn()
        #expect(center.isHolding)
        #expect(hold.kind == .screen)
        // A plain Turn On is an hour the first time.
        #expect(center.remaining(at: clock.now) == 3600)
    }

    @Test func canTurnOffKeepsOnlyTheSystemAwake() {
        settings.screen = .canTurnOff
        let center = makeCenter()
        center.turnOn(.untilStopped)
        #expect(hold.kind == .system)
        #expect(center.remaining(at: clock.now) == nil)
    }

    @Test func turnOnRemembersTheLength() {
        let center = makeCenter()
        center.turnOn(.timed(2 * 3600))
        center.turnOff()
        center.turnOn()
        #expect(center.remaining(at: clock.now) == 7200)
        #expect(settings.lastLength == .timed(2 * 3600))
    }

    @Test func extendAddsHalfAnHourUpToADay() {
        let center = makeCenter()
        center.turnOn(.timed(30 * 60))
        center.extend()
        #expect(center.remaining(at: clock.now) == 3600)
        for _ in 0..<60 { center.extend() }
        #expect(center.remaining(at: clock.now) == KeepAwakeCenter.longest)
        // Nothing to extend on one until you stop.
        center.turnOn(.untilStopped)
        center.extend()
        #expect(center.session?.end == nil)
    }

    @Test func plusThirtyIsOffAtTheDayLimitAndTellsNothing() {
        let center = makeCenter()
        var events: [KeepAwakeEvent] = []
        center.onEvent = { events.append($0) }
        center.turnOn(.timed(4 * 3600))
        #expect(center.canExtend)
        while center.canExtend { center.extend() }
        #expect(center.remaining(at: clock.now)! > KeepAwakeCenter.longest - 60)
        let before = events.count
        center.extend()
        // Nothing added, so nothing to tell a lesson.
        #expect(events.count == before)
        // Time passing makes room again.
        clock.advance(3600)
        #expect(center.canExtend)
        // Nothing to extend when it holds for work only, or for one until you stop.
        center.turnOn(.untilStopped)
        #expect(!center.canExtend)
    }

    @Test func endTimeSaysTomorrow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 22))!
        let later = now.addingTimeInterval(3600)
        let tomorrow = now.addingTimeInterval(6 * 3600)
        #expect(!KeepAwakeText.until(later, now: now, calendar: calendar).contains("tomorrow"))
        #expect(KeepAwakeText.until(tomorrow, now: now, calendar: calendar).contains("tomorrow"))
    }

    @Test func aGoneCenterIsNotKeptByItsTimer() async {
        weak var gone: KeepAwakeCenter?
        do {
            let center = KeepAwakeCenter(settings: settings, isPractice: true)
            center.turnOn(.timed(1800))
            gone = center
            // Let its timer start sleeping first.
            for _ in 0..<5 { await Task.yield() }
        }
        await Task.yield()
        await Task.yield()
        #expect(gone == nil)
    }

    @Test func timeUpEndsWithAStripOnlyWhenTheMacCanSleep() {
        let center = makeCenter()
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        center.turnOn(.timed(30 * 60))
        clock.advance(30 * 60)
        center.timeMayHaveJumped()
        #expect(!center.isHolding)
        #expect(ends == [.timeUp])
        #expect(hold.kind == nil)

        // A chosen deadline also stops automatic Keep Awake for the current work.
        ends = []
        center.setWork(agents: true, converting: false)
        center.turnOn(.timed(30 * 60))
        clock.advance(30 * 60)
        center.timeMayHaveJumped()
        #expect(center.session == nil)
        #expect(!center.isHolding)
        #expect(center.pausedForWork)
        #expect(hold.kind == nil)
        #expect(ends == [.timeUp])
        center.setWork(agents: true, converting: true)
        #expect(!center.isHolding)
        center.setWork(agents: false, converting: false)
        center.setWork(agents: true, converting: false)
        #expect(center.isHolding)
    }

    @Test func timeUpDropsAnAutomaticTailAndDoesNotRestartIt() {
        let center = makeCenter()
        center.turnOn(.timed(1800))
        clock.advance(1790)
        center.setWork(agents: true, converting: false)
        center.setWork(agents: false, converting: false)
        #expect(center.tailEnd != nil)
        clock.advance(10)
        center.timeMayHaveJumped()
        #expect(!center.isHolding)
        #expect(center.tailEnd == nil)
        #expect(!center.pausedForWork)
        center.setWork(agents: false, converting: false)
        #expect(!center.isHolding)
        center.setWork(agents: false, converting: true)
        #expect(center.isHolding)
    }

    @Test func timeUpDuringSleepEndsQuietly() {
        let center = makeCenter()
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        center.turnOn(.timed(30 * 60))
        clock.advance(3 * 3600)
        center.timeMayHaveJumped()
        #expect(center.session == nil)
        #expect(ends.isEmpty)
    }

    @Test func workKeepsItAwakeWithATwoMinuteTail() {
        let center = makeCenter()
        center.setWork(agents: true, converting: false)
        #expect(center.isHolding)
        #expect(center.work == .agents)
        center.setWork(agents: false, converting: false)
        #expect(center.isHolding)
        #expect(center.work == .finishing(until: clock.now.addingTimeInterval(120)))
        clock.advance(119)
        center.timeMayHaveJumped()
        #expect(center.isHolding)
        clock.advance(1)
        center.timeMayHaveJumped()
        #expect(!center.isHolding)
        // Work starting again during the tail cancels it.
        center.setWork(agents: false, converting: true)
        center.setWork(agents: false, converting: false)
        center.setWork(agents: true, converting: false)
        #expect(center.tailEnd == nil)
    }

    @Test func switchingTheWorksModuleOffStartsNoTail() {
        let center = makeCenter()
        center.setWork(agents: true, converting: false)
        #expect(center.isHolding)
        // The Agents module was switched off mid-work: nothing runs, so it lets go at once.
        center.setWork(agents: false, converting: false, startsTail: false)
        #expect(center.tailEnd == nil)
        #expect(!center.isHolding)
        #expect(hold.kind == nil)
    }

    @Test func automaticEndingShowsNoStrip() {
        let center = makeCenter()
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        center.setWork(agents: false, converting: true)
        center.setWork(agents: false, converting: false)
        clock.advance(200)
        center.timeMayHaveJumped()
        #expect(!center.isHolding)
        #expect(ends.isEmpty)
    }

    @Test func switchedOffSourcesDontCount() {
        settings.whileAgentsWork = false
        let center = makeCenter()
        center.setWork(agents: true, converting: false)
        #expect(!center.isHolding)
        // And stopping work that didn't count starts no tail.
        center.setWork(agents: false, converting: false)
        #expect(center.tailEnd == nil)
    }

    @Test func turnOffDuringWorkStaysOffUntilThatWorkEnds() {
        let center = makeCenter()
        center.setWork(agents: true, converting: false)
        center.turnOff()
        #expect(!center.isHolding)
        #expect(center.pausedForWork)
        // More work joining doesn't turn it back on.
        center.setWork(agents: true, converting: true)
        #expect(!center.isHolding)
        // The work ends: no tail, and the pause is over.
        center.setWork(agents: false, converting: false)
        #expect(!center.pausedForWork)
        #expect(center.tailEnd == nil)
        #expect(!center.isHolding)
        // The next run turns it on again.
        center.setWork(agents: true, converting: false)
        #expect(center.isHolding)
    }

    @Test func turnOffDuringTheTailEndsItWithoutAPause() {
        let center = makeCenter()
        center.setWork(agents: true, converting: false)
        center.setWork(agents: false, converting: false)
        center.turnOff()
        #expect(!center.isHolding)
        #expect(!center.pausedForWork)
        center.setWork(agents: true, converting: false)
        #expect(center.isHolding)
    }

    @Test func turnOnEndsThePause() {
        let center = makeCenter()
        center.setWork(agents: true, converting: false)
        center.turnOff()
        center.turnOn(.timed(30 * 60))
        #expect(!center.pausedForWork)
        clock.advance(30 * 60)
        center.timeMayHaveJumped()
        // A chosen time ends even when the agent still works.
        #expect(!center.isHolding)
        #expect(center.pausedForWork)
    }

    @Test func lowBatteryEndsEverythingWithAStripAndBlocksTurnOn() {
        let center = makeCenter()
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        center.turnOn(.untilStopped)
        center.setPower(PowerState(onBattery: true, percent: 21))
        #expect(center.isHolding)
        center.setPower(PowerState(onBattery: true, percent: 20))
        #expect(!center.isHolding)
        #expect(center.session == nil)
        #expect(ends == [.batteryLow])
        #expect(!center.canTurnOn)
        center.turnOn()
        #expect(!center.isHolding)
        // Agents don't keep it awake either, until it's plugged in.
        center.setWork(agents: true, converting: false)
        #expect(!center.isHolding)
        center.setPower(PowerState(onBattery: false, percent: 20))
        #expect(center.isHolding)
        #expect(center.canTurnOn)
        // Plugged in: the session you had comes back, and a strip says so.
        #expect(center.session?.end == nil && center.session != nil)
        #expect(ends == [.batteryLow, .backOn])
    }

    // MARK: Low battery and plugging in (ADR-0041 amendment 2026-11-03)

    @Test func pluggingInBringsBackTheRestOfTheSession() {
        settings.batteryCutoff = 10
        let center = makeCenter()
        center.turnOn(.timed(2 * 3600))
        clock.advance(1800)
        center.setPower(PowerState(onBattery: true, percent: 10))
        #expect(!center.isHolding)
        #expect(center.stoppedForBattery)
        clock.advance(600)
        center.setPower(PowerState(onBattery: false, percent: 11))
        #expect(center.isHolding)
        #expect(center.remaining(at: clock.now) == 4800)
        #expect(!center.stoppedForBattery)
    }

    @Test func aSessionThatRanOutWhileStoppedStaysGone() {
        let center = makeCenter()
        var notices: [KeepAwakeNotice] = []
        center.onNotice = { notices.append($0) }
        center.turnOn(.timed(1800))
        center.setPower(PowerState(onBattery: true, percent: 15))
        clock.advance(3600)
        center.timeMayHaveJumped()
        center.setPower(PowerState(onBattery: false, percent: 15))
        #expect(center.session == nil)
        #expect(!center.isHolding)
        // Nothing came back, so nothing to tell.
        #expect(notices == [.batteryLow])
    }

    @Test func stayOffKeepsItOffUntilTheWorkEnds() {
        settings.plugIn = .stayOff
        let center = makeCenter()
        var notices: [KeepAwakeNotice] = []
        center.onNotice = { notices.append($0) }
        center.turnOn(.untilStopped)
        center.setWork(agents: true, converting: false)
        center.setPower(PowerState(onBattery: true, percent: 12))
        center.setPower(PowerState(onBattery: false, percent: 12))
        #expect(!center.isHolding)
        #expect(center.session == nil)
        #expect(center.pausedForWork)
        #expect(notices == [.batteryLow])
        // That work ends; the next run keeps it awake again.
        center.setWork(agents: false, converting: false)
        #expect(!center.isHolding)
        center.setWork(agents: true, converting: false)
        #expect(center.isHolding)
        // And Turn On works at once.
        center.setWork(agents: false, converting: false)
        center.turnOn(.timed(1800))
        #expect(center.isHolding)
    }

    @Test func keepGoingCarriesOnAndTellsOnce() {
        settings.lowBattery = .keepGoing
        let center = makeCenter()
        var notices: [KeepAwakeNotice] = []
        center.onNotice = { notices.append($0) }
        center.turnOn(.untilStopped)
        center.setPower(PowerState(onBattery: true, percent: 20))
        center.setPower(PowerState(onBattery: true, percent: 19))
        center.setPower(PowerState(onBattery: true, percent: 5))
        #expect(center.isHolding)
        #expect(center.session != nil)
        #expect(notices == [.batteryLowKeepsGoing])
        // Turning it on below the level works too.
        center.turnOff()
        #expect(center.canTurnOn)
        center.turnOn()
        #expect(center.isHolding)
        // Nothing was stopped, so plugging in tells nothing.
        center.setPower(PowerState(onBattery: false, percent: 5))
        #expect(notices == [.batteryLowKeepsGoing])
    }

    @Test func keepGoingSaysNothingWhenNothingHolds() {
        settings.lowBattery = .keepGoing
        let center = makeCenter()
        var notices: [KeepAwakeNotice] = []
        center.onNotice = { notices.append($0) }
        center.setPower(PowerState(onBattery: true, percent: 5))
        #expect(notices.isEmpty)
    }

    @Test func switchingToKeepGoingWhileStoppedBringsItBackQuietly() {
        let center = makeCenter()
        var notices: [KeepAwakeNotice] = []
        center.onNotice = { notices.append($0) }
        center.turnOn(.untilStopped)
        center.setPower(PowerState(onBattery: true, percent: 15))
        #expect(!center.isHolding)
        settings.lowBattery = .keepGoing
        #expect(center.isHolding)
        #expect(center.session != nil)
        #expect(notices == [.batteryLow])
    }

    @Test func aLowerLevelWhileStoppedBringsItBackQuietly() {
        let center = makeCenter()
        center.turnOn(.untilStopped)
        center.setPower(PowerState(onBattery: true, percent: 15))
        settings.batteryCutoff = 10
        #expect(center.isHolding)
        #expect(center.session != nil)
    }

    @Test func switchingTheModuleOffForgetsWhatTheBatteryStopped() {
        let center = makeCenter()
        center.turnOn(.untilStopped)
        center.setPower(PowerState(onBattery: true, percent: 15))
        settings.isEnabled = false
        settings.isEnabled = true
        center.setPower(PowerState(onBattery: false, percent: 15))
        #expect(center.session == nil)
        #expect(!center.isHolding)
    }

    @Test func reopeningOnALowBatteryBringsItBackWhenPluggedIn() {
        makeCenter().turnOn(.untilStopped)
        let center = makeCenter(power: PowerState(onBattery: true, percent: 10))
        #expect(center.session == nil)
        #expect(center.stoppedForBattery)
        center.setPower(PowerState(onBattery: false, percent: 10))
        #expect(center.session != nil)
        #expect(center.isHolding)
    }

    @Test func automaticWorkComesBackWithAStripWhenPluggedIn() {
        let center = makeCenter()
        var notices: [KeepAwakeNotice] = []
        center.onNotice = { notices.append($0) }
        center.setWork(agents: true, converting: false)
        center.setPower(PowerState(onBattery: true, percent: 15))
        #expect(!center.isHolding)
        center.setPower(PowerState(onBattery: false, percent: 15))
        #expect(center.isHolding)
        #expect(notices == [.batteryLow, .backOn])
    }

    @Test func lowBatteryWhileNothingHoldsShowsNoStrip() {
        let center = makeCenter()
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        center.setPower(PowerState(onBattery: true, percent: 5))
        #expect(ends.isEmpty)
    }

    @Test func neverCutoffIgnoresTheBattery() {
        settings.batteryCutoff = nil
        let center = makeCenter()
        center.setPower(PowerState(onBattery: true, percent: 3))
        center.turnOn()
        #expect(center.isHolding)
    }

    @Test func switchingTheModuleOffLetsGo() async {
        let center = makeCenter()
        center.turnOn(.untilStopped)
        settings.isEnabled = false
        await Task.yield()
        await Task.yield()
        #expect(!center.isHolding)
        #expect(center.session == nil)
        #expect(hold.kind == nil)
        center.turnOn()
        #expect(!center.isHolding)
    }

    @Test func changingTheScreenSettingSwapsTheHold() async {
        let center = makeCenter()
        center.turnOn()
        settings.screen = .canTurnOff
        await Task.yield()
        await Task.yield()
        #expect(hold.kind == .system)
    }

    // MARK: Reopening

    @Test func carriesOnAfterReopeningButNotAfterARestart() {
        let boot = Date(timeIntervalSinceReferenceDate: 899_000_000)
        makeCenter(boot: boot).turnOn(.timed(3600))
        clock.advance(600)
        #expect(makeCenter(boot: boot).session != nil)
        // The Mac restarted: it starts off.
        #expect(makeCenter(boot: boot.addingTimeInterval(5000)).session == nil)
    }

    @Test func carryOnAfterRestartKeepsItAcrossARestart() {
        settings.reopen = .carryOnAfterRestart
        let boot = Date(timeIntervalSinceReferenceDate: 899_000_000)
        makeCenter(boot: boot).turnOn(.untilStopped)
        #expect(makeCenter(boot: boot.addingTimeInterval(5000)).session != nil)
    }

    @Test func startOffForgetsIt() {
        settings.reopen = .startOff
        makeCenter().turnOn(.untilStopped)
        #expect(makeCenter().session == nil)
    }

    @Test func aSessionThatRanOutWhileQuitIsGone() {
        makeCenter().turnOn(.timed(1800))
        clock.advance(1800)
        #expect(makeCenter().session == nil)
    }

    @Test func reopeningOnALowBatteryStartsOff() {
        makeCenter().turnOn(.untilStopped)
        #expect(makeCenter(power: PowerState(onBattery: true, percent: 10)).session == nil)
    }

    @Test func settingsKeepOddSavedValuesSafe() {
        defaults.set(37, forKey: "keepAwake.batteryCutoff")
        defaults.set("nonsense", forKey: "keepAwake.screen")
        let fresh = KeepAwakeSettings(defaults: defaults)
        #expect(fresh.batteryCutoff == KeepAwakeSettings.defaultCutoff)
        #expect(fresh.screen == .staysOn)
        defaults.set(0, forKey: "keepAwake.batteryCutoff")
        #expect(KeepAwakeSettings(defaults: defaults).batteryCutoff == nil)
    }
}
