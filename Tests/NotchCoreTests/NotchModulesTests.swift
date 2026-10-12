import AppKit
import SwiftUI
import Testing
@testable import NotchCore

/// A module with an ID, switches for "active" and "wants focus", and counters for what the notch tells it.
@MainActor
final class RankedModule: NotchModule {
    let moduleID: String
    var isActive = false
    var wantsFocus = false
    var hasExtraEar = false
    var hasEars = true
    var canPeek = true
    var acceptsDrags = false
    var opens = 0
    var closes = 0
    var switchedAway = 0
    weak var notch: NotchViewModel?

    init(_ id: String) { moduleID = id }

    func attach(to notch: NotchViewModel?) { self.notch = notch }
    func expandedView(layout: NotchLayout) -> AnyView { AnyView(EmptyView()) }
    func compactEars(layout: NotchLayout) -> CompactEars? {
        guard hasEars else { return nil }
        return CompactEars(main: AnyView(EmptyView()), extra: hasExtraEar ? AnyView(EmptyView()) : nil)
    }
    func peekView(layout: NotchLayout) -> AnyView? { canPeek ? AnyView(EmptyView()) : nil }
    func notchDidOpen() { opens += 1 }
    func notchDidClose() { closes += 1 }
    func userSwitchedAway() { switchedAway += 1 }
    func canAcceptDrag(_ pasteboard: NSPasteboard) -> Bool { acceptsDrags }
}

@MainActor
struct NotchModulesTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    func makeModel(state: NotchState = .closed) -> (NotchViewModel, RankedModule, RankedModule) {
        let model = NotchViewModel(
            layout: layout,
            state: state,
            behavior: NotchBehavior(openDelay: .milliseconds(10), closeDelay: .milliseconds(10)),
            pointerLocation: { CGPoint(x: 756, y: 300) },
            isMissionControlActive: { false }
        )
        let music = RankedModule("nowPlaying")
        let shelf = RankedModule("shelf")
        // Given in the "wrong" order: the arrangement ranks them.
        model.modules = [shelf, music]
        return (model, music, shelf)
    }

    // MARK: Ranking and ears

    @Test func modulesAreRankedByTheArrangement() {
        let (model, _, _) = makeModel()
        #expect(model.rankedModules.map(\.moduleID) == ["nowPlaying", "shelf"])
        #expect(model.selectedModule?.moduleID == "nowPlaying")
    }

    @Test func aLoneActiveModuleFillsBothEars() {
        let (model, music, _) = makeModel()
        music.isActive = true
        music.hasExtraEar = true
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "nowPlaying.main")
        #expect(ears.right?.id == "nowPlaying.extra")
    }

    @Test func twoActiveModulesShareTheEarsByRank() {
        let (model, music, shelf) = makeModel()
        music.isActive = true
        music.hasExtraEar = true
        shelf.isActive = true
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "nowPlaying.main")
        #expect(ears.right?.id == "shelf.main")
        model.arrangement.swapsEarSides = true
        let swapped = model.ears(layout: layout)
        #expect(swapped.left?.id == "shelf.main")
        #expect(swapped.right?.id == "nowPlaying.main")
    }

    @Test func reorderingChangesWhoGetsTheLeftEar() {
        let (model, music, shelf) = makeModel()
        music.isActive = true
        shelf.isActive = true
        model.arrangement.move("shelf", to: 0)
        #expect(model.ears(layout: layout).left?.id == "shelf.main")
    }

    @Test func withNothingActiveTheCurrentModuleShows() {
        let (model, _, _) = makeModel()
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "nowPlaying.main")
        #expect(ears.right == nil)
    }

    @Test func aModuleWithoutEarsLeavesItsSideToTheNext() {
        let (model, music, shelf) = makeModel()
        let third = RankedModule("third")
        model.modules.append(third)
        music.isActive = true
        music.hasEars = false
        shelf.isActive = true
        third.isActive = true
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "shelf.main")
        #expect(ears.right?.id == "third.main")
    }

    @Test func anActiveModuleMakesTheNotchRestCompact() {
        let (model, music, _) = makeModel()
        #expect(model.restingState == .closed)
        music.isActive = true
        model.activityChanged()
        #expect(model.restingState == .compact)
        #expect(model.state == .compact)
        music.isActive = false
        model.activityChanged()
        #expect(model.state == .closed)
    }

    // MARK: Opening and switching

    @Test func opensOnTheModuleThatWantsFocus() {
        let (model, music, shelf) = makeModel()
        model.select("shelf")
        music.wantsFocus = true
        model.open()
        #expect(model.selectedModule === music)
        #expect(music.opens == 1)
        #expect(shelf.opens == 0)
    }

    @Test func otherwiseOpensWhereTheUserWasLast() {
        let (model, _, shelf) = makeModel()
        model.select("shelf")
        model.open()
        #expect(model.selectedModule === shelf)
    }

    @Test func switchingTellsBothModules() {
        let (model, music, shelf) = makeModel()
        model.open()
        model.select("shelf")
        #expect(music.closes == 1)
        #expect(music.switchedAway == 1)
        #expect(shelf.opens == 1)
        #expect(model.switchedForward)
        model.select("nowPlaying")
        #expect(!model.switchedForward)
        #expect(shelf.closes == 1)
        #expect(music.opens == 2)
    }

    @Test func closingTellsOnlyTheShownModule() {
        let (model, music, shelf) = makeModel()
        model.open()
        model.close()
        #expect(music.closes == 1)
        #expect(shelf.closes == 0)
    }

    @Test func theMenuReplacesTheModuleAndEscLeavesIt() throws {
        let (model, music, _) = makeModel()
        model.open()
        model.toggleMenu()
        #expect(model.showsMenu)
        #expect(music.closes == 1)
        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53
        ))
        #expect(model.handleKey(escape))
        #expect(!model.showsMenu)
        #expect(model.state == .expanded)
        #expect(music.opens == 2)
    }

    @Test func removingAModuleFromUnderTheMenuShowsTheOtherOne() {
        let (model, _, shelf) = makeModel()
        model.open()
        model.toggleMenu()
        model.modules = [shelf]
        #expect(!model.showsMenu)
        #expect(model.selectedModule === shelf)
        #expect(shelf.opens == 1)
    }

    @Test func aScrollThatBeganBeforeOpeningDoesntSwitch() throws {
        let (model, _, _) = makeModel()
        let began = try #require(Self.scroll(phase: .began))
        model.handleScroll(began, at: .zero)
        model.open()
        let moved = try #require(Self.scroll(phase: .changed))
        #expect(!model.handleScroll(moved, at: .zero))
        #expect(model.selectedModule?.moduleID == "nowPlaying")
        // The same swipe started on the open notch switches.
        #expect(model.handleScroll(began, at: .zero))
        #expect(model.selectedModule?.moduleID == "shelf")
    }

    /// A trackpad scroll event that moves 60 points sideways.
    static func scroll(phase: CGScrollPhase) -> NSEvent? {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 60, wheel3: 0) else { return nil }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 60)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        return NSEvent(cgEvent: event)
    }

    @Test func picksFromTheMenuCloseIt() {
        let (model, _, shelf) = makeModel()
        model.open()
        model.toggleMenu()
        model.select("shelf")
        #expect(!model.showsMenu)
        #expect(model.selectedModule === shelf)
        #expect(shelf.opens == 1)
    }

    @Test func swipingStopsAtTheEnds() {
        let (model, _, shelf) = makeModel()
        model.open()
        model.showAdjacentModule(forward: false)
        #expect(model.selectedModule?.moduleID == "nowPlaying")
        model.showAdjacentModule(forward: true)
        #expect(model.selectedModule === shelf)
        model.showAdjacentModule(forward: true)
        #expect(model.selectedModule === shelf)
    }

    @Test func tabsShowFavoritesAndTheCurrentModule() {
        let (model, _, _) = makeModel()
        model.arrangement.favorites = ["nowPlaying"]
        #expect(model.tabModules.map(\.moduleID) == ["nowPlaying"])
        model.select("shelf")
        #expect(model.tabModules.map(\.moduleID) == ["nowPlaying", "shelf"])
        model.arrangement.navigation = .tabs
        #expect(model.tabModules.count == 2)
    }

    @Test func aDragGoesToTheModuleThatTakesIt() {
        let (model, music, shelf) = makeModel()
        shelf.acceptsDrags = true
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("NotchModulesTests"))
        #expect(model.module(accepting: pasteboard) === shelf)
        model.dragApproached(pasteboard)
        #expect(model.state == .expanded)
        #expect(model.selectedModule === shelf)
        #expect(music.opens == 0)
    }

    @Test func removingTheShownModuleShowsAnother() {
        let (model, music, shelf) = makeModel()
        model.open()
        model.modules = [shelf]
        #expect(music.notch == nil)
        #expect(music.closes == 1)
        #expect(model.selectedModule === shelf)
        #expect(shelf.opens == 1)
    }

    // MARK: Peek

    @Test func aPeekGrowsTheCompactNotchForAMoment() async throws {
        let (model, music, _) = makeModel()
        model.peek(music, for: .milliseconds(30))
        #expect(model.layout.isPeeking)
        #expect(model.state == .compact)
        #expect(model.layout.bodySize(for: .compact).height == layout.geometry.compactHeight + NotchLayout.peekStripHeight)
        try await Task.sleep(for: .milliseconds(400))
        #expect(!model.layout.isPeeking)
        #expect(model.state == .closed)
    }

    @Test func noPeekWithoutAStrip() {
        let (model, music, _) = makeModel()
        music.canPeek = false
        model.peek(music, for: .seconds(3))
        #expect(!model.layout.isPeeking)
        #expect(model.state == .closed)
    }

    @Test func removingThePeekingModuleEndsThePeek() {
        let (model, music, shelf) = makeModel()
        model.peek(music, for: .seconds(3))
        #expect(model.layout.isPeeking)
        model.modules = [shelf]
        #expect(!model.layout.isPeeking)
    }

    @Test func aNewPeekKeepsItsStripWhileTheOldOneSlidesAway() async throws {
        let (model, music, _) = makeModel()
        model.peek(music, for: .milliseconds(20))
        try await Task.sleep(for: .milliseconds(60))
        model.peek(music, for: .seconds(3))
        try await Task.sleep(for: .milliseconds(600))
        #expect(model.layout.isPeeking)
        #expect(model.peekModuleID == "nowPlaying")
    }

    @Test func noPeekWhileOpen() {
        let (model, music, _) = makeModel()
        model.open()
        model.peek(music, for: .seconds(3))
        #expect(!model.layout.isPeeking)
    }
}

@MainActor
struct ModuleArrangementTests {
    @Test func defaultsPutNowPlayingFirst() {
        let arrangement = ModuleArrangement()
        #expect(arrangement.order == ["nowPlaying", "shelf"])
        #expect(arrangement.isFavorite("shelf"))
        #expect(arrangement.navigation == .tabsAndMenu)
        #expect(!arrangement.swapsEarSides)
    }

    @Test func movesAndKeepsItInUserDefaults() throws {
        let suite = "ModuleArrangementTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let arrangement = ModuleArrangement(defaults: defaults)
        arrangement.move("shelf", to: 0)
        arrangement.toggleFavorite("nowPlaying")
        arrangement.navigation = .menu
        let again = ModuleArrangement(defaults: defaults)
        #expect(again.order == ["shelf", "nowPlaying"])
        #expect(!again.isFavorite("nowPlaying"))
        #expect(again.navigation == .menu)
    }

    @Test func newModulesJoinAtTheEnd() throws {
        let suite = "ModuleArrangementTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["shelf"], forKey: "modules.order")
        #expect(ModuleArrangement(defaults: defaults).order == ["shelf", "nowPlaying"])
    }

    @Test func moveByOneIsClamped() {
        let arrangement = ModuleArrangement()
        arrangement.move("nowPlaying", by: -1)
        #expect(arrangement.order == ["nowPlaying", "shelf"])
        arrangement.move("nowPlaying", by: 1)
        #expect(arrangement.order == ["shelf", "nowPlaying"])
        arrangement.move("nowPlaying", by: 5)
        #expect(arrangement.order == ["shelf", "nowPlaying"])
    }
}

struct NotchSwipeTrackerTests {
    @Test func aLongEnoughSidewaysSwipeCountsOnce() {
        var tracker = NotchSwipeTracker()
        var first = tracker.handle(phase: .began, deltaX: -10, deltaY: 0, isPrecise: true)
        #expect(first == nil)
        first = tracker.handle(phase: .changed, deltaX: -30, deltaY: 2, isPrecise: true)
        #expect(first == true)
        let again = tracker.handle(phase: .changed, deltaX: -60, deltaY: 0, isPrecise: true)
        #expect(again == nil)
    }

    @Test func fingersRightGoBack() {
        var tracker = NotchSwipeTracker()
        _ = tracker.handle(phase: .began, deltaX: 20, deltaY: 0, isPrecise: true)
        let result = tracker.handle(phase: .changed, deltaX: 20, deltaY: 0, isPrecise: true)
        #expect(result == false)
    }

    @Test func verticalScrollsAndMouseWheelsDontCount() {
        var tracker = NotchSwipeTracker()
        _ = tracker.handle(phase: .began, deltaX: 10, deltaY: 40, isPrecise: true)
        let vertical = tracker.handle(phase: .changed, deltaX: 30, deltaY: 40, isPrecise: true)
        #expect(vertical == nil)
        var wheel = NotchSwipeTracker()
        _ = wheel.handle(phase: .began, deltaX: 50, deltaY: 0, isPrecise: false)
        let mouse = wheel.handle(phase: .changed, deltaX: 50, deltaY: 0, isPrecise: false)
        #expect(mouse == nil)
    }

    @Test func aNewGestureCanSwitchAgain() {
        var tracker = NotchSwipeTracker()
        _ = tracker.handle(phase: .began, deltaX: -40, deltaY: 0, isPrecise: true)
        _ = tracker.handle(phase: .ended, deltaX: 0, deltaY: 0, isPrecise: true)
        _ = tracker.handle(phase: .began, deltaX: -20, deltaY: 0, isPrecise: true)
        let second = tracker.handle(phase: .changed, deltaX: -20, deltaY: 0, isPrecise: true)
        #expect(second == true)
    }

    @Test func ignoredGesturesStayIgnored() {
        var tracker = NotchSwipeTracker()
        tracker.ignoreCurrentGesture()
        let result = tracker.handle(phase: .changed, deltaX: -80, deltaY: 0, isPrecise: true)
        #expect(result == nil)
    }
}
