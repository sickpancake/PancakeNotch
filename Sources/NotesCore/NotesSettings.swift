import Foundation
import Observation

/// What the Shelf does with text dropped on it while Notes is on.
public enum NotesShelfText: String, CaseIterable, Sendable {
    /// Text files (`.txt`) become notes; other text stays on the Shelf.
    case textFiles
    /// Text files and plain text (not links) become notes.
    case allText
    /// Everything stays on the Shelf.
    case off
}

/// The order of the note list. Pinned notes always come first.
public enum NotesSort: String, CaseIterable, Sendable {
    case recentlyEdited
    case newestFirst
    case oldestFirst
}

/// When the search field above the note list shows.
public enum NotesSearchField: String, CaseIterable, Sendable {
    /// Always above the list (once there are notes).
    case always
    /// Hidden until you press ⌘F or click the magnifying glass, and gone again once you leave an empty search.
    case whenSearching
}

/// What a search looks through.
public enum NotesSearchScope: String, CaseIterable, Sendable {
    /// The whole note.
    case titleAndText
    /// Only each note's first line.
    case titlesOnly
}

/// Notes' options in the app window (Modules page). Stored in `UserDefaults`.
@MainActor
@Observable
public final class NotesSettings {
    public var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Keys.enabled) } }
    public var shelfText: NotesShelfText { didSet { defaults.set(shelfText.rawValue, forKey: Keys.shelfText) } }
    public var sort: NotesSort { didSet { defaults.set(sort.rawValue, forKey: Keys.sort) } }
    /// Opening Notes from the notch starts a new, empty note right away.
    public var opensNewNote: Bool { didSet { defaults.set(opensNewNote, forKey: Keys.opensNewNote) } }
    public var searchField: NotesSearchField { didSet { defaults.set(searchField.rawValue, forKey: Keys.searchField) } }
    public var searchScope: NotesSearchScope { didSet { defaults.set(searchScope.rawValue, forKey: Keys.searchScope) } }
    /// The search stays when the notch closes, so Notes opens on the same results next time.
    public var keepsSearch: Bool { didSet { defaults.set(keepsSearch, forKey: Keys.keepsSearch) } }

    @ObservationIgnored let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        shelfText = defaults.string(forKey: Keys.shelfText).flatMap(NotesShelfText.init(rawValue:)) ?? .textFiles
        sort = defaults.string(forKey: Keys.sort).flatMap(NotesSort.init(rawValue:)) ?? .recentlyEdited
        opensNewNote = defaults.object(forKey: Keys.opensNewNote) as? Bool ?? false
        searchField = defaults.string(forKey: Keys.searchField).flatMap(NotesSearchField.init(rawValue:)) ?? .always
        searchScope = defaults.string(forKey: Keys.searchScope).flatMap(NotesSearchScope.init(rawValue:)) ?? .titleAndText
        keepsSearch = defaults.object(forKey: Keys.keepsSearch) as? Bool ?? false
        if defaults == UserDefaults.standard { Self.user = self }
    }

    /// The user's own settings (the standard defaults), once they exist: practice copies show them.
    public private(set) static weak var user: NotesSettings?

    enum Keys {
        static let enabled = "notes.enabled"
        static let shelfText = "notes.shelfText"
        static let sort = "notes.sort"
        static let opensNewNote = "notes.opensNewNote"
        static let searchField = "notes.searchField"
        static let searchScope = "notes.searchScope"
        static let keepsSearch = "notes.keepsSearch"
    }
}
