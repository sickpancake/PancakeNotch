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

    @Test func timeUpEndsWithAStripOnlyWhenTheMacCanSleep() {
        let center = makeCenter()
        var ends: [KeepAwakeEnd] = []
        center.onEndedByItself = { ends.append($0) }
        center.turnOn(.timed(30 * 60))
        clock.advance(30 * 60)
        center.timeMayHaveJumped()
        #expect(!center.isHolding)
        #expect(ends == [.timeUp])
        #expect(hold.kind == nil)

        // While an agent works, the session ending doesn't let the Mac sleep: no strip.
        ends = []
        center.setWork(agents: true, converting: false)
        center.turnOn(.timed(30 * 60))
        clock.advance(30 * 60)
        center.timeMayHaveJumped()
        #expect(center.session == nil)
        #expect(center.isHolding)
        #expect(ends.isEmpty)
    }

    @Test func timeUpDuringSleepEndsQuietly() {
        let center = makeCenter()
        var ends: [KeepAwakeEnd] = []
        center.onEndedByItself = { ends.append($0) }
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

    @Test func automaticEndingShowsNoStrip() {
        let center = makeCenter()
        var ends: [KeepAwakeEnd] = []
        center.onEndedByItself = { ends.append($0) }
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
        // The agent still works: automatic keeps it awake now.
        #expect(center.isHolding)
    }

    @Test func lowBatteryEndsEverythingWithAStripAndBlocksTurnOn() {
        let center = makeCenter()
        var ends: [KeepAwakeEnd] = []
        center.onEndedByItself = { ends.append($0) }
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
        #expect(ends == [.batteryLow])
    }

    @Test func lowBatteryWhileNothingHoldsShowsNoStrip() {
        let center = makeCenter()
        var ends: [KeepAwakeEnd] = []
        center.onEndedByItself = { ends.append($0) }
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
