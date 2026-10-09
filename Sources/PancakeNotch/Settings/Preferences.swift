import Foundation
import NotchCore
import Observation

/// User preferences, stored in `UserDefaults` and observed by the settings window and the app.
@MainActor
@Observable
final class Preferences {
    private let defaults: UserDefaults

    /// The notch's on/off switch. Off hides the notch; the app keeps running.
    var notchEnabled: Bool {
        didSet { defaults.set(notchEnabled, forKey: Keys.notchEnabled) }
    }

    var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    /// Milliseconds the pointer rests on the notch before it opens.
    var openDelayMilliseconds: Double {
        didSet { defaults.set(openDelayMilliseconds, forKey: Keys.openDelay) }
    }

    /// Milliseconds after the pointer leaves before the notch closes.
    var closeDelayMilliseconds: Double {
        didSet { defaults.set(closeDelayMilliseconds, forKey: Keys.closeDelay) }
    }

    var hapticOnOpen: Bool {
        didSet { defaults.set(hapticOnOpen, forKey: Keys.hapticOnOpen) }
    }

    var notchBehavior: NotchBehavior {
        NotchBehavior(
            openDelay: .milliseconds(Int(openDelayMilliseconds)),
            closeDelay: .milliseconds(Int(closeDelayMilliseconds)),
            hapticOnOpen: hapticOnOpen
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.notchEnabled: true,
            Keys.showMenuBarIcon: true,
            Keys.openDelay: 150.0,
            Keys.closeDelay: 300.0,
            Keys.hapticOnOpen: false,
        ])
        notchEnabled = defaults.bool(forKey: Keys.notchEnabled)
        showMenuBarIcon = defaults.bool(forKey: Keys.showMenuBarIcon)
        openDelayMilliseconds = defaults.double(forKey: Keys.openDelay)
        closeDelayMilliseconds = defaults.double(forKey: Keys.closeDelay)
        hapticOnOpen = defaults.bool(forKey: Keys.hapticOnOpen)
    }

    private enum Keys {
        static let notchEnabled = "notchEnabled"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let openDelay = "openDelayMilliseconds"
        static let closeDelay = "closeDelayMilliseconds"
        static let hapticOnOpen = "hapticOnOpen"
    }
}
