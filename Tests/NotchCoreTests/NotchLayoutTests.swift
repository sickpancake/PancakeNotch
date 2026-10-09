import CoreGraphics
import Testing
@testable import NotchCore

struct NotchLayoutTests {
    // 14" MacBook Pro default resolution.
    let geometry = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 32,
        auxiliaryTopLeftWidth: 662,
        auxiliaryTopRightWidth: 662
    )!

    @Test func closedNotchStaysInsideHardwareCutout() {
        let layout = NotchLayout(geometry: geometry)
        #expect(layout.shapeSize(for: .closed) == geometry.notchRect.size)
        #expect(layout.windowFrame(for: .closed) == geometry.notchRect)
    }

    @Test func statesGrowInOrder() {
        let layout = NotchLayout(geometry: geometry)
        let closed = layout.bodySize(for: .closed)
        let compact = layout.bodySize(for: .compact)
        let expanded = layout.bodySize(for: .expanded)
        #expect(compact.width > closed.width)
        #expect(compact.height == closed.height)
        #expect(expanded.width > compact.width)
        #expect(expanded.height > compact.height)
    }

    @Test(arguments: NotchState.allCases)
    func windowFitsStateCenteredAtScreenTop(state: NotchState) {
        let layout = NotchLayout(geometry: geometry)
        let frame = layout.windowFrame(for: state)
        let shape = layout.shapeSize(for: state)
        #expect(frame.midX == geometry.notchRect.midX)
        #expect(frame.maxY == geometry.screenFrame.maxY)
        #expect(shape.width <= frame.width)
        #expect(shape.height <= frame.height)
    }

    @Test func expandedPanelFitsNarrowScreens() {
        let narrow = NotchGeometry.simulated(in: CGRect(x: 0, y: 0, width: 500, height: 400))
        let layout = NotchLayout(geometry: narrow)
        #expect(layout.windowFrame(for: .expanded).width <= 500)
    }
}
