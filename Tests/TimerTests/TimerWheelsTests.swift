import AppKit
import Foundation
import NotchCore
import SwiftUI
import Testing
@testable import ModuleTimer
@testable import TimerCore

/// Each bad path TimerWheels.tla found in the first design, replayed on the real code, one step per
/// model action. The comment names the rule; the steps are the path.
@MainActor
struct TimerWheelsTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    final class OtherModule: NotchModule {
        let moduleID = "nowPlaying"
        var isActive = false
        func attach(to notch: NotchViewModel?) {}
        func expandedView(layout: NotchLayout) -> AnyView { AnyView(EmptyView()) }
        func compactEars(layout: NotchLayout) -> CompactEars? { nil }
    }

    /// The notch open on the Timer page with no timer: the wheels on screen.
    func makeModule(seconds: TimeInterval = 31 * 60 + 3) -> (TimerModule, NotchViewModel) {
        let center = TimerCenter()
        center.customSeconds = seconds
        let settings = TimerSettings(defaults: scratchDefaults())
        settings.sound = ""
        let module = TimerModule(center: center, settings: settings)
        let notch = NotchViewModel(layout: layout, state: .closed, pointerLocation: { CGPoint(x: 5, y: 5) }, isMissionControlActive: { false })
        notch.modules = [OtherModule(), module]
        notch.open(focusing: "timer")
        return (module, notch)
    }

    func type(_ characters: String, into module: TimerModule) {
        for character in characters {
            let text = String(character)
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                         characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: 0)!
            _ = module.handleKey(event)
        }
    }

    /// NeighboursFollowFace: you click a wheel, you type a digit. The numbers above and below are
    /// around the typed digit, not the old value (the screenshot showed 30 and 32 around a typed 4).
    @Test func neighboursFollowATypedDigit() {
        let (module, _) = makeModule()
        module.beginEditing(.minutes)
        type("4", into: module)
        #expect(module.typedValue(for: .minutes) == "4")
        #expect(module.shownValue(for: .minutes) == 4)
        #expect(module.shownValue(for: .seconds) == 3)
    }

    /// StartLooksRight: wheels at 0:00, you click a wheel, you type a digit. Start works and looks it.
    @Test func startLooksPressableForATypedDigit() {
        let (module, _) = makeModule(seconds: 0)
        #expect(!module.canStartWheels)
        module.beginEditing(.minutes)
        type("5", into: module)
        #expect(module.canStartWheels)
        // And the other way: typing 0 over the only nonzero wheel.
        let (other, _) = makeModule(seconds: 5 * 60)
        other.beginEditing(.minutes)
        type("0", into: other)
        #expect(!other.canStartWheels)
    }

    /// TypingOnlyOnScreen: you click a wheel, a timer starts in the app window (Home's copy shares the
    /// center). The wheels are gone, so typing ends and the notch is no longer held open.
    @Test func aTimerStartedElsewhereEndsTyping() async throws {
        let (module, notch) = makeModule()
        let home = TimerModule(center: module.center, settings: module.settings, presents: false)
        module.beginEditing(.minutes)
        type("7", into: module)
        #expect(module.holdsOpen)
        home.startPreset(TimerPreset(id: UUID(), seconds: 60, name: ""))
        // Keys stop going to the gone wheels at once.
        #expect(!module.handleKey(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                    context: nil, characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 0)!))
        try await settle { module.editing == nil }
        #expect(module.editing == nil)
        #expect(!module.holdsOpen)
        #expect(notch.showsModuleBar)
    }

    /// TypingOnlyWithKeys: you click a wheel, you click another window. Typing ends and what was typed
    /// is kept.
    @Test func losingTheKeyboardEndsTyping() {
        let (module, notch) = makeModule()
        module.beginEditing(.minutes)
        type("9", into: module)
        notch.keyFocusLost()
        #expect(module.editing == nil)
        #expect(notch.showsModuleBar)
        #expect(module.wheelSeconds == 9 * 60 + 3)
    }

    /// WheelsKeepYourTime: you scroll a wheel, the pointer leaves, you hover the notch open. The wheels
    /// still show what you scrolled to.
    @Test func reopeningKeepsThePickedTime() {
        let (module, notch) = makeModule()
        module.turn(.minutes, by: 2)
        #expect(module.wheelSeconds == 33 * 60 + 3)
        notch.close()
        notch.open(focusing: "timer")
        #expect(module.wheelSeconds == 33 * 60 + 3)
        // Home's copy shows the same wheels.
        let home = TimerModule(center: module.center, settings: module.settings, presents: false)
        #expect(home.wheelSeconds == 33 * 60 + 3)
    }

    /// DigitsGoWhereYouAre: you click minutes and type a digit, then scroll hours. Typing ends, so the
    /// next digit can't land on minutes while your hand is on hours.
    @Test func turningAnotherWheelEndsTyping() {
        let (module, _) = makeModule(seconds: 0)
        module.beginEditing(.minutes)
        type("1", into: module)
        module.turn(.hours, by: 1)
        #expect(module.editing == nil)
        #expect(module.wheelSeconds == 3_600 + 60)
        module.beginEditing(.minutes)
        type("2", into: module)
        // Even the first fraction of a row moves the hand, before a whole number passes.
        module.turn(.hours, by: 0)
        #expect(module.editing == nil)
        #expect(module.wheelSeconds == 3_600 + 120)
        // Turning the wheel being typed into keeps typing there.
        module.beginEditing(.seconds)
        module.turn(.seconds, by: 1)
        #expect(module.editing == .seconds)
    }

    /// Esc cancels the digit being typed, like leaving a text field.
    @Test func escapeCancelsTheTypedDigit() {
        let (module, _) = makeModule()
        module.beginEditing(.minutes)
        type("4", into: module)
        _ = module.handleKey(key(53))
        #expect(module.editing == nil)
        #expect(module.wheelSeconds == 31 * 60 + 3)
    }

    /// A held key is one press, and ⌥ or ⌃ with a letter isn't the Timer's.
    @Test func heldAndModifiedKeysDontRepeatActions() {
        let (module, _) = makeModule()
        module.showMode(.stopwatch)
        module.center.startStopwatch()
        #expect(module.handleKey(key(37, "l")))
        #expect(module.handleKey(key(37, "l", repeat: true)))
        #expect(module.center.stopwatch.lapTotals.count == 1)
        #expect(!module.handleKey(key(37, "l", modifiers: .option)))
        #expect(module.center.stopwatch.lapTotals.count == 1)
        #expect(module.handleKey(key(49, " ", repeat: true)))
        #expect(module.center.stopwatch.isRunning)
    }

    /// Switching to the Stopwatch page is remembered for the next open with nothing running.
    @Test func thePageLookedAtIsRemembered() {
        let (module, _) = makeModule()
        module.showMode(.stopwatch)
        #expect(TimerModule.bestMode(module.center) == .stopwatch)
    }

    func key(_ code: UInt16, _ text: String = "", repeat isRepeat: Bool = false, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                         characters: text, charactersIgnoringModifiers: text, isARepeat: isRepeat, keyCode: code)!
    }

    /// StartsWhatItShows (held before, kept): Start starts the typed time.
    @Test func startStartsTheShownTime() {
        let (module, _) = makeModule(seconds: 0)
        module.beginEditing(.minutes)
        type("2", into: module)
        module.startWheels()
        #expect(abs(module.center.timer.remaining(at: module.center.now) - 2 * 60) < 1)
        #expect(module.editing == nil)
    }
}

/// The drum's movement: the wheel's value changes as the numbers pass halfway, and the drum always
/// comes to rest on a number.
struct WheelMotionTests {
    /// Runs frames until it rests; returns all the steps passed.
    func coast(_ motion: inout WheelMotion, frames: Int = 600) -> Int {
        var steps = 0
        for _ in 0..<frames where motion.isMoving { steps += motion.advance(by: 1.0 / 120) }
        return steps
    }

    @Test func followingPassesAStepAtHalfway() {
        var motion = WheelMotion()
        #expect(motion.follow(0.4) == 0)
        #expect(motion.follow(0.2) == 1)
        #expect(abs(motion.offset - -0.4) < 0.0001)
        #expect(motion.follow(0.1) == 0)
        // Back down past halfway: the wheel turns back.
        #expect(motion.follow(-0.3) == -1)
        #expect(abs(motion.offset - 0.4) < 0.0001)
    }

    @Test func releasingRestsOnTheNearestNumber() {
        var motion = WheelMotion()
        var steps = motion.follow(0.3)
        motion.release()
        steps += coast(&motion)
        #expect(steps == 0)
        #expect(motion.offset == 0)
        #expect(!motion.isMoving)

        steps = motion.follow(0.7)
        motion.release()
        steps += coast(&motion)
        #expect(steps == 1)
        #expect(motion.offset == 0)
    }

    @Test func aFlickTravelsOnWholeNumbers() {
        var motion = WheelMotion()
        var steps = motion.follow(0.2)
        motion.release(adding: 4.6)
        steps += coast(&motion)
        #expect(steps == 5)
        #expect(motion.offset == 0)
    }

    /// Each mouse-wheel click is one number, also when clicks come faster than the slide.
    @Test func clicksAddUpOneNumberEach() {
        var motion = WheelMotion()
        motion.nudge(1)
        var steps = motion.advance(by: 1.0 / 120)
        motion.nudge(1)
        motion.nudge(1)
        steps += coast(&motion)
        #expect(steps == 3)
        motion.nudge(-2)
        #expect(coast(&motion) == -2)
        #expect(motion.offset == 0)
    }

    /// The fingers catch a coasting drum: it stops coasting and follows them.
    @Test func touchingStopsTheCoast() {
        var motion = WheelMotion()
        motion.release(adding: 6)
        _ = motion.advance(by: 1.0 / 60)
        _ = motion.follow(0)
        #expect(!motion.isMoving)
    }

    /// Reduce Motion: one advance lands at once.
    @Test func landingAtOnce() {
        var motion = WheelMotion()
        motion.nudge(3)
        #expect(motion.advance(by: .infinity) == 3)
        #expect(!motion.isMoving)
        #expect(motion.offset == 0)
    }
}
