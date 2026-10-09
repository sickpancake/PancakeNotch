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
