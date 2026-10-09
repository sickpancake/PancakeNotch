import AppKit
import Foundation

// Private SkyLight/CoreGraphics calls, read-only (ADR-0030). Same approach as MacroVisionKit (MIT)
// used by boring.notch.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> Unmanaged<CFArray>?

/// Tells whether a full-screen (or split-view) app owns the current Space on a display.
/// Query it on Space changes only, never on a timer. If the private API stops working it reports
/// `false`, so the notch simply stays visible.
public enum FullScreenDetector {
    /// Space type the window server uses for full-screen and split-view Spaces.
    static let fullScreenSpaceType = 4

    public static func isFullScreen(displayID: CGDirectDisplayID) -> Bool {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let displayUUID = CFUUIDCreateString(nil, uuid) as String?,
              let spaces = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]]
        else { return false }
        return isFullScreen(displaySpaces: spaces, displayUUID: displayUUID)
    }

    /// - Parameter displaySpaces: one entry per display, as returned by `CGSCopyManagedDisplaySpaces`.
    ///   With "Displays have separate Spaces" off there is a single entry identified as `"Main"`.
    static func isFullScreen(displaySpaces: [[String: Any]], displayUUID: String) -> Bool {
        let display = displaySpaces.first { ($0["Display Identifier"] as? String) == displayUUID }
            ?? displaySpaces.first { ($0["Display Identifier"] as? String) == "Main" }
        guard let currentSpace = display?["Current Space"] as? [String: Any] else { return false }
        return (currentSpace["type"] as? Int) == fullScreenSpaceType
            || currentSpace["TileLayoutManager"] != nil
    }
}
