import Foundation

/// A module's name, symbol and the other words that find it, known even while it's switched off (a
/// switched-off module has no `NotchModule`, but the Library and the app window still list it).
public struct ModuleInfo: Sendable, Equatable {
    public let id: String
    public let title: String
    public let symbol: String
    /// Other words people type for it in the Library's search: its widgets' search terms.
    public let keywords: [String]
}

/// Every module the app knows, by ID (ADR-0045). One table for the Library and the app window, so a module
/// reads the same everywhere.
public enum ModuleCatalog {
    public static func info(_ moduleID: String) -> ModuleInfo {
        let (title, symbol): (String, String) = switch moduleID {
        case "nowPlaying": (String(localized: "Now Playing", comment: "Module name"), "music.note")
        case "shelf": (String(localized: "Shelf", comment: "Module name"), "tray")
        case "agents": (String(localized: "Agents", comment: "Module name"), "sparkles")
        case "aiUsage": (String(localized: "AI Usage", comment: "Module name"), "gauge.with.dots.needle.50percent")
        case "timer": (String(localized: "Timer", comment: "Module name"), "timer")
        case "keepAwake": (String(localized: "Keep Awake", comment: "Module name"), "cup.and.heat.waves")
        case "notes": (String(localized: "Notes", comment: "Module name"), "note.text")
        default: (moduleID, "square")
        }
        var keywords: [String] = []
        for kind in HomeWidgetKind.kinds(forModule: moduleID) {
            // The Timer's widgets are Timer and Stopwatch: "stopwatch" finds the Timer module too.
            if kind.title != title { keywords.append(kind.title) }
            keywords += kind.searchTerms.filter { !keywords.contains($0) }
        }
        return ModuleInfo(id: moduleID, title: title, symbol: symbol, keywords: keywords)
    }
}

/// Word-start matching shared by the Home widget search and the Library: each typed word must start a word
/// of the name or the search terms, ignoring case, accents and punctuation ("apple mu" finds Now Playing,
/// "tim" finds Timer, but "lay" doesn't).
enum SearchWords {
    static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Whether every word of `search` starts a word in `texts`. An empty search matches everything.
    static func matches(_ search: String, in texts: [String]) -> Bool {
        let typed = words(in: search)
        guard !typed.isEmpty else { return true }
        let own = words(in: texts.joined(separator: " "))
        return typed.allSatisfy { word in own.contains { $0.hasPrefix(word) } }
    }
}
