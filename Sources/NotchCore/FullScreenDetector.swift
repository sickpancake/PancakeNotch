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

/// Tells whether a full-screen app shows something that fills the display (a full-screen video, a
/// game), or a page under its own toolbar, like a browser tab while a video plays in another tab.
/// Reads window frames from the window server, which needs no permission (titles aren't read). Query it
/// when the notch is about to hide, never on a timer.
public enum FullScreenContentDetector {
    /// One on-screen window, as `CGWindowListCopyWindowInfo` describes it (top-left origin, y down).
    struct Window: Equatable {
        var owner: pid_t
        var bounds: CGRect
    }

    /// Slack for rounding: the area under the notch can end a fraction off `safeAreaInsets.top`.
    static let tolerance: CGFloat = 2

    /// - Parameters:
    ///   - apps: the apps in the full-screen Space.
    ///   - screen: the display, in the coordinates `NSScreen` uses (bottom-left origin).
    public static func fillsScreen(apps: [pid_t], screen: NSScreen) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return true }
        let windows = list.compactMap { info -> Window? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, apps.contains(pid),
                  let bounds = (info[kCGWindowBounds as String] as? [String: Any])
                      .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) })
            else { return nil }
            return Window(owner: pid, bounds: bounds)
        }
        return fillsScreen(windows, display: CGDisplayBounds(screen.displayID), topInset: screen.safeAreaInsets.top)
    }

    /// One window covers the whole display below the menu bar (or all of it). If the apps have no
    /// windows on screen, macOS didn't say enough: it counts as filling, so the notch hides as before.
    static func fillsScreen(_ windows: [Window], display: CGRect, topInset: CGFloat) -> Bool {
        guard !windows.isEmpty else { return true }
        return windows.contains { window in
            let frame = window.bounds
            return frame.minX <= display.minX + tolerance && frame.maxX >= display.maxX - tolerance
                && frame.minY <= display.minY + topInset + tolerance && frame.maxY >= display.maxY - tolerance
        }
    }
}
