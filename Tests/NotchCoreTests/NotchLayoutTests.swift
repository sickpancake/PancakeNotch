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

    @Test func closedBodyMatchesHardwareNotch() {
        let layout = NotchLayout(geometry: geometry)
        #expect(layout.bodySize(for: .closed) == geometry.notchRect.size)
        let top = layout.radii(for: .closed).top
        #expect(layout.shapeSize(for: .closed).width == geometry.notchRect.width + 2 * top)
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

    @Test func windowIsCenteredOnNotchAndTouchesScreenTop() {
        let layout = NotchLayout(geometry: geometry)
        let frame = layout.windowFrame
        #expect(frame.midX == geometry.notchRect.midX)
        #expect(frame.maxY == geometry.screenFrame.maxY)
        for state in NotchState.allCases {
            let shape = layout.shapeSize(for: state)
            #expect(shape.width <= frame.width)
            #expect(shape.height <= frame.height)
        }
    }

    @Test func expandedPanelFitsNarrowScreens() {
        let narrow = NotchGeometry.simulated(in: CGRect(x: 0, y: 0, width: 500, height: 400))
        let layout = NotchLayout(geometry: narrow)
        #expect(layout.windowFrame.width <= 500)
    }
}
