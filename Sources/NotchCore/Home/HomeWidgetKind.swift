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
