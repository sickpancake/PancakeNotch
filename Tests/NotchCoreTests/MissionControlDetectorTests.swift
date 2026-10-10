import CoreGraphics
import Testing
@testable import NotchCore

/// Window lists as measured on macOS 27 (1470×956 built-in display) with Mission Control open and closed.
struct MissionControlDetectorTests {
    typealias Surface = MissionControlDetector.Surface
    let screens = [CGSize(width: 1470, height: 956)]
    let fullScreen = CGRect(x: 0, y: 0, width: 1470, height: 956)

    @Test func nothingUpIsInactive() {
        #expect(!MissionControlDetector.isActive([], screenSizes: screens))
    }

    @Test func missionControlIsDetected() {
        let surfaces = [
            Surface(owner: .dock, layer: 20, bounds: fullScreen),
            Surface(owner: .windowManager, layer: 19, bounds: fullScreen),
            Surface(owner: .windowManager, layer: 15, bounds: CGRect(x: 224, y: 55, width: 169, height: 129)),
            Surface(owner: .windowManager, layer: 14, bounds: CGRect(x: 0, y: 0, width: 1470, height: 244)),
        ]
        #expect(MissionControlDetector.isActive(surfaces, screenSizes: screens))
    }

    /// Up to macOS 26 the Dock draws Mission Control.
    @Test func olderDockOverlayIsDetected() {
        #expect(MissionControlDetector.isActive([Surface(owner: .dock, layer: 18, bounds: fullScreen)], screenSizes: screens))
    }

    @Test func everyDayWindowsDoNotCount() {
        let surfaces = [
            // The Dock's own window can span the whole screen.
            Surface(owner: .dock, layer: 20, bounds: fullScreen),
            Surface(owner: .windowManager, layer: 19, bounds: CGRect(x: -100, y: 0, width: 66, height: 82)),
            Surface(owner: .windowManager, layer: -2147483624, bounds: fullScreen),
            Surface(owner: .other, layer: 19, bounds: fullScreen),
        ]
        #expect(!MissionControlDetector.isActive(surfaces, screenSizes: screens))
    }

    /// Tests run with Mission Control closed: the live check must agree (catches false alarms on CI's macOS).
    @Test @MainActor func liveCheckIsQuietAtRest() {
        #expect(!MissionControlDetector.isActive)
    }
}
