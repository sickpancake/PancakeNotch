import Foundation
import HotKey
import Observation

/// The user's open/close-notch shortcut: saved in preferences and registered system-wide.
/// Unassigned by default (ADR-0028).
@MainActor
@Observable
final class ShortcutController {
    private(set) var shortcut: HotKey?
    private(set) var errorMessage: String?

    /// Pauses the shortcut while the user records a new one, so pressing it doesn't fire.
    var isRecording = false {
        didSet { _ = register(shortcut) }
    }

    @ObservationIgnored private let hotKey: GlobalHotKey
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "toggleNotchShortcut"

    init(defaults: UserDefaults = .standard, action: @escaping @MainActor () -> Void) {
        self.defaults = defaults
        hotKey = GlobalHotKey(action: action)
        if let data = defaults.data(forKey: Self.key) {
            shortcut = try? JSONDecoder().decode(HotKey.self, from: data)
        }
        errorMessage = register(shortcut)
    }

    /// Uses `newShortcut` if it's free; otherwise keeps the old one and explains why.
    func set(_ newShortcut: HotKey?) {
        if let problem = register(newShortcut) {
            _ = register(shortcut)
            errorMessage = problem
            return
        }
        errorMessage = nil
        shortcut = newShortcut
        if let newShortcut, let data = try? JSONEncoder().encode(newShortcut) {
            defaults.set(data, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }

    /// Registers `candidate` system-wide (or nothing while recording). Returns a message for the
    /// user if it couldn't be registered.
    private func register(_ candidate: HotKey?) -> String? {
        guard let candidate, !isRecording else {
            hotKey.unregister()
            return nil
        }
        do {
            try hotKey.register(candidate)
            return nil
        } catch .alreadyTaken {
            return String(localized: "\(candidate.displayString) is already used by another app. Try a different one.")
        } catch {
            return String(localized: "Couldn't set that shortcut. Try a different one.")
        }
    }
}
