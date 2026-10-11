import CoreGraphics
import Testing
@testable import NotchCore

struct NotchGeometryTests {
    // 14" MacBook Pro default resolution.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func computesNotchFromAuxiliaryAreas() throws {
        let geometry = try #require(NotchGeometry(
            screenFrame: screen,
            safeAreaTop: 32,
            auxiliaryTopLeftWidth: 662,
            auxiliaryTopRightWidth: 662
        ))
        #expect(geometry.notchRect == CGRect(x: 662, y: 950, width: 188, height: 32))
        #expect(!geometry.isSimulated)
    }

    @Test func respectsScreenOrigin() throws {
        let offsetScreen = screen.offsetBy(dx: -1512, dy: 200)
        let geometry = try #require(NotchGeometry(
            screenFrame: offsetScreen,
            safeAreaTop: 32,
            auxiliaryTopLeftWidth: 662,
            auxiliaryTopRightWidth: 662
        ))
        #expect(geometry.notchRect.minX == -850)
        #expect(geometry.notchRect.maxY == offsetScreen.maxY)
    }

    /// The ears reach the menu bar's bottom, where the notch ends; the rounded safe area can stop short.
    @Test func compactHeightFollowsTheMenuBar() throws {
        func geometry(menuBar: CGFloat) throws -> NotchGeometry {
            try #require(NotchGeometry(screenFrame: screen, safeAreaTop: 32, auxiliaryTopLeftWidth: 662, auxiliaryTopRightWidth: 662, menuBarHeight: menuBar))
        }
        #expect(try geometry(menuBar: 33).compactHeight == 33)
        #expect(try geometry(menuBar: 33).notchRect.height == 32)
        // Hidden menu bar, or something unexpected: the safe area.
        #expect(try geometry(menuBar: 0).compactHeight == 32)
        #expect(try geometry(menuBar: 60).compactHeight == 32)
        let layout = NotchLayout(geometry: try geometry(menuBar: 33))
        #expect(layout.bodySize(for: .compact).height == 33)
        #expect(layout.bodySize(for: .closed).height == 32)
    }

    @Test func noNotchWithoutSafeArea() {
        #expect(NotchGeometry(screenFrame: screen, safeAreaTop: 0, auxiliaryTopLeftWidth: 662, auxiliaryTopRightWidth: 662) == nil)
    }

    @Test func noNotchWithoutAuxiliaryAreas() {
        #expect(NotchGeometry(screenFrame: screen, safeAreaTop: 32, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil) == nil)
    }

    @Test func simulatedNotchIsCenteredAtTop() {
        let geometry = NotchGeometry.simulated(in: screen)
        #expect(geometry.isSimulated)
        #expect(geometry.notchRect.midX == screen.midX)
        #expect(geometry.notchRect.maxY == screen.maxY)
        #expect(geometry.notchRect.size == NotchGeometry.simulatedSize)
    }
}
