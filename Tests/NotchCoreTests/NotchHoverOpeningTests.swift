import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import NotchCore

/// The opening race uses a fake notch hosted far off every screen, with an injected pointer.
/// Other checks need only the model. Nothing moves the real pointer or opens the app notch.
@MainActor
struct NotchHoverOpeningTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
    let inside = CGPoint(x: 756, y: 975)
    let outside = CGPoint(x: 756, y: 300)

    func makeModel(pointer: PointerBox) -> NotchViewModel {
        NotchViewModel(
            layout: layout,
            behavior: NotchBehavior(openDelay: .milliseconds(10), closeDelay: .milliseconds(10)),
            pointerLocation: { pointer.location },
            isMissionControlActive: { false }
        )
    }

    @Test(arguments: [false, true])
    func leavingDuringOpeningClosesEvenWithoutAnotherExit(ignoredExit: Bool) async throws {
        let pointer = PointerBox(inside)
        let model = makeModel(pointer: pointer)
        let panel = NotchPanel(contentRect: layout.windowFrame(for: .closed).offsetBy(dx: -30_000, dy: -30_000))
        let hosting = NSHostingView(rootView: NotchView(model: model))
        hosting.sizingOptions = []
        panel.contentView = NotchContainerView(content: hosting, contentSize: layout.largestWindowSize)
        var openingSettled = false
        model.fitWindow = { [weak panel, weak model] state in
            guard let model else { return }
            panel?.setFrame(model.layout.windowFrame(for: state).offsetBy(dx: -30_000, dy: -30_000), display: true)
            if model.state == .expanded { openingSettled = true }
        }
        panel.orderFrontRegardless()
        defer {
            model.onOpen = nil
            model.reset()
            panel.orderOut(nil)
            panel.contentView = nil
        }
        // Let SwiftUI lay out the initial closed state before starting the animation.
        try await Task.sleep(for: .milliseconds(100))
        var opens = 0
        model.onOpen = { [weak model] in
            guard let model else { return }
            opens += 1
            #expect(!openingSettled)
            #expect(model.state == .expanded)
            if ignoredExit {
                // Outside the small notch but inside its expanded target: the resize guard ignores this exit.
                pointer.location = CGPoint(x: 756, y: 900)
                #expect(!layout.outlineFrame(for: .closed).contains(pointer.location))
                #expect(layout.outlineFrame(for: .expanded).contains(pointer.location))
                model.hoverChanged(false)
            }
            // The pointer continues away with no further hover event before the animation completes.
            pointer.location = outside
        }
        model.hoverChanged(true)
        try await settle(.milliseconds(700)) { opens == 1 && model.state == .closed }
        #expect(opens == 1)
        #expect(openingSettled)
        #expect(model.state == .closed)
    }

    @Test func stayingInsideAfterHoverOpeningKeepsItOpen() async throws {
        let pointer = PointerBox(inside)
        let model = makeModel(pointer: pointer)
        model.hoverChanged(true)
        try await settle(.milliseconds(300)) { model.state == .expanded }
        #expect(model.state == .expanded)
        model.reset()
    }

    @Test(arguments: ["click", "keyboard", "drag"])
    func otherOpeningMethodsDoNotCloseForAnOutsidePointer(method: String) async throws {
        let pointer = PointerBox(outside)
        let model = makeModel(pointer: pointer)
        switch method {
        case "click": model.tap()
        case "keyboard": model.toggle()
        default: model.dragEntered()
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.state == .expanded)
        model.reset()
    }

    @Test func aModuleHoldSurvivesOpeningUntilReleased() async throws {
        let pointer = PointerBox(inside)
        let model = makeModel(pointer: pointer)
        let module = FakeModule()
        model.module = module
        module.holdsOpen = true
        model.onOpen = { pointer.location = outside }
        model.hoverChanged(true)
        try await settle(.milliseconds(300)) { model.state == .expanded }
        #expect(model.state == .expanded)
        module.holdsOpen = false
        model.holdReleased()
        try await settle(.milliseconds(100)) { model.state == .closed }
        #expect(model.state == .closed)
    }
}
