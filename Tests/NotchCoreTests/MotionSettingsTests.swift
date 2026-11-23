import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NotchCore

/// PancakeNotch's own Reduce motion switch plus the Mac's (issue #99).
@MainActor
struct MotionSettingsTests {
    /// A pretend Mac switch the tests flip, and the center the Mac would announce changes on.
    final class Mac {
        var reducesMotion = false
        let center = NotificationCenter()

        func flip(to value: Bool) {
            reducesMotion = value
            center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        }
    }

    private func freshDefaults() -> UserDefaults {
        let name = "MotionSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func settings(_ mac: Mac, defaults: UserDefaults? = nil) -> MotionSettings {
        MotionSettings(defaults: defaults ?? freshDefaults(), readMacSetting: { mac.reducesMotion }, macChanges: mac.center)
    }

    /// Counts the change announcements one settings object posts.
    private final class Announcements {
        var count = 0
        var token: NotificationToken?
    }

    private func count(_ settings: MotionSettings) -> Announcements {
        let announcements = Announcements()
        announcements.token = NotificationToken(observing: MotionSettings.didChangeNotification, from: settings) {
            announcements.count += 1
        }
        return announcements
    }

    @Test func offByDefaultSoTheAppMovesAsBefore() {
        let motion = settings(Mac())
        #expect(!motion.reduceMotionInApp)
        #expect(!motion.macReducesMotion)
        #expect(!motion.reducesMotion)
    }

    @Test func ownSwitchIsSavedAndRestored() {
        let defaults = freshDefaults()
        let mac = Mac()
        settings(mac, defaults: defaults).reduceMotionInApp = true
        #expect(defaults.bool(forKey: "reduceMotion"))
        let reopened = settings(mac, defaults: defaults)
        #expect(reopened.reduceMotionInApp)
        #expect(reopened.reducesMotion)
    }

    @Test func eitherSwitchReducesMotion() {
        let mac = Mac()
        let motion = settings(mac)
        for app in [false, true] {
            for macOn in [false, true] {
                motion.reduceMotionInApp = app
                mac.flip(to: macOn)
                #expect(motion.reducesMotion == (app || macOn))
            }
        }
    }

    /// Turning the Mac's switch off goes back to what the person chose here, not to on or off.
    @Test func macSwitchNeverOverwritesTheOwnChoice() {
        let mac = Mac()
        let motion = settings(mac)
        mac.flip(to: true)
        #expect(motion.reducesMotion)
        #expect(!motion.reduceMotionInApp)
        mac.flip(to: false)
        #expect(!motion.reducesMotion)

        motion.reduceMotionInApp = true
        mac.flip(to: true)
        mac.flip(to: false)
        #expect(motion.reducesMotion)
    }

    /// The model's NoDeadSwitch: while the Mac's switch is on, the Settings switch shows on and is
    /// locked; a click that still gets through changes nothing and keeps your own choice.
    @Test func lockedSwitchKeepsTheOwnChoice() {
        let mac = Mac()
        let motion = settings(mac)
        motion.switchClicked(toReduce: true)
        #expect(motion.reduceMotionInApp)
        mac.flip(to: true)
        motion.switchClicked(toReduce: false) // what a click on the shown-on switch asks for
        #expect(motion.reduceMotionInApp)
        #expect(motion.reducesMotion)
        mac.flip(to: false)
        #expect(motion.reducesMotion) // still your own choice
        motion.switchClicked(toReduce: false)
        #expect(!motion.reducesMotion)
    }

    @Test func readsTheMacSwitchAtLaunch() {
        let mac = Mac()
        mac.reducesMotion = true
        #expect(settings(mac).reducesMotion)
    }

    /// Models hear about a change of the combined value only, once each time.
    @Test func announcesOnlyRealChanges() {
        let mac = Mac()
        let motion = settings(mac)
        let heard = count(motion)
        motion.reduceMotionInApp = true
        #expect(heard.count == 1)
        mac.flip(to: true) // still reduced
        motion.reduceMotionInApp = false // still reduced (the Mac)
        #expect(heard.count == 1)
        mac.flip(to: false)
        #expect(heard.count == 2)
        mac.flip(to: false) // the Mac changed some other display option
        #expect(heard.count == 2)
    }

    /// The root modifier relies on SwiftUI returning the value it's handed: guard against an SDK change.
    @Test func swiftUIReadsTheValueTheRootHandsDown() {
        var environment = EnvironmentValues()
        environment._accessibilityReduceMotion = true
        #expect(environment.accessibilityReduceMotion)
        environment._accessibilityReduceMotion = false
        #expect(!environment.accessibilityReduceMotion)
    }

    @Test func notchCurvesBecomeShortFades() {
        #expect(NotchViewModel.switchAnimation(reducesMotion: true) == .easeInOut(duration: 0.15))
        #expect(NotchViewModel.tallAnimation(reducesMotion: true) == .easeInOut(duration: 0.15))
        #expect(NotchViewModel.animation(opening: true, reducesMotion: true) == .easeInOut(duration: 0.2))
        #expect(NotchViewModel.animation(opening: false, reducesMotion: true) == .easeInOut(duration: 0.2))
        #expect(NotchViewModel.switchAnimation(reducesMotion: false) == .spring(response: 0.32, dampingFraction: 0.86))
        #expect(NotchViewModel.animation(opening: true, reducesMotion: false) == .spring(response: 0.42, dampingFraction: 0.8))
    }

    // MARK: Home's page scrolling

    private func twoPageHome(_ motion: MotionSettings) -> NotchViewModel {
        let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        let model = NotchViewModel(layout: layout, motion: motion)
        model.modules = [RankedModule("timer")]
        model.home.opening = .home
        model.home.layout = HomeLayout(placements: [
            HomePlacement(kind: .clock, size: .small, slot: .init(page: 0, column: 0, row: 0)),
            HomePlacement(kind: .battery, size: .small, slot: .init(page: 1, column: 0, row: 0))
        ])
        model.open()
        return model
    }

    /// The model's chart: path "fingers hold Home between two pages → Reduce motion comes on → it goes
    /// off again". Without the reset the page stays halfway and its widgets can't be clicked.
    @Test func switchingMidScrollSettlesThePage() {
        let mac = Mac()
        let motion = settings(mac)
        let model = twoPageHome(motion)
        #expect(model.showsHome)
        model.handleHomePreciseScroll(phase: .began, deltaY: -10, deltaX: 0, time: 1)
        model.handleHomePreciseScroll(phase: .changed, deltaY: -30, deltaX: 0, time: 1.1)
        #expect(model.homeScrollPosition != nil)
        #expect(model.homeRenderedPages.count == 2)

        motion.reduceMotionInApp = true
        #expect(model.homeScrollPosition == nil)
        #expect(model.homeRenderedPages == [model.homePage])
        let page = model.homePage

        // The fingers lift with Reduce motion on: nothing is left moving.
        model.handleHomePreciseScroll(phase: .ended, deltaY: 0, deltaX: 0, time: 1.2)
        #expect(model.homeScrollPosition == nil)

        motion.reduceMotionInApp = false
        #expect(model.homeScrollPosition == nil)
        #expect(model.homeRenderedPages == [page])
        #expect(model.homeIsLive(onPage: model.homePages[page]))
    }

    /// The Mac's switch has the same effect as the app's.
    @Test func macSwitchMidScrollSettlesThePage() {
        let mac = Mac()
        let model = twoPageHome(settings(mac))
        model.handleHomePreciseScroll(phase: .began, deltaY: -10, deltaX: 0, time: 1)
        model.handleHomePreciseScroll(phase: .changed, deltaY: -30, deltaX: 0, time: 1.1)
        #expect(model.homeScrollPosition != nil)
        mac.flip(to: true)
        #expect(model.homeScrollPosition == nil)
        #expect(model.homeRenderedPages == [model.homePage])
    }

    /// A real trackpad scroll moving up by `points` (fingers on the trackpad, so no momentum).
    private func verticalScroll(_ phase: CGScrollPhase, points: Int32 = -30) -> NSEvent? {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                  wheel1: points, wheel2: 0, wheel3: 0) else { return nil }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(points))
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        return NSEvent(cgEvent: event)
    }

    /// The model's NoHomeScrollWhileReduced, through the notch's real scroll handling: with Reduce motion
    /// the fingers never drag Home between two pages; with full motion the same scroll does.
    @Test func reducedTrackpadScrollNeverDragsHome() throws {
        let mac = Mac()
        let motion = settings(mac)
        let full = twoPageHome(motion)
        full.handleScroll(try #require(verticalScroll(.began)), at: .zero)
        full.handleScroll(try #require(verticalScroll(.changed)), at: .zero)
        #expect(full.homeScrollPosition != nil) // the control: this scroll does drag Home

        mac.flip(to: true)
        let reduced = twoPageHome(motion)
        reduced.handleScroll(try #require(verticalScroll(.began)), at: .zero)
        reduced.handleScroll(try #require(verticalScroll(.changed)), at: .zero)
        #expect(reduced.homeScrollPosition == nil)
        #expect(reduced.homeRenderedPages == [reduced.homePage])
    }

    /// With Reduce motion, a page change is one cross-fade: no in-between position, one page drawn. (In
    /// tests a settle animation finishes at once, so this can't tell the arrow-key path's two branches
    /// apart; the trackpad test above can tell the scroll path's.)
    @Test func reducedPageChangesNeverScroll() {
        let mac = Mac()
        let motion = settings(mac)
        motion.reduceMotionInApp = true
        let model = twoPageHome(motion)
        model.showHomePage(1)
        #expect(model.homePage == 1)
        #expect(model.homeScrollPosition == nil)
        #expect(model.homeRenderedPages == [1])
        model.showHomePage(0)
        #expect(model.homePage == 0)
        #expect(model.homeScrollPosition == nil)
    }
}
