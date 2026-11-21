import ConvertKit
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

    /// What a file drag to the top of the screen does on macOS 27, where it can start Mission Control.
    public enum DragToTop: String, CaseIterable, Sendable {
        /// The pointer stops just below the menu bar over the open notch, so the drop lands on the Shelf.
        case openShelf
        /// The top of the screen is left to macOS.
        case allowMissionControl
    }

    /// Where Convert puts what it makes (ADR-0038).
    public enum ConvertDestination: String, CaseIterable, Sendable {
        /// In the original's folder (the Shelf's own storage when that can't be written to).
        case nextToOriginal
        /// In `convertFolder`.
        case folder
    }

    public var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Keys.enabled) } }
    public var dragOutMode: DragOutMode { didSet { defaults.set(dragOutMode.rawValue, forKey: Keys.dragOutMode) } }
    public var removeAfterDragOut: Bool { didSet { defaults.set(removeAfterDragOut, forKey: Keys.removeAfterDragOut) } }
    public var duplicatePolicy: DuplicatePolicy { didSet { defaults.set(duplicatePolicy.rawValue, forKey: Keys.duplicatePolicy) } }
    public var autoClear: AutoClear { didSet { defaults.set(autoClear.rawValue, forKey: Keys.autoClear) } }
    public var showsAirDropZone: Bool { didSet { defaults.set(showsAirDropZone, forKey: Keys.airDropZone) } }
    public var dragToTop: DragToTop { didSet { defaults.set(dragToTop.rawValue, forKey: Keys.dragToTop) } }
    /// The compact ear from 15 items and the short pop-up after a drop.
    public var showsInEars: Bool { didSet { defaults.set(showsInEars, forKey: Keys.showsInEars) } }
    /// The Convert drop zone and "Convert…" on items.
    public var convertEnabled: Bool { didSet { defaults.set(convertEnabled, forKey: Keys.convertEnabled) } }
    public var convertDestination: ConvertDestination {
        didSet { defaults.set(convertDestination.rawValue, forKey: Keys.convertDestination) }
    }
    /// The folder chosen for `.folder`.
    public var convertFolder: URL? { didSet { defaults.set(convertFolder?.path, forKey: Keys.convertFolder) } }
    public var convertQuality: ConvertQuality { didSet { defaults.set(convertQuality.rawValue, forKey: Keys.convertQuality) } }
    /// Experimental: Word and OpenDocument files to PDF (layout and pictures aren't kept).
    public var convertWordToPDF: Bool { didSet { defaults.set(convertWordToPDF, forKey: Keys.convertWordToPDF) } }

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
        dragToTop = defaults.string(forKey: Keys.dragToTop).flatMap(DragToTop.init(rawValue:)) ?? .openShelf
        convertEnabled = defaults.object(forKey: Keys.convertEnabled) as? Bool ?? true
        convertDestination = defaults.string(forKey: Keys.convertDestination).flatMap(ConvertDestination.init(rawValue:)) ?? .nextToOriginal
        convertFolder = defaults.string(forKey: Keys.convertFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
        convertQuality = defaults.string(forKey: Keys.convertQuality).flatMap(ConvertQuality.init(rawValue:)) ?? .balanced
        convertWordToPDF = defaults.bool(forKey: Keys.convertWordToPDF)
    }

    private enum Keys {
        static let enabled = "shelf.enabled"
        static let dragOutMode = "shelf.dragOutMode"
        static let removeAfterDragOut = "shelf.removeAfterDragOut"
        static let duplicatePolicy = "shelf.duplicatePolicy"
        static let autoClear = "shelf.autoClear"
        static let airDropZone = "shelf.airDropZone"
        static let showsInEars = "shelf.showsInEars"
        static let dragToTop = "shelf.dragToTop"
        static let convertEnabled = "shelf.convert.enabled"
        static let convertDestination = "shelf.convert.destination"
        static let convertFolder = "shelf.convert.folder"
        static let convertQuality = "shelf.convert.quality"
        static let convertWordToPDF = "shelf.convert.wordToPDF"
    }
}
