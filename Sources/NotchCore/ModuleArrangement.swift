import Foundation
import Observation

/// How the open notch lets you move between modules (Notch settings).
public enum NotchNavigation: String, CaseIterable, Sendable {
    /// A Menu button, then tabs for the favorite modules (the default).
    case tabsAndMenu
    /// Tabs for every module, no Menu.
    case tabs
    /// Only the current module's name: click it for Home.
    case menu
}

/// Which side of Home the Library sits on, in the bar and for swipes (ADR-0045).
public enum LibrarySide: String, CaseIterable, Sendable {
    case left, right
}

/// The user's module order, favorites, ear sides and navigation (ADR-0010, ADR-0011, ADR-0045), edited on
/// the Modules and Notch pages and in the notch's Library. Stored in `UserDefaults`, or only in memory when there are no defaults.
@MainActor
@Observable
public final class ModuleArrangement {
    /// Module IDs by rank, #1 first. #1 gets the left compact ear and #2 the right (or swapped).
    /// Modules missing from it rank after the listed ones.
    public var order: [String] { didSet { defaults?.set(order, forKey: Keys.order) } }
    /// Modules shown as tabs beside the Home button.
    public var favorites: Set<String> { didSet { defaults?.set(favorites.sorted(), forKey: Keys.favorites) } }
    /// #1 takes the right ear instead of the left.
    public var swapsEarSides: Bool { didSet { defaults?.set(swapsEarSides, forKey: Keys.swapsEarSides) } }
    public var navigation: NotchNavigation { didSet { defaults?.set(navigation.rawValue, forKey: Keys.navigation) } }
    /// Where the Library sits beside Home: its button in the bar and the way to swipe to it.
    public var librarySide: LibrarySide { didSet { defaults?.set(librarySide.rawValue, forKey: Keys.librarySide) } }
    /// Modules opened most recently, newest first: the Library's "Recently used".
    public private(set) var recent: [String] { didSet { defaults?.set(recent, forKey: Keys.recent) } }

    /// Every module the app knows, in the default order.
    public static let knownModules = ["nowPlaying", "shelf", "agents", "aiUsage", "timer", "keepAwake", "notes"]
    /// Favorites until the person picks their own: everyday tools, few enough to fit any bar (ADR-0045).
    public static let defaultFavorites = ["nowPlaying", "shelf", "timer", "notes"]
    /// How many recently opened modules are kept (the Library shows up to three switched-on ones).
    static let recentLimit = 6

    @ObservationIgnored private let defaults: UserDefaults?

    /// - Parameter defaults: where to keep it; `nil` keeps it in memory only (tests, snapshots).
    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        let saved = defaults?.stringArray(forKey: Keys.order) ?? []
        // New modules (e.g. after an update) join at the end of a saved order.
        order = saved + Self.knownModules.filter { !saved.contains($0) }
        favorites = Set(defaults?.stringArray(forKey: Keys.favorites) ?? Self.defaultFavorites)
        swapsEarSides = defaults?.bool(forKey: Keys.swapsEarSides) ?? false
        navigation = defaults?.string(forKey: Keys.navigation).flatMap(NotchNavigation.init(rawValue:)) ?? .tabsAndMenu
        librarySide = defaults?.string(forKey: Keys.librarySide).flatMap(LibrarySide.init(rawValue:)) ?? .left
        recent = Array((defaults?.stringArray(forKey: Keys.recent) ?? []).prefix(Self.recentLimit))
    }

    /// Position in the ranking; unknown modules rank last, in the order they come.
    public func rank(of moduleID: String) -> Int {
        order.firstIndex(of: moduleID) ?? order.count
    }

    /// `modules` sorted by ranking (stable for unknown ones).
    public func sorted<Item>(_ items: [Item], id: (Item) -> String) -> [Item] {
        items.enumerated()
            .sorted { lhs, rhs in
                let left = rank(of: id(lhs.element)), right = rank(of: id(rhs.element))
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    public func isFavorite(_ moduleID: String) -> Bool { favorites.contains(moduleID) }

    public func toggleFavorite(_ moduleID: String) {
        if favorites.contains(moduleID) { favorites.remove(moduleID) } else { favorites.insert(moduleID) }
    }

    /// A module's page came up in the open notch: it moves to the front of `recent`.
    public func noteOpened(_ moduleID: String) {
        guard recent.first != moduleID else { return }
        recent = Array(([moduleID] + recent.filter { $0 != moduleID }).prefix(Self.recentLimit))
    }

    /// Moves a module to `index` in the ranking (clamped).
    public func move(_ moduleID: String, to index: Int) {
        guard let from = order.firstIndex(of: moduleID) else { return }
        var next = order
        next.remove(at: from)
        next.insert(moduleID, at: min(max(index, 0), next.count))
        if next != order { order = next }
    }

    /// Moves a module one place up (`-1`) or down (`1`) in the ranking.
    public func move(_ moduleID: String, by offset: Int) {
        move(moduleID, to: rank(of: moduleID) + offset)
    }

    private enum Keys {
        static let order = "modules.order"
        static let favorites = "modules.favorites"
        static let swapsEarSides = "modules.swapsEarSides"
        static let navigation = "modules.navigation"
        static let librarySide = "modules.librarySide"
        static let recent = "modules.recent"
    }
}
