import AppKit
import CoreGraphics
import Testing
@testable import NotchCore

@MainActor
struct NotchPreviewTests {
    @Test func detachedPreviewDoesNotTick() {
        let host = NotchPreviewHost(behavior: NotchBehavior(), screenWidth: 560, arrangement: nil, acceptsDragSource: { _ in true })
        #expect(!host.model.isOnScreen)
    }

    @Test func containerReportsVisibilityWhenDetached() {
        let container = NotchContainerView(content: NSView(), contentSize: CGSize(width: 100, height: 100))
        var visible: Bool?
        container.onVisibilityChange = { visible = $0 }
        container.viewDidMoveToWindow()
        #expect(visible == false)
    }
    @Test func restingSizeFitsTheOpenPanel() {
        let size = NotchPreview.restingSize(screenWidth: 560)
        let layout = NotchPreviewHost.layout(screenWidth: 560)
        #expect(size == layout.windowFrame(for: .expanded).size)
        // The pretend screen is wide enough for the whole open panel and its shadow.
        #expect(size.width <= 560)
    }

    @Test func tallPanelNeedsMoreRoomThanResting() {
        var layout = NotchPreviewHost.layout(screenWidth: 560)
        layout.isTall = true
        #expect(layout.windowFrame(for: .expanded).height > NotchPreview.restingSize(screenWidth: 560).height)
    }

    @Test func dropPointsLandInTheBody() {
        let layout = NotchPreviewHost.layout(screenWidth: 560)
        let origin = layout.bodyOrigin(for: .expanded)
        let point = NotchDropRouter.bodyPoint(CGPoint(x: origin.x + 10, y: 20), layout: layout)
        #expect(point == CGPoint(x: 10, y: 20))
    }
}
