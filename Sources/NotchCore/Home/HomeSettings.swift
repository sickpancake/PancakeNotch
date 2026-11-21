import Foundation
import Observation

/// What appears when an ordinary notch opening has no urgent module to show.
public enum HomeOpening: String, CaseIterable, Sendable {
    case lastModule, home
    public var title: String {
        switch self {
        case .lastModule: String(localized: "Last module", comment: "Notch opening choice")
        case .home: String(localized: "Home", comment: "Notch opening choice")
        }
    }
}

/// Home preferences; nil defaults keep snapshots and tests entirely in memory.
@MainActor @Observable public final class HomeSettings {
    public var layout: HomeLayout { didSet { if layout != oldValue { defaults?.set(layout.encoded(), forKey: "home.layout") } } }
    public var opening: HomeOpening { didSet { if opening != oldValue { defaults?.set(opening.rawValue, forKey: "home.opening") } } }
    public var hasSeenIntro: Bool { didSet { if hasSeenIntro != oldValue { defaults?.set(hasSeenIntro, forKey: "home.introSeen") } } }
    @ObservationIgnored private let defaults: UserDefaults?
    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        layout = HomeLayout.decode(defaults?.data(forKey: "home.layout"))
        opening = defaults?.string(forKey: "home.opening").flatMap(HomeOpening.init(rawValue:)) ?? .lastModule
        hasSeenIntro = defaults?.bool(forKey: "home.introSeen") ?? false
    }
    /// Applies successful edits and returns a refusal for the editor to explain.
    @discardableResult public func apply(_ result: Result<HomeLayout, HomeEditRefusal>) -> HomeEditRefusal? {
        switch result {
        case .success(let next): if layout != next { layout = next }; return nil
        case .failure(let reason): return reason
        }
    }
}
