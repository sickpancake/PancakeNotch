import Foundation
import Testing
import Observation
@testable import KeepAwakeCore

/// Step-by-step replays from verify-keep-awake. No IOKit assertion, real sleep, or app window.
/// Tests named finding... assert ADR-0041's intended result. They failed before the main session
/// repaired the feature, and now pass. Inline action comments describe the original Naive path;
/// current settings listeners reconcile synchronously, before any queued task can run.
@MainActor
struct KeepAwakeModelTests {
    let clock = TestClock()
    let hold = PretendPowerHold()
    let defaults: UserDefaults
    let settings: KeepAwakeSettings
    let boot = Date(timeIntervalSinceReferenceDate: 899_000_000)

    init() {
        let name = "KeepAwakeModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = KeepAwakeSettings(defaults: defaults)
    }

    func makeCenter(power: PowerState = .pluggedIn, boot: Date? = nil) -> KeepAwakeCenter {
        let clock = clock
        let boot = boot ?? self.boot
        return KeepAwakeCenter(settings: settings, defaults: defaults, holder: hold,
                               now: { clock.now }, power: { power }, bootTime: { boot })
    }

    func drainSettings() async {
        // Observation enqueues a separate main-actor Task. Let it run, without a wall-clock delay.
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func findingModuleOffReleasesPhysicalHoldInTheSetterStep() {
        let center = makeCenter()
        center.turnOn(.untilStopped)                              // TurnOn
        settings.isEnabled = false                               // ChangeModule; reaction still queued
        #expect(!center.isHolding)
        #expect(hold.kind == nil)                                 // physical assertion is still .screen
    }

    @Test func findingScreenChoiceMatchesPhysicalHoldBeforeQueuedReaction() {
        let center = makeCenter()
        center.turnOn(.untilStopped)                              // TurnOn
        settings.screen = .canTurnOff                             // ChangeScreen
        #expect(hold.kind == .system)
    }

    @Test func findingLowCutoffReleasesPhysicalHoldBeforeQueuedReaction() {
        let center = makeCenter(power: PowerState(onBattery: true, percent: 30))
        center.turnOn(.untilStopped)                              // TurnOn
        settings.batteryCutoff = 50                               // ChangeCutoff
        #expect(center.batteryLow)
        #expect(hold.kind == nil)
    }

    @Test func findingCutoffReactionEndsSessionAndReportsBatteryOnce() async {
        let center = makeCenter()
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        center.turnOn(.untilStopped)                              // TurnOn
        settings.batteryCutoff = nil                              // ChangeCutoff
        center.setPower(PowerState(onBattery: true, percent: 30))  // SetPower
        settings.batteryCutoff = 50                               // ChangeCutoff
        await drainSettings()                                    // ObserveSettings
        #expect(hold.kind == nil)
        #expect(center.session == nil)                            // retained by current update()
        #expect(ends == [.batteryLow])                            // current observer sends nothing
        center.setPower(PowerState(onBattery: true, percent: 30))  // wasLow is already true
        #expect(center.session == nil)
        center.setPower(.pluggedIn)                               // SetPower: Turn back on (default) brings it back
        #expect(center.session != nil)
        #expect(center.isHolding)
        #expect(ends == [.batteryLow, .backOn])
    }

    @Test func findingPowerCallbackBetweenCutoffWriteAndReactionStillEndsSession() {
        let center = makeCenter(power: PowerState(onBattery: true, percent: 30))
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        center.turnOn(.untilStopped)
        settings.batteryCutoff = 50
        center.setPower(PowerState(onBattery: true, percent: 30))  // SetPower before ObserveSettings
        #expect(center.session == nil)
        #expect(ends == [.batteryLow])
        center.setPower(.pluggedIn)
        #expect(center.isHolding)
        #expect(ends == [.batteryLow, .backOn])
    }

    @Test func findingModuleOffAtDeadlineDoesNotEmitTimeUp() async {
        let center = makeCenter()
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        clock.advance(60)                                         // ClockTick
        center.turnOn(.timed(120))                                // TurnOn at tick 1, end at tick 3
        settings.isEnabled = false                               // ChangeModule, reaction queued
        clock.advance(180)                                        // ClockJump to tick 4: only 60 s late
        await drainSettings()                                    // ObserveSettings / due sleeping task
        #expect(center.session == nil)
        #expect(hold.kind == nil)
        #expect(ends.isEmpty)
    }

    @Test func findingLowCutoffAtDeadlineDoesNotMisreportTimeUp() async {
        let center = makeCenter()
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        center.turnOn(.timed(1800))                               // TurnOn
        center.extend()                                          // Extend
        settings.batteryCutoff = nil                             // ChangeCutoff
        center.setPower(PowerState(onBattery: true, percent: 30))  // SetPower: cutoff disabled
        settings.batteryCutoff = 50                               // ChangeCutoff: now low
        clock.advance(3660)                                       // ClockJump, 60 s after extended end
        await drainSettings()                                    // ObserveSettings / due sleeping task
        #expect(center.session == nil)
        #expect(!ends.contains(.timeUp))
        #expect(ends == [.batteryLow])
    }

    @Test func findingDisablingAutomaticSourceReleasesPhysicalHoldImmediately() {
        let center = makeCenter()
        center.setWork(agents: true, converting: false)
        settings.whileAgentsWork = false
        #expect(!center.isHolding)
        #expect(hold.kind == nil)
    }

    @Test func findingEnablingCountedWorkCancelsExistingTail() async {
        let center = makeCenter()
        center.setWork(agents: true, converting: false)             // SetWork
        settings.whileConverting = false                          // ChangeConversionSwitch
        center.setWork(agents: false, converting: true)            // SetWork: only uncounted work left
        #expect(center.tailEnd != nil)
        settings.whileConverting = true                           // ChangeConversionSwitch: counts again
        #expect(center.workRuns)
        await drainSettings()                                     // ObserveSettings cannot repair this
        #expect(center.tailEnd == nil)
        #expect(hold.kind == .screen)
    }

    @Test func identicalWorkInputDoesNotRetriggerHoldingObservation() {
        let center = makeCenter()
        center.setWork(agents: true, converting: false)
        let changes = KeepAwakeObservationCount()
        withObservationTracking {
            _ = center.isHolding
        } onChange: {
            MainActor.assumeIsolated { changes.value += 1 }
        }
        center.setWork(agents: true, converting: false)
        #expect(changes.value == 0)
    }

    @Test func physicalHoldMatchesEverySettledSetting() async {
        let center = makeCenter()
        center.turnOn(.untilStopped)
        settings.screen = .canTurnOff
        await drainSettings()
        #expect(hold.kind == .system)
        settings.isEnabled = false
        await drainSettings()
        #expect(hold.kind == nil)
        #expect(center.session == nil)
    }

    @Test func pausedOverlappingWorkEndsWithoutTailAndNextRunHolds() {
        let center = makeCenter()
        center.setWork(agents: true, converting: false)
        center.turnOff()
        center.setWork(agents: true, converting: true)
        center.setWork(agents: false, converting: true)
        #expect(center.pausedForWork)
        #expect(hold.kind == nil)
        center.setWork(agents: false, converting: false)
        #expect(!center.pausedForWork)
        #expect(center.tailEnd == nil)
        center.setWork(agents: true, converting: false)
        #expect(hold.kind == .screen)
    }

    @Test func manualTurnOnClearsWorkPause() {
        let center = makeCenter()
        center.setWork(agents: true, converting: false)
        center.turnOff()
        center.turnOn(.timed(1800))
        #expect(!center.pausedForWork)
        clock.advance(1800)
        center.timeMayHaveJumped()
        #expect(center.session == nil)
        #expect(hold.kind == nil)
        #expect(center.pausedForWork)
    }

    @Test func tailLastsTwoMinutesRestartsAndEndsQuietly() {
        let center = makeCenter()
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        center.setWork(agents: true, converting: false)
        center.setWork(agents: false, converting: false)
        #expect(center.tailEnd == clock.now.addingTimeInterval(120))
        clock.advance(119)
        center.timeMayHaveJumped()
        #expect(hold.kind == .screen)
        center.setWork(agents: false, converting: true)
        #expect(center.tailEnd == nil)
        center.setWork(agents: false, converting: false)
        clock.advance(120)
        center.timeMayHaveJumped()
        #expect(hold.kind == nil)
        #expect(center.tailEnd == nil)
        #expect(ends.isEmpty)
    }

    @Test func disablingSourceStartsNoTailAndDisabledWorkCountsForNothing() async {
        let center = makeCenter()
        center.setWork(agents: true, converting: false)
        settings.whileAgentsWork = false
        await drainSettings()
        #expect(center.tailEnd == nil)
        #expect(hold.kind == nil)
        center.setWork(agents: false, converting: false)
        #expect(center.tailEnd == nil)
        center.setWork(agents: true, converting: false)
        #expect(hold.kind == nil)
        settings.isEnabled = false
        await drainSettings()
        center.setWork(agents: false, converting: true)
        center.setWork(agents: false, converting: false)
        #expect(hold.kind == nil)
        #expect(center.tailEnd == nil)
    }

    @Test func timeUpStopsCurrentWorkAndShowsItsStripOnce() {
        let center = makeCenter()
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        center.turnOn(.timed(1800))
        clock.advance(1800)
        center.timeMayHaveJumped()
        center.timeMayHaveJumped()                                // competing end task / wake notice
        center.setPower(.pluggedIn)
        #expect(ends == [.timeUp])
        center.setWork(agents: true, converting: false)
        center.turnOn(.timed(1800))
        clock.advance(1800)
        center.timeMayHaveJumped()
        #expect(ends == [.timeUp, .timeUp])
        #expect(hold.kind == nil)
        #expect(center.pausedForWork)
        center.setPower(.pluggedIn)
        center.timeMayHaveJumped()
        center.setWork(agents: true, converting: false)
        #expect(hold.kind == nil)
        #expect(ends == [.timeUp, .timeUp])
    }

    @Test func lateAndBoundaryTimeEndUseSixtySecondGrace() {
        let center = makeCenter()
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        center.turnOn(.timed(1800))
        clock.advance(1860)                                       // exactly one minute late is allowed
        center.timeMayHaveJumped()
        #expect(ends == [.timeUp])
        center.turnOn(.timed(1800))
        clock.advance(1861)
        center.timeMayHaveJumped()
        #expect(ends == [.timeUp])
        #expect(center.session == nil)
    }

    @Test func clockBackAndEarlyWakeLeaveDeadlineIntactThenEnd() {
        let center = makeCenter()
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        center.turnOn(.timed(1800))
        let end = center.session?.end
        clock.advance(-600)
        center.timeMayHaveJumped()
        #expect(center.session?.end == end)
        #expect(hold.kind == .screen)
        clock.advance(2399)
        center.timeMayHaveJumped()
        #expect(center.session != nil)
        clock.advance(1)
        center.timeMayHaveJumped()
        #expect(center.session == nil)
        #expect(ends == [.timeUp])
    }

    @Test func extendPastDueUsesNowAndCancelledOldDeadlineCannotEndNewSession() {
        let center = makeCenter()
        center.turnOn(.timed(1800))
        clock.advance(1801)
        center.extend()
        #expect(center.remaining(at: clock.now) == 1800)
        center.timeMayHaveJumped()
        #expect(center.isHolding)
        center.turnOff()
        center.turnOn(.untilStopped)
        clock.advance(3600)
        center.timeMayHaveJumped()
        #expect(center.session?.end == nil)
        #expect(hold.kind == .screen)
    }

    @Test func lowPowerEndsSessionAndPlugBringsItBack() {
        let center = makeCenter()
        var ends: [KeepAwakeNotice] = []
        center.onNotice = { ends.append($0) }
        center.turnOn(.untilStopped)
        center.setWork(agents: true, converting: false)
        center.setPower(PowerState(onBattery: true, percent: 20))
        #expect(center.session == nil)
        #expect(hold.kind == nil)
        center.turnOn(.untilStopped)
        #expect(center.session == nil)
        center.setPower(PowerState(onBattery: true, percent: 19))
        #expect(ends == [.batteryLow])
        center.setPower(.pluggedIn)
        #expect(center.session != nil)
        #expect(hold.kind == .screen)
        #expect(ends == [.batteryLow, .backOn])
    }

    @Test func restorePolicyMatrixMatchesBootExpiryBatteryAndModule() {
        // Reopen: each tuple is a fresh center, just as init reads power before restoredSession().
        for policy in [KeepAwakeReopen.carryOn, .carryOnAfterRestart, .startOff] {
            for sameBoot in [true, false] {
                for expired in [true, false] {
                    for low in [true, false] {
                        for enabled in [true, false] {
                            settings.reopen = policy
                            settings.isEnabled = enabled
                            let saved = KeepAwakeSession(start: clock.now.addingTimeInterval(-100),
                                end: clock.now.addingTimeInterval(expired ? -1 : 1800), boot: boot)
                            defaults.set(try! JSONEncoder().encode(saved), forKey: "keepAwake.session")
                            let center = makeCenter(power: low ? PowerState(onBattery: true, percent: 20) : .pluggedIn,
                                boot: sameBoot ? boot : boot.addingTimeInterval(5000))
                            let expected = enabled && !low && !expired &&
                                (policy == .carryOnAfterRestart || (policy == .carryOn && sameBoot))
                            #expect((center.session != nil) == expected)
                            #expect((hold.kind != nil) == expected)
                            center.turnOff()
                        }
                    }
                }
            }
        }
    }

    @Test func unknownBootDoesNotRestoreCarryOnButRestartPolicyDoes() {
        let clock = clock
        let saved = KeepAwakeSession(start: clock.now, end: nil, boot: nil)
        defaults.set(try! JSONEncoder().encode(saved), forKey: "keepAwake.session")
        let center = KeepAwakeCenter(settings: settings, defaults: defaults, holder: hold,
                                    now: { clock.now }, bootTime: { nil })
        #expect(center.session == nil)
        settings.reopen = .carryOnAfterRestart
        defaults.set(try! JSONEncoder().encode(saved), forKey: "keepAwake.session")
        let afterRestart = KeepAwakeCenter(settings: settings, defaults: defaults, holder: hold,
                                          now: { clock.now }, bootTime: { nil })
        #expect(afterRestart.session != nil)
        afterRestart.turnOff()
    }
}

@MainActor
private final class KeepAwakeObservationCount { var value = 0 }
