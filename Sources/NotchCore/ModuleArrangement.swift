import Foundation
import Observation

/// How the open notch lets you move between modules (Notch settings).
public enum NotchNavigation: String, CaseIterable, Sendable {
    /// A Menu button, then tabs for the favorite modules (the default).
    case tabsAndMenu
    /// Tabs for every module, no Menu.
    case tabs
    /// Only the current module's name: click it for the Menu.
    case menu
}

/// The user's module order, favorites and ear sides (ADR-0010, ADR-0011), edited on the Modules page
/// and in the notch's Menu. Stored in `UserDefaults`, or only in memory when there are no defaults.
@MainActor
@Observable
public final class ModuleArrangement {
    /// Module IDs by rank, #1 first. #1 gets the left compact ear and #2 the right (or swapped).
    /// Modules missing from it rank after the listed ones.
    public var order: [String] { didSet { defaults?.set(order, forKey: Keys.order) } }
    /// Modules shown as tabs beside the Menu button and in the Menu's Favorites grid.
    public var favorites: Set<String> { didSet { defaults?.set(favorites.sorted(), forKey: Keys.favorites) } }
    /// #1 takes the right ear instead of the left.
    public var swapsEarSides: Bool { didSet { defaults?.set(swapsEarSides, forKey: Keys.swapsEarSides) } }
    public var navigation: NotchNavigation { didSet { defaults?.set(navigation.rawValue, forKey: Keys.navigation) } }

    /// Every module the app knows, in the default order.
    public static let knownModules = ["nowPlaying", "shelf"]

    @ObservationIgnored private let defaults: UserDefaults?

    /// - Parameter defaults: where to keep it; `nil` keeps it in memory only (tests, snapshots).
    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        let saved = defaults?.stringArray(forKey: Keys.order) ?? []
        // New modules (e.g. after an update) join at the end of a saved order.
        order = saved + Self.knownModules.filter { !saved.contains($0) }
        favorites = Set(defaults?.stringArray(forKey: Keys.favorites) ?? Self.knownModules)
        swapsEarSides = defaults?.bool(forKey: Keys.swapsEarSides) ?? false
        navigation = defaults?.string(forKey: Keys.navigation).flatMap(NotchNavigation.init(rawValue:)) ?? .tabsAndMenu
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
    }
}
