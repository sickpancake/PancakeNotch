import CoreGraphics
import Testing
@testable import NotchCore

@MainActor
struct NotchViewModelTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    func makeModel(state: NotchState = .closed) -> NotchViewModel {
        NotchViewModel(layout: layout, state: state, behavior: NotchBehavior(openDelay: .milliseconds(10), closeDelay: .milliseconds(10)))
    }

    @Test func hoverOpensAfterDelay() async throws {
        let model = makeModel()
        model.hoverChanged(true)
        #expect(model.state == .closed)
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.state == .expanded)
    }

    @Test func briefHoverDoesNotOpen() async throws {
        let model = makeModel()
        model.hoverChanged(true)
        model.hoverChanged(false)
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.state == .closed)
    }

    @Test func leavingClosesToRestingState() async throws {
        let model = makeModel(state: .expanded)
        model.restingState = .compact
        model.hoverChanged(false)
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.state == .compact)
    }

    @Test func returningCancelsClose() async throws {
        let model = makeModel(state: .expanded)
        model.hoverChanged(false)
        model.hoverChanged(true)
        try await Task.sleep(for: .milliseconds(300))
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
        try await Task.sleep(for: .milliseconds(300))
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
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.state == .closed)
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
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.state == .closed)
    }

    @Test func compactStaysWhileItIsTheRestingState() async throws {
        let model = makeModel(state: .expanded)
        model.restingState = .compact
        model.tap()
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.state == .compact)
    }

    @Test func hoveringCompactAfterClickDoesNotReopen() async throws {
        let model = makeModel(state: .expanded, pointer: CGPoint(x: 756, y: 975))
        model.tap()
        model.hoverChanged(true)
        try await Task.sleep(for: .milliseconds(300))
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
