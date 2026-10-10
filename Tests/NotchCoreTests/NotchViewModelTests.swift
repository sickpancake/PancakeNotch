import CoreGraphics
import Testing
@testable import NotchCore

/// Waits `delay` (long enough on a normal machine), then up to 2 s more for `condition`, so slow CI
/// machines don't fail timing tests. Tests that expect nothing to change still wait the full `delay`.
@MainActor
func settle(_ delay: Duration, until condition: () -> Bool) async throws {
    try await Task.sleep(for: delay)
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
struct NotchViewModelTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    /// The pointer sits away from the notch, so hover exits count.
    func makeModel(state: NotchState = .closed) -> NotchViewModel {
        NotchViewModel(
            layout: layout,
            state: state,
            behavior: NotchBehavior(openDelay: .milliseconds(10), closeDelay: .milliseconds(10)),
            pointerLocation: { CGPoint(x: 5, y: 5) }
        )
    }

    @Test func hoverOpensAfterDelay() async throws {
        let model = makeModel()
        model.hoverChanged(true)
        #expect(model.state == .closed)
        try await settle(.milliseconds(300)) { model.state == .expanded }
        #expect(model.state == .expanded)
    }

    @Test func briefHoverDoesNotOpen() async throws {
        let model = makeModel()
        model.hoverChanged(true)
        model.hoverChanged(false)
        try await settle(.milliseconds(300)) { model.state == .closed }
        #expect(model.state == .closed)
    }

    @Test func leavingClosesToRestingState() async throws {
        let model = makeModel(state: .expanded)
        model.restingState = .compact
        model.hoverChanged(false)
        try await settle(.milliseconds(300)) { model.state == .compact }
        #expect(model.state == .compact)
    }

    @Test func returningCancelsClose() async throws {
        let model = makeModel(state: .expanded)
        model.hoverChanged(false)
        model.hoverChanged(true)
        try await settle(.milliseconds(300)) { model.state == .expanded }
        #expect(model.state == .expanded)
    }

    @Test func reportsEachOpenOnce() {
        let model = makeModel()
        var opens = 0
        model.onOpen = { opens += 1 }
        model.open()
        model.open()
        model.close()
        model.toggle()
        #expect(opens == 2)
    }

    @Test func clickOpensImmediately() {
        let model = makeModel()
        model.open()
        #expect(model.state == .expanded)
    }

    @Test func pinnedIgnoresHover() async throws {
        let model = makeModel(state: .expanded)
        model.isPinned = true
        model.hoverChanged(false)
        try await settle(.milliseconds(300)) { model.state == .expanded }
        #expect(model.state == .expanded)
    }
}

@MainActor
struct NotchWindowFittingTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    @Test func windowGrowsBeforeOpeningAndHidingResets() {
        let model = NotchViewModel(layout: layout)
        var fitted: [NotchState] = []
        model.fitWindow = { fitted.append($0) }
        model.open()
        #expect(fitted.first == .expanded)
        model.reset()
        #expect(model.state == .closed)
        #expect(fitted.last == .closed)
    }
}

@MainActor
struct NotchTallTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    @Test func tallOnlyWhileOpenAndClosingShrinksIt() {
        let model = NotchViewModel(layout: layout)
        var fitted: [NotchState] = []
        model.fitWindow = { fitted.append($0) }
        model.setTall(true)
        #expect(!model.layout.isTall)

        model.open()
        fitted = []
        model.setTall(true)
        #expect(model.layout.isTall)
        #expect(fitted.first == .expanded)

        model.close()
        #expect(!model.layout.isTall)
        #expect(model.state == .closed)
    }

    @Test func approachingDragOpensAndClosesAgainWhenReleasedElsewhere() async throws {
        let model = NotchViewModel(
            layout: layout,
            behavior: NotchBehavior(openDelay: .milliseconds(10), closeDelay: .milliseconds(10)),
            pointerLocation: { CGPoint(x: 100, y: 100) }
        )
        model.dragApproached()
        #expect(model.state == .expanded)
        model.approachingDragEnded()
        try await settle(.milliseconds(200)) { model.state == .closed }
        #expect(model.state == .closed)
    }
}

@MainActor
struct NotchMissionControlTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    func makeModel(missionControl: Bool) -> NotchViewModel {
        NotchViewModel(
            layout: layout,
            behavior: NotchBehavior(openDelay: .milliseconds(10), closeDelay: .milliseconds(10)),
            isMissionControlActive: { missionControl }
        )
    }

    @Test func hoverDoesNothingInMissionControl() async throws {
        let model = makeModel(missionControl: true)
        model.hoverChanged(true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.state == .closed)
    }

    @Test func clickAndDragDoNothingInMissionControl() {
        let model = makeModel(missionControl: true)
        model.tap()
        #expect(model.state == .closed)
        model.dragApproached()
        #expect(model.state == .closed)
        model.toggle()
        #expect(model.state == .closed)
    }

    @Test func opensNormallyOtherwise() {
        let model = makeModel(missionControl: false)
        model.tap()
        #expect(model.state == .expanded)
    }
}

@MainActor
struct NotchBriefCompactTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    func makeModel() -> NotchViewModel {
        NotchViewModel(layout: layout, state: .expanded, isMissionControlActive: { false })
    }

    /// After a drop the Shelf shows its count: the next close stops at Compact for a moment.
    @Test func nextCloseGoesThroughCompact() async throws {
        let model = makeModel()
        model.closeThroughCompact(for: .milliseconds(100))
        model.close()
        #expect(model.state == .compact)
        try await settle(.milliseconds(300)) { model.state == .closed }
        #expect(model.state == .closed)
        // Only once.
        model.open()
        model.close()
        #expect(model.state == .closed)
    }

    @Test func briefCompactKeepsANearlyFullRestingState() async throws {
        let model = makeModel()
        model.restingState = .compact
        model.closeThroughCompact(for: .milliseconds(50))
        model.close()
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.state == .compact)
    }

    @Test func openingEndsTheBriefMoment() async throws {
        let model = makeModel()
        model.closeThroughCompact(for: .milliseconds(100))
        model.close()
        model.open()
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.state == .expanded)
    }
}

@MainActor
struct NotchClickTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    /// A pointer well below the notch, as when clicking the panel body.
    func makeModel(state: NotchState, pointer: CGPoint = CGPoint(x: 756, y: 850)) -> NotchViewModel {
        NotchViewModel(
            layout: layout,
            state: state,
            behavior: NotchBehavior(openDelay: .milliseconds(10), closeDelay: .milliseconds(10)),
            collapseLinger: .milliseconds(10),
            pointerLocation: { pointer }
        )
    }

    @Test func clickOpensClosedNotch() {
        let model = makeModel(state: .closed)
        model.tap()
        #expect(model.state == .expanded)
    }

    @Test func clickShrinksOpenPanelToCompactThenRests() async throws {
        let model = makeModel(state: .expanded)
        model.tap()
        #expect(model.state == .compact)
        try await settle(.milliseconds(300)) { model.state == .closed }
        #expect(model.state == .closed)
    }

    @Test func compactStaysWhileItIsTheRestingState() async throws {
        let model = makeModel(state: .expanded)
        model.restingState = .compact
        model.tap()
        try await settle(.milliseconds(300)) { model.state == .compact }
        #expect(model.state == .compact)
    }

    /// The window shrinking after a click makes AppKit report "left" then "entered" while the pointer
    /// stays on the notch: that mustn't reopen it.
    @Test func resizeHoverBounceAfterClickDoesNotReopen() async throws {
        let model = makeModel(state: .expanded, pointer: CGPoint(x: 756, y: 975))
        model.tap()
        model.hoverChanged(false)
        model.hoverChanged(true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.state == .compact)
    }

    @Test func hoveringCompactAfterClickDoesNotReopen() async throws {
        let model = makeModel(state: .expanded, pointer: CGPoint(x: 756, y: 975))
        model.tap()
        model.hoverChanged(true)
        try await settle(.milliseconds(300)) { model.state == .compact }
        #expect(model.state == .compact)
        model.tap()
        #expect(model.state == .expanded)
    }
}

@MainActor
struct NotchToggleTests {
    @Test func toggleOpensAndCloses() {
        let model = NotchViewModel(layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))))
        model.toggle()
        #expect(model.state == .expanded)
        model.toggle()
        #expect(model.state == .closed)
    }
}
