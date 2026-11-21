import AppKit
import Foundation
import NotchCore
import Testing
@testable import KeepAwakeCore
@testable import ModuleKeepAwake

/// The low battery, told as the user lives it (ADR-0041 amendment 2026-11-03): the real Keep Awake, the real
/// notch model and its strip, and a pretend battery the test drains and plugs in. Each test reads like the
/// steps someone would try by hand.
@MainActor
struct KeepAwakeBatteryStoryTests {
    /// A battery the test sets; Keep Awake reads it when told the power changed, as with IOKit's notification.
    final class Battery {
        var state = PowerState(onBattery: false, percent: 100)
    }

    let clock = TestClock()
    let hold = PretendPowerHold()
    let battery = Battery()
    let settings: KeepAwakeSettings
    let defaults: UserDefaults
    let center: KeepAwakeCenter
    let module: KeepAwakeModule
    let notch: NotchViewModel
    /// The strips the notch was asked to show, by module.
    let strips: StripLog

    final class StripLog {
        var shown: [String] = []
    }

    init(cutoff: Int? = 10, lowBattery: KeepAwakeLowBattery = .stop, plugIn: KeepAwakePlugIn = .turnBackOn) {
        let name = "KeepAwakeBatteryStory-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = KeepAwakeSettings(defaults: defaults)
        settings.batteryCutoff = cutoff
        settings.lowBattery = lowBattery
        settings.plugIn = plugIn
        let clock = clock, battery = battery
        center = KeepAwakeCenter(settings: settings, defaults: defaults, holder: hold, now: { clock.now },
                                 power: { battery.state }, bootTime: { Date(timeIntervalSinceReferenceDate: 899_000_000) })
        module = KeepAwakeModule(center: center)
        notch = NotchViewModel(layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))),
                               isMissionControlActive: { false })
        let strips = StripLog()
        self.strips = strips
        notch.presentPeek = { id, _, _ in strips.shown.append(id) }
        notch.modules = [module]
    }

    // MARK: Steps

    func unplug(at percent: Int) { setBattery(onBattery: true, percent) }
    func drain(to percent: Int) { setBattery(onBattery: true, percent) }
    func plugIn() { setBattery(onBattery: false, battery.state.percent) }

    private func setBattery(onBattery: Bool, _ percent: Int?) {
        battery.state = PowerState(onBattery: onBattery, percent: percent)
        center.powerChanged()
    }

    /// The strip under the notch right now: its title and detail.
    var strip: (title: String, detail: String)? {
        guard let notice = module.ended else { return nil }
        let text = KeepAwakeModule.stripText(notice, comesBack: center.stoppedForBattery && settings.plugIn == .turnBackOn)
        return (text.title, text.detail)
    }

    /// What the open Keep Awake page says.
    var page: KeepAwakeStatus { KeepAwakeStatus(center) }

    // MARK: Stop (the default), Turn back on (the default)

    @Test func stopsAtTheLevelThenComesBackWithAStripWhenPluggedIn() {
        center.turnOn(.untilStopped)
        unplug(at: 40)
        drain(to: 11)
        #expect(center.isHolding, "Above 10% it keeps going")
        #expect(strips.shown.isEmpty)

        drain(to: 10)
        #expect(!center.isHolding, "At the chosen level it stops")
        #expect(hold.kind == nil, "and lets the Mac sleep")
        #expect(strips.shown == ["keepAwake"], "with one strip")
        #expect(strip?.title == "Battery low")
        #expect(strip?.detail == "Back on when you plug in")
        #expect(page.title == "Battery low (10%)")
        #expect(page.detail == "Comes back on when you plug in")

        drain(to: 9)
        #expect(strips.shown.count == 1, "No second strip as it keeps draining")

        plugIn()
        #expect(center.isHolding, "Plugging in turns it back on")
        #expect(center.session?.end == nil, "with the same session (until you turn it off)")
        #expect(strips.shown.count == 2, "and tells you with a strip")
        #expect(strip?.title == "Keep Awake turned on")
        #expect(strip?.detail == "Your Mac is plugged in")
    }

    @Test func aTimedSessionComesBackWithTheTimeItHadLeft() {
        center.turnOn(.timed(2 * 3600))
        unplug(at: 30)
        clock.advance(20 * 60)
        drain(to: 10)
        #expect(!center.isHolding)
        clock.advance(10 * 60)
        plugIn()
        #expect(center.isHolding)
        // Two hours, 30 minutes gone (20 on, 10 stopped): the clock kept running while it was stopped.
        // 90 minutes.
        #expect(center.remaining(at: clock.now) == 5400)
    }

    @Test func aSessionThatRanOutWhileStoppedDoesNotComeBack() {
        center.turnOn(.timed(30 * 60))
        unplug(at: 20)
        drain(to: 10)
        clock.advance(40 * 60)
        center.powerChanged()
        #expect(page.detail == "Plug in to keep your Mac awake", "No promise once its time is up")
        plugIn()
        #expect(!center.isHolding)
        #expect(strips.shown.count == 1, "No 'turned on' strip")
    }

    @Test func turningItOffWhileStoppedKeepsItOffWhenPluggedIn() {
        center.turnOn(.untilStopped)
        unplug(at: 30)
        drain(to: 10)
        center.turnOff()
        #expect(page.detail == "Plug in to keep your Mac awake")
        plugIn()
        #expect(!center.isHolding)
        #expect(strips.shown.count == 1)
    }

    @Test func nothingHappensOnALowBatteryWhenItWasOff() {
        unplug(at: 30)
        drain(to: 5)
        plugIn()
        #expect(!center.isHolding)
        #expect(strips.shown.isEmpty, "No strips when it wasn't on")
    }

    // MARK: The chosen level

    @Test(arguments: [10, 20, 30, 50])
    func stopsExactlyAtTheChosenLevel(level: Int) {
        let story = KeepAwakeBatteryStoryTests(cutoff: level)
        story.center.turnOn(.untilStopped)
        story.unplug(at: 100)
        story.drain(to: level + 1)
        #expect(story.center.isHolding, "One above \(level)% it still keeps going")
        story.drain(to: level)
        #expect(!story.center.isHolding, "At \(level)% it stops")
    }

    @Test func neverStopsWhenTheLevelIsNever() {
        let story = KeepAwakeBatteryStoryTests(cutoff: nil)
        story.center.turnOn(.untilStopped)
        story.unplug(at: 30)
        story.drain(to: 1)
        #expect(story.center.isHolding)
        #expect(story.strips.shown.isEmpty)
    }

    @Test func pluggedInItNeverStopsForTheBattery() {
        center.turnOn(.untilStopped)
        battery.state = PowerState(onBattery: false, percent: 5)
        center.powerChanged()
        #expect(center.isHolding)
        #expect(strips.shown.isEmpty)
    }

    // MARK: Keep going

    @Test func keepGoingCarriesOnAndTellsYouOnce() {
        let story = KeepAwakeBatteryStoryTests(lowBattery: .keepGoing)
        story.center.turnOn(.untilStopped)
        story.unplug(at: 30)
        story.drain(to: 10)
        #expect(story.center.isHolding, "It keeps the Mac awake below the level")
        #expect(story.strips.shown == ["keepAwake"])
        #expect(story.strip?.title == "Battery low")
        #expect(story.strip?.detail == "Keep Awake keeps going")
        story.drain(to: 4)
        #expect(story.strips.shown.count == 1, "Only once")
        story.plugIn()
        #expect(story.center.isHolding)
        #expect(story.strips.shown.count == 1, "Plugging in has nothing to tell: it never stopped")
    }

    @Test func keepGoingLetsYouTurnItOnOnALowBattery() {
        let story = KeepAwakeBatteryStoryTests(lowBattery: .keepGoing)
        story.unplug(at: 5)
        #expect(story.center.canTurnOn)
        story.center.turnOn(.untilStopped)
        #expect(story.center.isHolding)
    }

    @Test func stopDoesNotLetYouTurnItOnOnALowBattery() {
        unplug(at: 5)
        #expect(!center.canTurnOn)
    }

    // MARK: Stay off

    @Test func stayOffStopsAndStaysOffWhenPluggedIn() {
        let story = KeepAwakeBatteryStoryTests(plugIn: .stayOff)
        story.center.turnOn(.untilStopped)
        story.unplug(at: 30)
        story.drain(to: 10)
        #expect(!story.center.isHolding)
        #expect(story.strip?.title == "Battery low")
        #expect(story.strip?.detail == "Your Mac can sleep again", "No promise to come back")
        #expect(story.page.detail == "Plug in to keep your Mac awake")
        story.plugIn()
        #expect(!story.center.isHolding, "Stays off")
        #expect(story.strips.shown.count == 1, "and says nothing")
        story.center.turnOn(.untilStopped)
        #expect(story.center.isHolding, "You can turn it on again yourself")
    }

    // MARK: Agents and conversions

    @Test func agentWorkStopsOnALowBatteryAndComesBackWhenPluggedIn() {
        settings.whileAgentsWork = true
        center.setWork(agents: true, converting: false)
        unplug(at: 30)
        drain(to: 10)
        #expect(!center.isHolding)
        #expect(strip?.detail == "Back on when you plug in")
        plugIn()
        #expect(center.isHolding, "The agent is still working: it keeps the Mac awake again")
        #expect(strip?.title == "Keep Awake turned on")
    }

    @Test func agentWorkThatEndedWhileStoppedDoesNotComeBack() {
        settings.whileAgentsWork = true
        center.setWork(agents: true, converting: false)
        unplug(at: 30)
        drain(to: 10)
        center.setWork(agents: false, converting: false)
        #expect(page.detail == "Plug in to keep your Mac awake")
        plugIn()
        #expect(!center.isHolding, "Nothing left to keep awake for (and no 2-minute tail)")
        #expect(strips.shown.count == 1)
    }

    // MARK: Changing a setting while it's stopped

    @Test func switchingToKeepGoingWhileStoppedTurnsItBackOnQuietly() {
        center.turnOn(.untilStopped)
        unplug(at: 30)
        drain(to: 10)
        settings.lowBattery = .keepGoing
        #expect(center.isHolding)
        #expect(strips.shown.count == 1, "You changed it yourself: no strip")
    }

    @Test func choosingALowerLevelWhileStoppedTurnsItBackOn() {
        let story = KeepAwakeBatteryStoryTests(cutoff: 20)
        story.center.turnOn(.untilStopped)
        story.unplug(at: 30)
        story.drain(to: 15)
        #expect(!story.center.isHolding)
        story.settings.batteryCutoff = 10
        #expect(story.center.isHolding, "15% is above the new 10% level")
    }

    // MARK: Quitting and reopening

    @Test func reopeningAfterAStopStillComesBackWhenPluggedIn() {
        center.turnOn(.untilStopped)
        unplug(at: 30)
        drain(to: 10)
        center.stop()
        // PancakeNotch opens again, still on the low battery.
        let battery = battery, clock = clock
        let reopened = KeepAwakeCenter(settings: KeepAwakeSettings(defaults: defaults), defaults: defaults, holder: PretendPowerHold(),
                                       now: { clock.now }, power: { battery.state },
                                       bootTime: { Date(timeIntervalSinceReferenceDate: 899_000_000) })
        #expect(!reopened.isHolding)
        #expect(reopened.stoppedForBattery)
        battery.state = PowerState(onBattery: false, percent: 10)
        reopened.powerChanged()
        #expect(reopened.isHolding)
    }
}
