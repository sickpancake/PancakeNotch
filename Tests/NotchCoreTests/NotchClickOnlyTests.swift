import CoreGraphics
import Testing
@testable import NotchCore

/// Real MainActor tasks with an injected pointer; no visible app or pointer movement.
@MainActor
struct NotchClickOnlyTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    func makeModel(clickOnly: Bool = true, state: NotchState = .closed, pointer: PointerBox) -> NotchViewModel {
        NotchViewModel(
            layout: layout, state: state,
            behavior: NotchBehavior(openDelay: .milliseconds(20), closeDelay: .milliseconds(20), openOnClickOnly: clickOnly),
            pointerLocation: { pointer.location }, isMissionControlActive: { false }
        )
    }

    @Test(arguments: [NotchState.closed, .compact])
    func hoverCannotOpenButClickCan(resting: NotchState) async throws {
        let pointer = PointerBox(CGPoint(x: 756, y: 975))
        let model = makeModel(state: resting, pointer: pointer)
        defer { model.reset() }
        model.restingState = resting
        model.hoverChanged(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state == resting)
        model.tap()
        #expect(model.state == .expanded)
        pointer.location = CGPoint(x: 5, y: 5)
        model.hoverChanged(false)
        try await settle(.milliseconds(100)) { model.state == resting }
        #expect(model.state == resting)
    }

    @Test(arguments: [false, true])
    func enablingCancelsQueuedHoverOpen(switchBack: Bool) async throws {
        let pointer = PointerBox(CGPoint(x: 756, y: 975))
        let model = makeModel(clickOnly: false, pointer: pointer)
        defer { model.reset() }
        var opens = 0
        model.onOpen = { opens += 1 }
        model.hoverChanged(true)
        model.behavior.openOnClickOnly = true
        if switchBack { model.behavior.openOnClickOnly = false }
        try await Task.sleep(for: .milliseconds(100))
        #expect(opens == 0)
        #expect(model.state == .closed)
        if switchBack {
            // A fresh entry still works after switching back to hover mode.
            model.hoverChanged(true)
            try await settle(.milliseconds(100)) { model.state == .expanded }
            #expect(model.state == .expanded)
        }
    }

    @Test func enablingPreservesQueuedClose() async throws {
        let pointer = PointerBox(CGPoint(x: 5, y: 5))
        let model = makeModel(clickOnly: false, state: .expanded, pointer: pointer)
        defer { model.reset() }
        model.hoverChanged(false)
        model.behavior.openOnClickOnly = true
        try await settle(.milliseconds(100)) { model.state == .closed }
        #expect(model.state == .closed)
    }

    @Test func reenteringCancelsCloseWithoutReopeningCompact() async throws {
        let pointer = PointerBox(CGPoint(x: 5, y: 5))
        let model = makeModel(state: .expanded, pointer: pointer)
        defer { model.reset() }
        model.hoverChanged(false)
        pointer.location = CGPoint(x: 756, y: 975)
        model.hoverChanged(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state == .expanded)
        model.tap()
        #expect(model.state == .compact)
        pointer.location = CGPoint(x: 5, y: 5)
        model.hoverChanged(false)
        pointer.location = CGPoint(x: 756, y: 975)
        model.hoverChanged(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state == .compact)
        model.tap()
        #expect(model.state == .expanded)
        model.tap()
        #expect(model.state == .closed)
    }

    @Test(arguments: ["shortcut", "drag", "accessibility"])
    func explicitOpeningStillWorks(method: String) {
        let pointer = PointerBox(CGPoint(x: 5, y: 5))
        let model = makeModel(pointer: pointer)
        defer { model.reset() }
        switch method {
        case "shortcut": model.toggle()
        case "drag": model.dragEntered()
        default: model.open()
        }
        #expect(model.state == .expanded)
    }

    @Test func holdStillDefersClosing() async throws {
        let pointer = PointerBox(CGPoint(x: 5, y: 5))
        let model = makeModel(state: .expanded, pointer: pointer)
        defer { model.reset() }
        let module = FakeModule()
        model.module = module
        module.holdsOpen = true
        model.hoverChanged(false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state == .expanded)
        module.holdsOpen = false
        model.holdReleased()
        try await settle(.milliseconds(100)) { model.state == .closed }
        #expect(model.state == .closed)
    }
}
