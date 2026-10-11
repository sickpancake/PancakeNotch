import CoreGraphics
import Testing
@testable import NotchCore

@MainActor
struct NotchPreviewTests {
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
