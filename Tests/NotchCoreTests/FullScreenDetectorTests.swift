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

    @Test func unknownDataIsNotFullScreen() {
        #expect(!FullScreenDetector.isFullScreen(displaySpaces: [], displayUUID: builtIn))
        #expect(!FullScreenDetector.isFullScreen(displaySpaces: [["junk": 1]], displayUUID: builtIn))
    }
}
