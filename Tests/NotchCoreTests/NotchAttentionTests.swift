import AppKit
import SwiftUI
import Testing
@testable import NotchCore

/// A module that asks for the second ear and opens from it, like the Timer (ADR-0040).
@MainActor
final class SecondEarModule: NotchModule {
    let moduleID: String
    var isActive = true
    var prefersSecondEar = true
    var opensFromEar = true
    weak var notch: NotchViewModel?

    init(_ id: String = "timer") { moduleID = id }

    func attach(to notch: NotchViewModel?) { self.notch = notch }
    func expandedView(layout: NotchLayout) -> AnyView { AnyView(EmptyView()) }
    func compactEars(layout: NotchLayout) -> CompactEars? {
        CompactEars(main: AnyView(EmptyView()), extra: AnyView(EmptyView()), soloMain: AnyView(EmptyView()))
    }
}

@MainActor
struct SecondEarTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    func makeModel(pointer: @escaping @MainActor () -> CGPoint = { CGPoint(x: 5, y: 5) }) -> (NotchViewModel, RankedModule, SecondEarModule) {
        let model = NotchViewModel(
            layout: layout,
            behavior: NotchBehavior(openDelay: .milliseconds(10), closeDelay: .milliseconds(10)),
            pointerLocation: pointer,
            isMissionControlActive: { false }
        )
        let music = RankedModule("nowPlaying")
        music.hasExtraEar = true
        let timer = SecondEarModule()
        model.modules = [music, timer]
        return (model, music, timer)
    }

    @Test func takesTheSecondEarWhateverItsRank() {
        let (model, music, _) = makeModel()
        music.isActive = true
        model.arrangement.move("timer", to: 0)
        let ears = model.ears(layout: layout)
        // Ranked first, it still takes #2 and Now Playing keeps the left.
        #expect(ears.left?.id == "nowPlaying.main")
        #expect(ears.right?.id == "timer.main")
        model.arrangement.swapsEarSides = true
        #expect(model.ears(layout: layout).left?.id == "timer.main")
    }

    @Test func behindTwoOthersItStillGetsAnEar() {
        let (model, music, _) = makeModel()
        let shelf = RankedModule("shelf")
        shelf.isActive = true
        model.modules.append(shelf)
        music.isActive = true
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "nowPlaying.main")
        #expect(ears.right?.id == "timer.main")
    }

    @Test func aloneItsTimeIsInTheSecondEar() {
        let (model, _, _) = makeModel()
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "timer.extra")
        #expect(ears.right?.id == "timer.main")
    }

    @Test func byRankingWhenItDoesntAsk() {
        let (model, music, timer) = makeModel()
        timer.prefersSecondEar = false
        music.isActive = true
        model.arrangement.move("timer", to: 0)
        #expect(model.ears(layout: layout).left?.id == "timer.main")
    }

    /// ADR-0011: the Shelf's after-drop count borrows #2's ear, it doesn't push #1 aside.
    @Test func aBriefModuleBorrowsTheSecondEar() async throws {
        let model = NotchViewModel(layout: layout, state: .expanded, pointerLocation: { CGPoint(x: 5, y: 5) }, isMissionControlActive: { false })
        let music = RankedModule("nowPlaying")
        let shelf = RankedModule("shelf")
        model.modules = [music, shelf]
        model.arrangement.move("shelf", to: 0)
        music.isActive = true
        model.activityChanged()
        model.closeThroughCompact(for: .seconds(5), showing: shelf)
        model.close()
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "nowPlaying.main")
        #expect(ears.right?.id == "shelf.main")
    }

    @Test func hoveringItsEarOpensOnIt() async throws {
        let notch = layout.geometry.notchRect
        // Over the right ear of the compact notch.
        let (model, music, _) = makeModel { CGPoint(x: notch.maxX + 10, y: notch.maxY - 5) }
        music.isActive = true
        music.wantsFocus = true
        model.activityChanged()
        #expect(model.state == .compact)
        model.hoverChanged(true)
        try await settle(.milliseconds(60)) { model.state == .expanded }
        #expect(model.selectedModule?.moduleID == "timer")
    }

    @Test func hoveringTheOtherEarOpensAsUsual() async throws {
        let notch = layout.geometry.notchRect
        let (model, music, _) = makeModel { CGPoint(x: notch.minX - 10, y: notch.maxY - 5) }
        music.isActive = true
        music.wantsFocus = true
        model.activityChanged()
        model.hoverChanged(true)
        try await settle(.milliseconds(60)) { model.state == .expanded }
        #expect(model.selectedModule?.moduleID == "nowPlaying")
    }
}

/// A module's alert opening the notch, and the close that follows if nobody touches it. Each test replays
/// a path TLA+ found in the first design (TimerAlarm.tla).
@MainActor
struct AttentionTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    func makeModel(state: NotchState = .compact) -> (NotchViewModel, SecondEarModule) {
        let model = NotchViewModel(
            layout: layout,
            state: state,
            behavior: NotchBehavior(openDelay: .milliseconds(10), closeDelay: .milliseconds(10)),
            pointerLocation: { CGPoint(x: 5, y: 5) },
            isMissionControlActive: { false }
        )
        model.attentionCloseDelay = .milliseconds(80)
        let timer = SecondEarModule()
        model.modules = [RankedModule("nowPlaying"), timer]
        model.activityChanged()
        return (model, timer)
    }

    @Test func opensOnTheModuleThenClosesUntouched() async throws {
        let (model, timer) = makeModel()
        model.requestAttention(from: timer, revealsInFullScreen: true)
        #expect(model.state == .expanded)
        #expect(model.selectedModule?.moduleID == "timer")
        try await settle(.milliseconds(150)) { model.state != .expanded }
        #expect(model.state == .compact)
    }

    /// CloseOnlyAlertsOpen: the alert opened it, the shortcut closed it, the user opened it again. The
    /// old wait must not close the notch the user just opened.
    @Test func neverClosesANotchTheUserOpened() async throws {
        let (model, timer) = makeModel()
        model.requestAttention(from: timer, revealsInFullScreen: true)
        model.toggle()
        model.toggle()
        #expect(model.state == .expanded)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.state == .expanded)
    }

    @Test func aKeyPressCountsAsTouching() async throws {
        let (model, timer) = makeModel()
        model.requestAttention(from: timer, revealsInFullScreen: true)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                     context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        _ = model.handleKey(event)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.state == .expanded)
    }

    @Test func switchingModulesCountsAsTouching() async throws {
        let (model, timer) = makeModel()
        model.requestAttention(from: timer, revealsInFullScreen: true)
        model.select("nowPlaying")
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.state == .expanded)
    }

    @Test func alreadyOpenItDoesNothing() {
        let (model, timer) = makeModel(state: .expanded)
        model.select("nowPlaying")
        model.requestAttention(from: timer, revealsInFullScreen: true)
        #expect(model.selectedModule?.moduleID == "nowPlaying")
    }
}

/// Where the alert may open: never behind a hidden window, over full screen only when asked, and never
/// leaving the notch shown over a full-screen app when it couldn't open. The notch sits far off every
/// screen, so nothing shows while testing.
@MainActor
struct AttentionVisibilityTests {
    func makeController(missionControl: @escaping @MainActor () -> Bool = { false }) -> (NotchWindowController, SecondEarModule) {
        let controller = NotchWindowController(isMissionControlActive: missionControl)
        controller.update(geometry: .simulated(in: CGRect(x: -30_000, y: -30_000, width: 1512, height: 982)))
        let timer = SecondEarModule()
        controller.modules = [timer]
        return (controller, timer)
    }

    /// NoInvisibleOpen: switched off, the alert mustn't open the notch unseen (it would pop up open later).
    @Test func switchedOffItStaysClosed() {
        let (controller, timer) = makeController()
        controller.isEnabled = false
        controller.model?.requestAttention(from: timer, revealsInFullScreen: true)
        #expect(controller.model?.state != .expanded)
        controller.isEnabled = true
        #expect(controller.model?.state != .expanded)
    }

    @Test func overFullScreenOnlyWhenAsked() {
        let (controller, timer) = makeController()
        controller.isHiddenForFullScreen = true
        controller.model?.requestAttention(from: timer, revealsInFullScreen: false)
        #expect(!controller.isShowing)
        #expect(controller.model?.state != .expanded)
        controller.model?.requestAttention(from: timer, revealsInFullScreen: true)
        #expect(controller.isShowing)
        #expect(controller.model?.state == .expanded)
    }

    /// RevealOnlyWhileOpen: Mission Control refuses the open, so the notch hides again at once.
    @Test func missionControlLeavesItHidden() {
        let (controller, timer) = makeController(missionControl: { true })
        controller.isHiddenForFullScreen = true
        controller.model?.requestAttention(from: timer, revealsInFullScreen: true)
        #expect(!controller.isShowing)
    }
}
