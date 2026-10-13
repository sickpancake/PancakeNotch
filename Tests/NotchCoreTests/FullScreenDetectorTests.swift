import Foundation
import Testing
@testable import NotchCore

struct FullScreenDetectorTests {
    let builtIn = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    let external = "11111111-2222-3333-4444-555555555555"

    func display(_ id: String, currentType: Int, tiled: Bool = false) -> [String: Any] {
        var current: [String: Any] = ["type": currentType]
        if tiled { current["TileLayoutManager"] = [String: Any]() }
        return ["Display Identifier": id, "Current Space": current]
    }

    @Test func desktopSpaceIsNotFullScreen() {
        let spaces = [display(builtIn, currentType: 0)]
        #expect(!FullScreenDetector.isFullScreen(displaySpaces: spaces, displayUUID: builtIn))
    }

    @Test func fullScreenSpaceIsDetected() {
        let spaces = [display(builtIn, currentType: 4, tiled: true)]
        #expect(FullScreenDetector.isFullScreen(displaySpaces: spaces, displayUUID: builtIn))
    }

    @Test func onlyTheMatchingDisplayCounts() {
        let spaces = [display(builtIn, currentType: 0), display(external, currentType: 4, tiled: true)]
        #expect(!FullScreenDetector.isFullScreen(displaySpaces: spaces, displayUUID: builtIn))
    }

    @Test func sharedSpacesUseMainEntry() {
        let spaces = [display("Main", currentType: 4)]
        #expect(FullScreenDetector.isFullScreen(displaySpaces: spaces, displayUUID: builtIn))
    }

    @Test func theFullScreenAppIsNamed() {
        var spaces = [display(builtIn, currentType: 4)]
        var current = spaces[0]["Current Space"] as! [String: Any]
        current["pid"] = NSNumber(value: 812)
        spaces[0]["Current Space"] = current
        #expect(FullScreenDetector.fullScreenApps(displaySpaces: spaces, displayUUID: builtIn) == [812])
    }

    @Test func splitViewNamesBothApps() {
        var spaces = [display(builtIn, currentType: 4)]
        var current = spaces[0]["Current Space"] as! [String: Any]
        current["pid"] = NSNumber(value: 812)
        current["TileLayoutManager"] = ["TileSpaces": [["pid": NSNumber(value: 812)], ["pid": NSNumber(value: 97)]]]
        spaces[0]["Current Space"] = current
        #expect(FullScreenDetector.fullScreenApps(displaySpaces: spaces, displayUUID: builtIn) == [812, 97])
    }

    @Test func aDesktopNamesNoApps() {
        #expect(FullScreenDetector.fullScreenApps(displaySpaces: [display(builtIn, currentType: 0)], displayUUID: builtIn) == nil)
        // Full screen, but macOS didn't say whose.
        #expect(FullScreenDetector.fullScreenApps(displaySpaces: [display(builtIn, currentType: 4)], displayUUID: builtIn) == [])
    }

    @Test func unknownDataIsNotFullScreen() {
        #expect(!FullScreenDetector.isFullScreen(displaySpaces: [], displayUUID: builtIn))
        #expect(!FullScreenDetector.isFullScreen(displaySpaces: [["junk": 1]], displayUUID: builtIn))
    }
}

struct FullScreenHidingTests {
    @Test func nothingHidesOutsideFullScreen() {
        for hiding in FullScreenHiding.allCases {
            #expect(!hiding.hides(isFullScreen: false, isPlaying: true, isUserActive: false))
        }
    }

    @Test func whileWatchingHidesOnlyWhileItPlaysAndTheUserSitsStill() {
        #expect(FullScreenHiding.whileWatching.hides(isFullScreen: true, isPlaying: true, isUserActive: false))
        // Scrolling or moving the pointer brings it back.
        #expect(!FullScreenHiding.whileWatching.hides(isFullScreen: true, isPlaying: true, isUserActive: true))
        // Studying in full screen with music from another app: isPlaying is false.
        #expect(!FullScreenHiding.whileWatching.hides(isFullScreen: true, isPlaying: false, isUserActive: false))
    }

    @Test func alwaysAndNeverIgnorePlayingAndActivity() {
        #expect(FullScreenHiding.always.hides(isFullScreen: true, isPlaying: false, isUserActive: true))
        #expect(!FullScreenHiding.never.hides(isFullScreen: true, isPlaying: true, isUserActive: false))
    }
}
