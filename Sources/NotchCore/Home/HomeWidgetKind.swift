import Foundation

/// The three footprints offered in the Home gallery.
public enum HomeWidgetSize: String, Codable, CaseIterable, Sendable, Comparable {
    case small, medium, large
    public var columns: Int { self == .small ? 1 : 2 }
    public var rows: Int { self == .large ? 2 : 1 }
    public var cellCount: Int { columns * rows }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.cellCount < rhs.cellCount }
}

/// The gallery order and the options each widget offers.
public enum HomeWidgetKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case nowPlaying, timer, stopwatch, agents, aiUsage, shelf, keepAwake, allModules, clock, battery, statistics
    public var id: String { rawValue }
    public var moduleID: String? {
        switch self {
        case .nowPlaying, .agents, .aiUsage, .shelf, .keepAwake: rawValue
        case .timer, .stopwatch: "timer"
        default: nil
        }
    }
    public var sizes: [HomeWidgetSize] {
        switch self {
        case .allModules: [.large]
        case .aiUsage, .keepAwake, .clock, .battery, .statistics: [.small, .medium]
        default: [.small, .medium, .large]
        }
    }
    public var defaultSize: HomeWidgetSize {
        switch self {
        case .nowPlaying, .allModules: .large
        case .timer, .stopwatch, .agents: .medium
        default: .small
        }
    }
    public var title: String {
        switch self {
        case .nowPlaying: String(localized: "Now Playing", comment: "Home widget name")
        case .timer: String(localized: "Timer", comment: "Home widget name")
        case .stopwatch: String(localized: "Stopwatch", comment: "Home widget name")
        case .agents: String(localized: "Agents", comment: "Home widget name")
        case .aiUsage: String(localized: "AI Usage", comment: "Home widget name")
        case .shelf: String(localized: "Shelf", comment: "Home widget name")
        case .keepAwake: String(localized: "Keep Awake", comment: "Home widget name")
        case .allModules: String(localized: "All Modules", comment: "Home widget name")
        case .clock: String(localized: "Clock", comment: "Home widget name")
        case .battery: String(localized: "Battery", comment: "Home widget name")
        case .statistics: String(localized: "Statistics", comment: "Home widget name")
        }
    }
    public var symbol: String {
        switch self {
        case .nowPlaying: "music.note"
        case .timer: "timer"
        case .stopwatch: "stopwatch"
        case .agents: "sparkles"
        case .aiUsage: "gauge.with.dots.needle.50percent"
        case .shelf: "tray"
        case .keepAwake: "cup.and.saucer"
        case .allModules: "square.grid.2x2"
        case .clock: "clock"
        case .battery: "battery.75percent"
        case .statistics: "chart.bar"
        }
    }
    public func supports(_ size: HomeWidgetSize) -> Bool { sizes.contains(size) }
    public static func kinds(forModule moduleID: String) -> [Self] { allCases.filter { $0.moduleID == moduleID } }
}

// MARK: Search

extension HomeWidgetKind {
    /// Words people might type when looking for this widget, besides its name.
    public var searchTerms: [String] {
        let words = switch self {
        case .nowPlaying: String(localized: "music, song, album, audio, podcast, Spotify, Apple Music, media, play, pause",
                                 comment: "Words that find the Now Playing widget in the Home widget search, separated by commas")
        case .timer: String(localized: "countdown, alarm, time, minutes, reminder",
                            comment: "Words that find the Timer widget in the Home widget search, separated by commas")
        case .stopwatch: String(localized: "laps, time, count up, timing",
                                comment: "Words that find the Stopwatch widget in the Home widget search, separated by commas")
        case .agents: String(localized: "Claude Code, Codex, Cursor, AI, coding, assistant, conversations",
                             comment: "Words that find the Agents widget in the Home widget search, separated by commas")
        case .aiUsage: String(localized: "limits, tokens, plan, Claude, Codex, cost, quota",
                              comment: "Words that find the AI Usage widget in the Home widget search, separated by commas")
        case .shelf: String(localized: "files, drop, drag, links, AirDrop, share, clipboard",
                            comment: "Words that find the Shelf widget in the Home widget search, separated by commas")
        case .keepAwake: String(localized: "sleep, coffee, caffeine, awake, screen, lock, stay on",
                                comment: "Words that find the Keep Awake widget in the Home widget search, separated by commas")
        case .allModules: String(localized: "modules, menu, shortcuts, launcher",
                                 comment: "Words that find the All Modules widget in the Home widget search, separated by commas")
        case .clock: String(localized: "time, date, hour, day",
                            comment: "Words that find the Clock widget in the Home widget search, separated by commas")
        case .battery: String(localized: "power, charge, charging, plugged in, energy",
                              comment: "Words that find the Battery widget in the Home widget search, separated by commas")
        case .statistics: String(localized: "stats, numbers, listening, history, charts",
                                 comment: "Words that find the Statistics widget in the Home widget search, separated by commas")
        }
        return words.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Whether a search finds this widget: each word typed starts a word of its name or its search terms,
    /// ignoring case and accents ("apple mu" finds Now Playing, "tim" finds Timer). An empty search finds all.
    public func matches(search: String) -> Bool {
        let typed = Self.words(in: search)
        guard !typed.isEmpty else { return true }
        let own = Self.words(in: ([title] + searchTerms).joined(separator: " "))
        return typed.allSatisfy { word in own.contains { $0.hasPrefix(word) } }
    }

    private static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
