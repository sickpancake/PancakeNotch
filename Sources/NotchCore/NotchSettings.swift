import AppKit
import Foundation

/// User preferences shared by the notch and the companion app's settings window (M4).
public enum NotchSettings {
    static let appsHiddenInFullScreenKey = "appsHiddenInFullScreen"

    /// Bundle IDs of apps (e.g. games) that hide the notch completely while they're full screen.
    /// Empty by default; edited in Settings (ADR-0030).
    public static var appsHiddenInFullScreen: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: appsHiddenInFullScreenKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: appsHiddenInFullScreenKey) }
    }
}

/// Whether the notch hides while a full-screen app (a video, a game, a presentation) fills the built-in
/// display (ADR-0030). Hidden means nothing is drawn and hovering does nothing; the keyboard shortcut
/// still opens it.
public enum FullScreenHiding: String, CaseIterable, Sendable {
    /// Hidden while the full-screen app itself plays and the user sits still: scrolling or moving the
    /// pointer brings the notch back for a moment, like a video player's controls.
    case whileWatching
    /// Hidden whenever the built-in display shows a full-screen app.
    case always
    /// The notch works as usual in full screen.
    case never

    /// - Parameters:
    ///   - isPlaying: an app in the full-screen Space plays (not one in the background).
    ///   - isUserActive: the user scrolled or moved the pointer a moment ago.
    public func hides(isFullScreen: Bool, isPlaying: Bool, isUserActive: Bool) -> Bool {
        guard isFullScreen else { return false }
        switch self {
        case .whileWatching: return isPlaying && !isUserActive
        case .always: return true
        case .never: return false
        }
    }
}

/// Calls back when the user scrolls, moves the pointer or clicks anywhere outside this app. Global
/// mouse monitors (no permission needed); it runs only while a full-screen video hides the notch.
@MainActor
public final class UserActivityWatcher {
    public var onActivity: (() -> Void)?
    private var monitor: Any?

    public init() {}

    public var isRunning: Bool { monitor != nil }

    public func start() {
        guard monitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.onActivity?() }
        }
    }

    public func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
