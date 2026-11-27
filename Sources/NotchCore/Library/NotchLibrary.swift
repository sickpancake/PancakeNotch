import Foundation
import Observation
import SwiftUI

/// Where the open notch is: the Library, Home or a module. The bar shows them in this order (the Library
/// on the side the person chose), and sideways swipes and ←/→ walk it (ADR-0045).
public enum NotchPlace: Hashable, Sendable {
    case library, home
    case module(String)

    public var moduleID: String? {
        if case .module(let id) = self { id } else { nil }
    }

    /// Home and the Library share one sliding pager; modules are separate pages.
    var isHub: Bool { moduleID == nil }
}

/// How a page that arrives comes in, so it comes from where the person looked: from its side for a swipe,
/// an arrow key or a tab; grown from the bar's corner for Home or the Library from their buttons; grown out
/// of the tile that was clicked in the Library.
public enum NotchEntrance: Equatable, Sendable {
    case slide(forward: Bool)
    case reveal
    case grow(from: UnitPoint)
}

/// One module in the Library: switched on (with its live status) or off.
public struct LibraryEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String
    /// One short line ("Playing", "3 items"), "Off" for a switched-off module, or `nil`.
    public let status: String?
    public let isOn: Bool
    public let isFavorite: Bool
    /// A favorite the bar has no room for: its tile says so (ADR-0045).
    public let isFavoriteWithoutRoom: Bool
    /// Something here waits for the person (an agent's question, a finished timer).
    public let waitsForYou: Bool
}

/// What a short note under the Library says, for a moment.
public enum LibraryNote: Equatable, Sendable {
    /// A favorite was refused: the bar has no room.
    case barFull
}

/// The Library's search and keyboard state (ADR-0045). Owned by `NotchViewModel`; it resets when the Library
/// goes away, so the next visit starts with an empty search.
@MainActor
@Observable
public final class NotchLibrary {
    /// The words typed in the search field.
    public internal(set) var query = ""
    /// The tile the arrow keys are on (Return opens it), by module ID. `nil` until an arrow key or typing.
    public internal(set) var highlight: String?
    /// The search field has the keyboard: typing filters, and a typed search holds the notch open.
    public internal(set) var isTyping = false
    /// Goes up on every request to type, so the field takes focus again even while it already wants it.
    public internal(set) var focusRequest = 0
    /// A short note under the tiles, shown for a moment (a refused favorite).
    public internal(set) var note: LibraryNote?
    @ObservationIgnored var noteTask: Task<Void, Never>?

    func reset() {
        query = ""
        highlight = nil
        isTyping = false
        noteTask?.cancel()
        noteTask = nil
        note = nil
    }

    /// Orders `entries` for a search: names that match first, then those found by other words, each in
    /// ranking order. An empty search keeps every entry in ranking order.
    public static func results(_ entries: [LibraryEntry], for query: String) -> [LibraryEntry] {
        guard !SearchWords.words(in: query).isEmpty else { return entries }
        let byName = entries.filter { SearchWords.matches(query, in: [$0.title]) }
        let byWord = entries.filter { entry in
            !byName.contains(entry) && SearchWords.matches(query, in: [entry.title] + ModuleCatalog.info(entry.id).keywords)
        }
        return byName + byWord
    }
}
