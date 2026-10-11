import Foundation
import Observation

/// The Shelf's options in the app window (Modules page). Stored in `UserDefaults`.
@MainActor
@Observable
public final class ShelfSettings {
    public enum DragOutMode: String, CaseIterable, Sendable {
        /// Dragging a file out always copies it; the original stays put.
        case copy
        /// Like Finder: same disk moves, another disk copies.
        case move
    }

    public enum DuplicatePolicy: String, CaseIterable, Sendable {
        case ask
        case moveToFront
        case addAgain
    }

    public enum AutoClear: String, CaseIterable, Sendable {
        case never, day, week, month

        /// Items older than this are cleared when the notch opens.
        public var maxAge: TimeInterval? {
            switch self {
            case .never: nil
            case .day: 86_400
            case .week: 7 * 86_400
            case .month: 30 * 86_400
            }
        }
    }

    public var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Keys.enabled) } }
    public var dragOutMode: DragOutMode { didSet { defaults.set(dragOutMode.rawValue, forKey: Keys.dragOutMode) } }
    public var removeAfterDragOut: Bool { didSet { defaults.set(removeAfterDragOut, forKey: Keys.removeAfterDragOut) } }
    public var duplicatePolicy: DuplicatePolicy { didSet { defaults.set(duplicatePolicy.rawValue, forKey: Keys.duplicatePolicy) } }
    public var autoClear: AutoClear { didSet { defaults.set(autoClear.rawValue, forKey: Keys.autoClear) } }
    public var showsAirDropZone: Bool { didSet { defaults.set(showsAirDropZone, forKey: Keys.airDropZone) } }
    /// The compact ear from 15 items and the short pop-up after a drop.
    public var showsInEars: Bool { didSet { defaults.set(showsInEars, forKey: Keys.showsInEars) } }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        dragOutMode = defaults.string(forKey: Keys.dragOutMode).flatMap(DragOutMode.init(rawValue:)) ?? .copy
        removeAfterDragOut = defaults.bool(forKey: Keys.removeAfterDragOut)
        duplicatePolicy = defaults.string(forKey: Keys.duplicatePolicy).flatMap(DuplicatePolicy.init(rawValue:)) ?? .ask
        autoClear = defaults.string(forKey: Keys.autoClear).flatMap(AutoClear.init(rawValue:)) ?? .never
        showsAirDropZone = defaults.object(forKey: Keys.airDropZone) as? Bool ?? true
        showsInEars = defaults.object(forKey: Keys.showsInEars) as? Bool ?? true
    }

    private enum Keys {
        static let enabled = "shelf.enabled"
        static let dragOutMode = "shelf.dragOutMode"
        static let removeAfterDragOut = "shelf.removeAfterDragOut"
        static let duplicatePolicy = "shelf.duplicatePolicy"
        static let autoClear = "shelf.autoClear"
        static let airDropZone = "shelf.airDropZone"
        static let showsInEars = "shelf.showsInEars"
    }
}
