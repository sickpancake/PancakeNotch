import AppKit
import Foundation
import NotchCore
import SwiftUI
import Testing
@testable import ModuleTimer
@testable import TimerCore

/// A clock the tests move by hand.
@MainActor
final class TestClock {
    var now = Date(timeIntervalSinceReferenceDate: 900_000_000)
    func advance(_ seconds: TimeInterval) { now += seconds }
}

/// A throwaway defaults domain per test, so nothing touches the user's own settings.
func scratchDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "io.github.sickpancake.PancakeNotch.tests.timer.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// The timer's alarm: it rings once however many ways the end is noticed (TimerAlarm.tla).
@MainActor
struct TimerCenterTests {
    func makeCenter(defaults: UserDefaults? = nil) -> (TimerCenter, TestClock, () -> Int) {
        let clock = TestClock()
        let center = TimerCenter(defaults: defaults, now: { clock.now })
        var rings = 0
        center.onFinish = { rings += 1 }
        return (center, clock, { rings })
    }

    /// RingsOnce: the alarm, a wake and a clock change all notice the same end.
    @Test func ringsOnceHoweverItsNoticed() {
        let (center, clock, rings) = makeCenter()
        center.startTimer(seconds: 60)
        clock.advance(61)
        center.timeMayHaveJumped()
        center.timeMayHaveJumped()
        center.checkFinished()
        #expect(rings() == 1)
        #expect(center.timer.isDone)
    }

    /// NotStuckAtZero: the clock jumped forward past the end (set by hand, or network time). The sleeping
    /// alarm still has most of its wait left; the clock-change check must finish it now.
    @Test func aClockJumpFinishesIt() {
        let (center, clock, rings) = makeCenter()
        center.startTimer(seconds: 600)
        clock.advance(3_600)
        center.timeMayHaveJumped()
        #expect(rings() == 1)
    }

    /// The same, through the real notifications: the center must be listening for both.
    @Test func listensForClockChangesAndWake() {
        let (center, clock, rings) = makeCenter()
        center.start()
        defer { center.stop() }
        center.startTimer(seconds: 600)
        clock.advance(3_600)
        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        #expect(rings() == 1)
        center.startTimer(seconds: 600)
        clock.advance(3_600)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(rings() == 2)
    }

    @Test func notYetDueItKeepsRunning() {
        let (center, clock, rings) = makeCenter()
        center.startTimer(seconds: 600)
        clock.advance(30)
        center.timeMayHaveJumped()
        #expect(rings() == 0)
        #expect(center.timer.isRunning)
    }

    @Test func aPausedTimerNeverRings() {
        let (center, clock, rings) = makeCenter()
        center.startTimer(seconds: 60)
        clock.advance(10)
        center.pauseTimer()
        clock.advance(3_600)
        center.timeMayHaveJumped()
        #expect(rings() == 0)
        #expect(center.timer.remaining(at: clock.now) == 50)
    }

    /// The real alarm, on the real clock.
    @Test func theAlarmGoesOff() async throws {
        let center = TimerCenter()
        var rings = 0
        center.onFinish = { rings += 1 }
        center.startTimer(seconds: 1)
        let deadline = ContinuousClock.now + .seconds(5)
        while rings == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(rings == 1)
        #expect(center.timer.isDone)
    }

    @Test func cancelledItStaysQuiet() async throws {
        let center = TimerCenter()
        var rings = 0
        center.onFinish = { rings += 1 }
        center.startTimer(seconds: 1)
        center.cancelTimer()
        try await Task.sleep(for: .milliseconds(1_400))
        #expect(rings == 0)
        #expect(center.timer.isIdle)
    }

    @Test func carriesOnAfterQuitting() {
        let defaults = scratchDefaults()
        let (center, clock, _) = makeCenter(defaults: defaults)
        center.startTimer(seconds: 300)
        center.startStopwatch()
        clock.advance(20)
        center.lap()
        let reopened = TimerCenter(defaults: defaults, now: { clock.now + 40 })
        #expect(reopened.timer.isRunning)
        #expect(reopened.timer.remaining(at: clock.now + 40) == 240)
        #expect(reopened.stopwatch.elapsed(at: clock.now + 40) == 60)
        #expect(reopened.stopwatch.lapTotals == [20])
        #expect(reopened.lastMode == .stopwatch)
    }

    /// Ran out while the app was quit: Done when it opens, with "ended …", and no sound for it.
    @Test func endedWhileQuitItsDoneQuietly() {
        let defaults = scratchDefaults()
        let (center, clock, _) = makeCenter(defaults: defaults)
        center.startTimer(seconds: 60)
        var rings = 0
        let reopened = TimerCenter(defaults: defaults, now: { clock.now + 3_600 })
        reopened.onFinish = { rings += 1 }
        reopened.timeMayHaveJumped()
        #expect(reopened.timer.isDone)
        #expect(reopened.finishedWhileAway)
        #expect(rings == 0)
    }

    @Test func remembersTheLastCustomTime() {
        let defaults = scratchDefaults()
        let (center, _, _) = makeCenter(defaults: defaults)
        #expect(center.customSeconds == 300)
        center.startCustom(seconds: 90.4)
        #expect(center.customSeconds == 90)
        #expect(TimerCenter(defaults: defaults).customSeconds == 90)
    }

    @Test func doneItCanGoAgain() {
        let (center, clock, rings) = makeCenter()
        center.startTimer(seconds: 60)
        clock.advance(60)
        center.timeMayHaveJumped()
        center.addMinute()
        #expect(center.timer.remaining(at: clock.now) == 60)
        clock.advance(60)
        center.timeMayHaveJumped()
        center.repeatTimer()
        #expect(center.timer.remaining(at: clock.now) == 60)
        #expect(rings() == 2)
    }
}

/// The module's side of a finish: where the Done card shows, and the "Timer done" strip for a finish
/// that happened behind another module (TimerAlarm.tla, PeekOnlyIfMissed and PeekTruthful).
@MainActor
struct TimerModuleTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    final class OtherModule: NotchModule {
        let moduleID = "nowPlaying"
        var isActive = false
        func attach(to notch: NotchViewModel?) {}
        func expandedView(layout: NotchLayout) -> AnyView { AnyView(EmptyView()) }
        func compactEars(layout: NotchLayout) -> CompactEars? { nil }
    }

    func makeModule(state: NotchState = .closed, defaults: UserDefaults = scratchDefaults(),
                    _ adjust: (TimerSettings) -> Void = { _ in }) -> (TimerModule, NotchViewModel, TestClock) {
        let clock = TestClock()
        let center = TimerCenter(now: { clock.now })
        let settings = TimerSettings(defaults: defaults)
        settings.sound = ""
        settings.hapticOnDone = false
        adjust(settings)
        let module = TimerModule(center: center, settings: settings)
        let notch = NotchViewModel(layout: layout, state: state, pointerLocation: { CGPoint(x: 5, y: 5) }, isMissionControlActive: { false })
        notch.attentionCloseDelay = .seconds(30)
        notch.modules = [OtherModule(), module]
        return (module, notch, clock)
    }

    func finish(_ module: TimerModule, _ clock: TestClock) {
        module.center.startTimer(seconds: 60)
        clock.advance(60)
        module.center.timeMayHaveJumped()
    }

    @Test func anEarOnlyWhileSomethingRuns() {
        let (module, _, clock) = makeModule()
        #expect(!module.isActive)
        module.center.startStopwatch()
        #expect(module.isActive)
        module.center.stopStopwatch()
        #expect(module.isActive)
        module.center.resetStopwatch()
        #expect(!module.isActive)
        module.center.startTimer(seconds: 60)
        #expect(module.isActive)
        #expect(module.prefersSecondEar)
        _ = clock
    }

    /// With the ear off a running timer has none, but a finished one shows Done until it's stopped.
    @Test func earOffStillShowsDone() {
        let (module, _, clock) = makeModule { $0.earPlacement = .off }
        module.center.startTimer(seconds: 60)
        #expect(!module.isActive)
        #expect(!module.prefersSecondEar)
        clock.advance(60)
        module.center.timeMayHaveJumped()
        #expect(module.isActive)
        module.stopTimer()
        #expect(!module.isActive)
    }

    @Test func closedItOpensOnTheDoneCard() {
        let (module, notch, clock) = makeModule()
        finish(module, clock)
        #expect(notch.state == .expanded)
        #expect(notch.selectedModule === module)
        #expect(module.mode == .timer)
    }

    @Test func openOnTheStopwatchItTurnsToTheTimer() {
        let (module, notch, clock) = makeModule(state: .expanded)
        notch.select("timer")
        module.showMode(.stopwatch)
        finish(module, clock)
        #expect(module.mode == .timer)
        #expect(!module.peekPending)
    }

    /// Open on another module it never switches; the strip shows once the notch closes.
    @Test func behindAnotherModuleItPeeksAfterClosing() async throws {
        let (module, notch, clock) = makeModule(state: .expanded)
        notch.select("nowPlaying")
        finish(module, clock)
        #expect(notch.selectedModule?.moduleID == "nowPlaying")
        #expect(module.peekPending)
        notch.close()
        try await settle { notch.peekModuleID == "timer" }
        #expect(notch.peekModuleID == "timer")
        #expect(!module.peekPending)
    }

    /// PeekOnlyIfMissed: the user went to the Timer and saw the Done card, so no strip after.
    @Test func seenItDoesntPeek() async throws {
        let (module, notch, clock) = makeModule(state: .expanded)
        notch.select("nowPlaying")
        finish(module, clock)
        notch.select("timer")
        #expect(!module.peekPending)
        notch.close()
        try await Task.sleep(for: .milliseconds(100))
        #expect(notch.peekModuleID == nil)
    }

    /// PeekTruthful: stopped elsewhere (Home's copy) before the notch closed: no "Timer done" for a timer
    /// that isn't done any more.
    @Test func stoppedItDoesntPeek() async throws {
        let (module, notch, clock) = makeModule(state: .expanded)
        notch.select("nowPlaying")
        finish(module, clock)
        module.center.stopTimer()
        notch.close()
        try await Task.sleep(for: .milliseconds(100))
        #expect(notch.peekModuleID == nil)
    }

    /// PeekTruthful, the other way: the strip is showing when the timer is stopped in the app window. It
    /// goes at once rather than staying, empty, for its 4 seconds.
    @Test func stoppedWhileItPeeksTheStripGoes() async throws {
        let (module, notch, clock) = makeModule(state: .expanded)
        notch.select("nowPlaying")
        finish(module, clock)
        notch.close()
        try await settle { notch.peekModuleID == "timer" }
        module.center.stopTimer()
        try await settle { notch.peekModuleID == nil }
        #expect(notch.peekModuleID == nil)
        #expect(!notch.layout.isPeeking)
    }

    /// With the ear set by order or off, a finished timer still gets the second ear.
    @Test func doneAlwaysGetsAnEar() {
        let (module, _, clock) = makeModule { $0.earPlacement = .ranking }
        #expect(!module.prefersSecondEar)
        finish(module, clock)
        #expect(module.prefersSecondEar)
    }

    /// Using the Done card's buttons (VoiceOver, pointer elsewhere) keeps the alert from closing it.
    @Test func usingTheDoneCardKeepsItOpen() async throws {
        let (module, notch, clock) = makeModule()
        notch.attentionCloseDelay = .milliseconds(80)
        finish(module, clock)
        #expect(notch.state == .expanded)
        module.repeatTimer()
        try await Task.sleep(for: .milliseconds(200))
        #expect(notch.state == .expanded)
    }

    @Test func untouchedTheDoneCardCloses() async throws {
        let (module, notch, clock) = makeModule()
        notch.attentionCloseDelay = .milliseconds(80)
        finish(module, clock)
        try await settle { notch.state != .expanded }
        #expect(notch.state == .compact)
        #expect(module.isActive)
    }

    @Test func nothingTicksBehindAHiddenWindow() async throws {
        let (module, notch, _) = makeModule()
        module.center.startTimer(seconds: 60)
        try await settle { notch.state == .compact && !notch.earsAsleep }
        #expect(notch.state == .compact)
        #expect(module.earTicks)
        notch.isOnScreen = false
        #expect(!module.earTicks)
    }

    /// One typed digit counts: Start is offered for "5" minutes before typing is committed.
    @Test func aTypedDigitCountsForStart() {
        let (module, _, _) = makeModule(state: .expanded)
        module.wheelSeconds = 0
        module.beginEditing(.minutes)
        _ = module.handleKey(keyEvent("5"))
        #expect(module.wheelSeconds == 0)
        #expect(module.pendingWheelSeconds == 300)
    }

    @Test func opensOnWhatsRunning() {
        let (module, _, _) = makeModule()
        module.center.startStopwatch()
        #expect(TimerModule.bestMode(module.center) == .stopwatch)
        module.center.startTimer(seconds: 60)
        #expect(TimerModule.bestMode(module.center) == .timer)
        module.center.lastMode = .stopwatch
        #expect(TimerModule.bestMode(module.center) == .stopwatch)
    }

    @Test func typingSetsTheWheels() {
        let (module, _, _) = makeModule(state: .expanded)
        module.wheelSeconds = 0
        module.beginEditing(.minutes)
        #expect(module.holdsOpen)
        for key in ["1", "2"] { _ = module.handleKey(keyEvent(key)) }
        // Two digits fill minutes and move on to seconds.
        #expect(module.editing == .seconds)
        module.endEditing()
        #expect(module.wheelSeconds == 12 * 60)
        #expect(!module.holdsOpen)
    }

    @Test func wheelsWrapAndStayInRange() {
        #expect(TimerWheelUnit.seconds.turned(59, by: 1) == 0)
        #expect(TimerWheelUnit.minutes.turned(0, by: -1) == 59 * 60)
        #expect(TimerWheelUnit.hours.turned(23 * 3_600, by: 1) == 0)
        #expect(TimerWheelUnit.minutes.setting(0, to: 75) == 59 * 60)
    }

    func keyEvent(_ characters: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0)!
    }
}

/// Waits until `condition` holds. Returns as soon as it does; the long limit only catches a real hang
/// (a busy CI machine once took over 2 s to run an 80 ms close).
@MainActor
func settle(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(30)
    while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
}

@MainActor
struct TimerSettingsTests {
    @Test func presetsAddRemoveMoveAndReset() {
        let settings = TimerSettings(defaults: scratchDefaults())
        #expect(settings.hasDefaultPresets)
        #expect(settings.addPreset(seconds: 180, name: "  Tea  "))
        #expect(settings.presets.last?.name == "Tea")
        #expect(!settings.hasDefaultPresets)
        let tea = settings.presets.last!.id
        settings.movePreset(tea, to: 0)
        #expect(settings.presets.first?.id == tea)
        settings.removePreset(tea)
        #expect(settings.hasDefaultPresets)
        while settings.canAddPreset { settings.addPreset(seconds: 60) }
        #expect(settings.presets.count == TimerSettings.mostPresets)
        #expect(!settings.addPreset(seconds: 60))
        settings.resetPresets()
        #expect(settings.hasDefaultPresets)
    }

    @Test func savedPresetsAreCleaned() {
        let defaults = scratchDefaults()
        let settings = TimerSettings(defaults: defaults)
        settings.addPreset(seconds: 999_999)
        #expect(settings.presets.last?.seconds == CountdownTimer.longest)
        #expect(!settings.addPreset(seconds: 0.2))
        let reopened = TimerSettings(defaults: defaults)
        #expect(reopened.presets == settings.presets)
    }
}
