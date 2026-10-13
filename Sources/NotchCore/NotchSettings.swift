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
    /// The notch works as usual in full screen.
    case never
    /// Hidden while something plays (as Now Playing reports it).
    case whilePlaying
    /// Hidden whenever the built-in display shows a full-screen app.
    case always

    public func hides(isFullScreen: Bool, isPlaying: Bool) -> Bool {
        guard isFullScreen else { return false }
        switch self {
        case .never: return false
        case .whilePlaying: return isPlaying
        case .always: return true
        }
    }
}
