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

    /// Disable hover-to-open while keeping clicks, shortcuts and file drops available.
    var openOnClickOnly: Bool {
        didSet { defaults.set(openOnClickOnly, forKey: Keys.openOnClickOnly) }
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

    /// Whether the notch hides while a full-screen app fills the built-in display.
    var fullScreenHiding: FullScreenHiding {
        didSet { defaults.set(fullScreenHiding.rawValue, forKey: Keys.fullScreenHiding) }
    }

    var notchBehavior: NotchBehavior {
        NotchBehavior(
            openDelay: .milliseconds(Int(openDelayMilliseconds)),
            closeDelay: .milliseconds(Int(closeDelayMilliseconds)),
            hapticOnOpen: hapticOnOpen,
            openOnClickOnly: openOnClickOnly
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.notchEnabled: true,
            Keys.showMenuBarIcon: true,
            Keys.openOnClickOnly: false,
            Keys.openDelay: Self.defaultOpenDelay,
            Keys.closeDelay: Self.defaultCloseDelay,
            Keys.hapticOnOpen: false,
            Keys.fullScreenHiding: FullScreenHiding.whileWatching.rawValue,
        ])
        notchEnabled = defaults.bool(forKey: Keys.notchEnabled)
        showMenuBarIcon = defaults.bool(forKey: Keys.showMenuBarIcon)
        openOnClickOnly = defaults.bool(forKey: Keys.openOnClickOnly)
        openDelayMilliseconds = defaults.double(forKey: Keys.openDelay)
        closeDelayMilliseconds = defaults.double(forKey: Keys.closeDelay)
        hapticOnOpen = defaults.bool(forKey: Keys.hapticOnOpen)
        // "whilePlaying" was While watching's first name.
        let hiding = defaults.string(forKey: Keys.fullScreenHiding)
        fullScreenHiding = hiding.flatMap(FullScreenHiding.init(rawValue:)) ?? (hiding == "always" ? .always : .whileWatching)
    }

    /// The recommended hover delays, in milliseconds (the Notch page can go back to them).
    static let defaultOpenDelay = 150.0
    static let defaultCloseDelay = 300.0

    private enum Keys {
        static let notchEnabled = "notchEnabled"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let openOnClickOnly = "openOnClickOnly"
        static let openDelay = "openDelayMilliseconds"
        static let closeDelay = "closeDelayMilliseconds"
        static let hapticOnOpen = "hapticOnOpen"
        static let fullScreenHiding = "fullScreenHiding"
    }
}
