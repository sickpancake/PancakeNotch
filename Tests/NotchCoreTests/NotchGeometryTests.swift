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
