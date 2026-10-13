import AppKit
import Testing
@testable import NotchCore

/// Hiding the notch in full screen, with the keyboard shortcut still opening it (ADR-0030). The notch
/// sits far off every screen and has no modules (no key focus taken), so nothing shows while testing.
@MainActor
struct FullScreenRevealTests {
    func makeController() -> NotchWindowController {
        let controller = NotchWindowController()
        controller.update(geometry: .simulated(in: CGRect(x: -30_000, y: -30_000, width: 1512, height: 982)))
        return controller
    }

    @Test func theShortcutOpensItAndItHidesAgainOnceClosed() async throws {
        let controller = makeController()
        #expect(controller.isShowing)
        controller.isHiddenForFullScreen = true
        #expect(!controller.isShowing)

        controller.toggle()
        #expect(controller.isShowing)
        #expect(controller.model?.state == .expanded)

        controller.toggle()
        // Still there while it animates closed; hidden at the end.
        #expect(controller.isShowing)
        try await settle(.milliseconds(600)) { !controller.isShowing }
        #expect(!controller.isShowing)
        #expect(controller.model?.state == .closed)
    }

    @Test func leavingFullScreenShowsItAsUsual() {
        let controller = makeController()
        controller.isHiddenForFullScreen = true
        controller.toggle()
        controller.isHiddenForFullScreen = false
        #expect(controller.isShowing)
        controller.toggle()
        // Back in full screen: hidden again, not still opened by the earlier shortcut.
        controller.isHiddenForFullScreen = true
        #expect(!controller.isShowing)
        #expect(controller.model?.state == .closed)
    }

    @Test func anOpenNotchStaysUntilItCloses() async throws {
        let controller = makeController()
        controller.toggle()
        // The user went still while using the open notch: it isn't pulled away.
        controller.isHiddenForFullScreen = true
        #expect(controller.isShowing)
        #expect(controller.model?.state == .expanded)
        controller.toggle()
        try await settle(.milliseconds(600)) { !controller.isShowing }
        #expect(!controller.isShowing)
    }

    @Test func theHideListBlocksTheShortcutToo() {
        let controller = makeController()
        controller.isSuppressed = true
        controller.toggle()
        #expect(!controller.isShowing)
        #expect(controller.model?.state == .closed)
    }
}
