import AppKit
import Foundation

// Private SkyLight/CoreGraphics calls, read-only (ADR-0030). Same approach as MacroVisionKit (MIT)
// used by boring.notch.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> Unmanaged<CFArray>?

/// Tells whether a full-screen (or split-view) app owns the current Space on a display, and which.
/// Query it on Space changes only, never on a timer. If the private API stops working it reports
/// `false`, so the notch simply stays visible.
public enum FullScreenDetector {
    /// Space type the window server uses for full-screen and split-view Spaces.
    static let fullScreenSpaceType = 4

    public static func isFullScreen(displayID: CGDirectDisplayID) -> Bool {
        fullScreenApps(displayID: displayID) != nil
    }

    /// The process IDs of the apps filling the display's current Space (one, or two in split view), or
    /// nil when it isn't a full-screen Space. Empty if macOS didn't say which apps they are.
    public static func fullScreenApps(displayID: CGDirectDisplayID) -> [pid_t]? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let displayUUID = CFUUIDCreateString(nil, uuid) as String?,
              let spaces = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]]
        else { return nil }
        return fullScreenApps(displaySpaces: spaces, displayUUID: displayUUID)
    }

    /// - Parameter displaySpaces: one entry per display, as returned by `CGSCopyManagedDisplaySpaces`.
    ///   With "Displays have separate Spaces" off there is a single entry identified as `"Main"`.
    static func isFullScreen(displaySpaces: [[String: Any]], displayUUID: String) -> Bool {
        fullScreenApps(displaySpaces: displaySpaces, displayUUID: displayUUID) != nil
    }

    /// A full-screen Space names its app in `pid`; in split view each tile in `TileSpaces` names its own.
    static func fullScreenApps(displaySpaces: [[String: Any]], displayUUID: String) -> [pid_t]? {
        let display = displaySpaces.first { ($0["Display Identifier"] as? String) == displayUUID }
            ?? displaySpaces.first { ($0["Display Identifier"] as? String) == "Main" }
        guard let currentSpace = display?["Current Space"] as? [String: Any] else { return nil }
        let tileManager = currentSpace["TileLayoutManager"] as? [String: Any]
        guard (currentSpace["type"] as? Int) == fullScreenSpaceType || tileManager != nil else { return nil }
        let tiles = tileManager?["TileSpaces"] as? [[String: Any]] ?? []
        var apps: [pid_t] = []
        for case let pid? in ([currentSpace] + tiles).map({ ($0["pid"] as? NSNumber)?.int32Value })
        where pid > 0 && !apps.contains(pid) {
            apps.append(pid)
        }
        return apps
    }
}
