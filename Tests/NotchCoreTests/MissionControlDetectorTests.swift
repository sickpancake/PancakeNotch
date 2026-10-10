import CoreGraphics
import Testing
@testable import NotchCore

/// Window lists as measured on macOS 27 (1470×956 built-in display) with Mission Control open and closed.
struct MissionControlDetectorTests {
    typealias Surface = MissionControlDetector.Surface
    let screens = [CGSize(width: 1470, height: 956)]

    @Test func nothingUpIsInactive() {
        #expect(!MissionControlDetector.isActive([], screenSizes: screens))
    }

    @Test func missionControlIsDetected() {
        let surfaces = [
            Surface(owner: "Dock", layer: 20, bounds: CGRect(x: 0, y: 0, width: 1470, height: 956)),
            Surface(owner: "WindowManager", layer: 19, bounds: CGRect(x: 0, y: 0, width: 1470, height: 956)),
            Surface(owner: "WindowManager", layer: 15, bounds: CGRect(x: 224, y: 55, width: 169, height: 129)),
            Surface(owner: "WindowManager", layer: 14, bounds: CGRect(x: 0, y: 0, width: 1470, height: 244)),
        ]
        #expect(MissionControlDetector.isActive(surfaces, screenSizes: screens))
    }

    @Test func fullScreenShieldAloneCounts() {
        let shield = Surface(owner: "WindowManager", layer: 19, bounds: CGRect(x: 0, y: 0, width: 1470, height: 956))
        #expect(MissionControlDetector.isActive([shield], screenSizes: screens))
    }

    @Test func dockAndSmallSurfacesDoNotCount() {
        let surfaces = [
            Surface(owner: "Dock", layer: 20, bounds: CGRect(x: 300, y: 880, width: 870, height: 76)),
            Surface(owner: "WindowManager", layer: 19, bounds: CGRect(x: -100, y: 0, width: 66, height: 82)),
            Surface(owner: "WindowManager", layer: -2147483624, bounds: CGRect(x: 0, y: 0, width: 1470, height: 956)),
            Surface(owner: "Window Server", layer: 24, bounds: CGRect(x: 0, y: 0, width: 1470, height: 32)),
        ]
        #expect(!MissionControlDetector.isActive(surfaces, screenSizes: screens))
    }
}
