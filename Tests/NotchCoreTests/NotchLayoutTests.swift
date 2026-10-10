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

    @Test func tallPanelIsTallerAndFitsTheContent() {
        let layout = NotchLayout(geometry: geometry)
        let tall = NotchLayout(geometry: geometry, isTall: true)
        #expect(tall.bodySize(for: .expanded).height > layout.bodySize(for: .expanded).height)
        #expect(tall.bodySize(for: .expanded).width == layout.bodySize(for: .expanded).width)
        #expect(tall.bodySize(for: .compact) == layout.bodySize(for: .compact))
        #expect(layout.largestWindowSize.height >= tall.windowFrame(for: .expanded).height)
        #expect(tall.windowFrame(for: .expanded).height < geometry.screenFrame.height)
    }

    @Test func expandedPanelFitsNarrowScreens() {
        let narrow = NotchGeometry.simulated(in: CGRect(x: 0, y: 0, width: 500, height: 400))
        let layout = NotchLayout(geometry: narrow)
        #expect(layout.windowFrame(for: .expanded).width <= 500)
    }

    @Test(arguments: NotchState.allCases)
    func notchViewKeepsItsPlaceWhenTheWindowResizes(state: NotchState) {
        // The notch view is laid out once at the largest size; each smaller window must show the
        // same top-center slice of it, so the outline grows from the center, not the left edge.
        let layout = NotchLayout(geometry: geometry)
        let window = layout.windowFrame(for: state)
        let bounds = CGRect(origin: .zero, size: window.size)
        let content = NotchContainerView.contentFrame(in: bounds, contentSize: layout.largestWindowSize)
        let onScreen = content.offsetBy(dx: window.minX, dy: window.minY)
        let largest = layout.windowFrame(for: .expanded)
        #expect(onScreen.midX == largest.midX)
        #expect(onScreen.maxY == largest.maxY)
        #expect(content.width >= window.width && content.height >= window.height)
    }
}

@Test func expandedBodyIsTopCentredInTheContent() {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
    let origin = layout.bodyOrigin(for: .expanded)
    let body = layout.bodySize(for: .expanded)
    #expect(origin.y == 0)
    #expect(abs(origin.x * 2 + body.width - layout.largestWindowSize.width) < 0.001)
}
