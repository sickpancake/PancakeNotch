import CoreGraphics
import Testing
@testable import NotchCore

@MainActor
struct NotchViewModelTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    func makeModel(state: NotchState = .closed) -> NotchViewModel {
        NotchViewModel(layout: layout, state: state, openDelay: .milliseconds(10), closeDelay: .milliseconds(10))
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
struct NotchClickTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    /// A pointer well below the notch, as when clicking the panel body.
    func makeModel(state: NotchState, pointer: CGPoint = CGPoint(x: 756, y: 850)) -> NotchViewModel {
        NotchViewModel(
            layout: layout,
            state: state,
            openDelay: .milliseconds(10),
            closeDelay: .milliseconds(10),
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
