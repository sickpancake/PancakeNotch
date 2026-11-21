import Foundation

/// A widget's top-left cell, counted from zero.
public struct HomeSlot: Hashable, Codable, Sendable {
    public var page: Int
    public var column: Int
    public var row: Int
    public init(page: Int, column: Int, row: Int) { self.page = page; self.column = column; self.row = row }
}

/// A cell uses the same coordinates as a slot.
public typealias HomeCell = HomeSlot

/// One widget and the cells it occupies.
public struct HomePlacement: Hashable, Codable, Sendable, Identifiable {
    public var kind: HomeWidgetKind
    public var size: HomeWidgetSize
    public var slot: HomeSlot
    public var id: HomeWidgetKind { kind }
    public init(kind: HomeWidgetKind, size: HomeWidgetSize, slot: HomeSlot) {
        self.kind = kind; self.size = size; self.slot = slot
    }
    public var cells: Set<HomeCell> {
        Set((0..<size.columns).flatMap { column in
            (0..<size.rows).map { HomeCell(page: slot.page, column: slot.column + column, row: slot.row + $0) }
        })
    }
    public func overlaps(_ other: Self) -> Bool { !cells.isDisjoint(with: other.cells) }
    public var fits: Bool {
        (0..<HomeLayout.pageCount).contains(slot.page) && slot.column >= 0 && slot.row >= 0
            && slot.column <= HomeLayout.columns - size.columns && slot.row <= HomeLayout.rows - size.rows
    }
}

/// Home's saved arrangement, kept in column-first reading order.
public struct HomeLayout: Equatable, Sendable, Codable {
    public static let columns = 6, rows = 2, pageCount = 3, currentVersion = 1
    public var placements: [HomePlacement] {
        didSet { placements.sort(by: Self.readingOrder) }
    }
    public var statisticsMetric: String?
    public init(placements: [HomePlacement] = [], statisticsMetric: String? = nil) {
        self.placements = placements.sorted(by: Self.readingOrder); self.statisticsMetric = statisticsMetric
    }
    static func readingOrder(_ a: HomePlacement, _ b: HomePlacement) -> Bool {
        if a.slot.page != b.slot.page { return a.slot.page < b.slot.page }
        if a.slot.column != b.slot.column { return a.slot.column < b.slot.column }
        if a.slot.row != b.slot.row { return a.slot.row < b.slot.row }
        return a.kind.rawValue < b.kind.rawValue
    }
    public func placement(of kind: HomeWidgetKind) -> HomePlacement? { placements.first { $0.kind == kind } }
    public func contains(_ kind: HomeWidgetKind) -> Bool { placement(of: kind) != nil }
    public func placements(onPage page: Int) -> [HomePlacement] { placements.filter { $0.slot.page == page } }
    public func placement(at cell: HomeCell) -> HomePlacement? { placements.first { $0.cells.contains(cell) } }
    public var isEmpty: Bool { placements.isEmpty }
    public func isPageEmpty(_ page: Int) -> Bool { placements(onPage: page).isEmpty }
    public var nonEmptyPages: [Int] { Set(placements.map(\.slot.page)).sorted() }
    public var occupiedCells: Set<HomeCell> { placements.reduce(into: []) { $0.formUnion($1.cells) } }
    public func freeCells(onPage page: Int) -> Set<HomeCell> {
        Set(Self.slots(onPage: page)).subtracting(occupiedCells)
    }
    public func isFree(_ placement: HomePlacement) -> Bool {
        placement.fits && placement.cells.isDisjoint(with: occupiedCells)
    }
    static func slots(onPage page: Int) -> [HomeSlot] {
        guard (0..<pageCount).contains(page) else { return [] }
        return (0..<columns).flatMap { c in (0..<rows).map { HomeSlot(page: page, column: c, row: $0) } }
    }
    static func p(_ kind: HomeWidgetKind, _ size: HomeWidgetSize, _ column: Int, _ row: Int) -> HomePlacement {
        HomePlacement(kind: kind, size: size, slot: HomeSlot(page: 0, column: column, row: row))
    }
    public static let `default` = HomeLayout(placements: [
        p(.nowPlaying, .large, 0, 0), p(.timer, .medium, 2, 0), p(.agents, .medium, 2, 1),
        p(.shelf, .small, 4, 0), p(.aiUsage, .small, 5, 0), p(.keepAwake, .small, 4, 1), p(.clock, .small, 5, 1)
    ])
    enum CodingKeys: String, CodingKey { case version, placements, statisticsMetric }
    struct SavedPlacement: Encodable {
        var widget: String; var size: String; var page: Int; var column: Int; var row: Int
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(placements.map { SavedPlacement(widget: $0.kind.rawValue, size: $0.size.rawValue,
            page: $0.slot.page, column: $0.slot.column, row: $0.slot.row) }, forKey: .placements)
        try c.encodeIfPresent(statisticsMetric, forKey: .statisticsMetric)
    }
    /// Codable callers get the same forgiving repair as settings loading.
    public init(from decoder: any Decoder) throws {
        let value = try JSONValue(from: decoder)
        self = Self.decode(try? JSONSerialization.data(withJSONObject: value.object, options: [.fragmentsAllowed]))
    }
}

/// Ready-made arrangements offered by the editor.
public enum HomePreset: String, CaseIterable, Sendable {
    case standard, music, work, minimal
    public var title: String {
        switch self {
        case .standard: String(localized: "Default", comment: "Home preset")
        case .music: String(localized: "Music", comment: "Home preset")
        case .work: String(localized: "Work", comment: "Home preset")
        case .minimal: String(localized: "Minimal", comment: "Home preset")
        }
    }
    public var layout: HomeLayout {
        switch self {
        case .standard: .default
        case .music: HomeLayout(placements: [HomeLayout.p(.clock, .medium, 0, 0), HomeLayout.p(.battery, .medium, 0, 1), HomeLayout.p(.nowPlaying, .large, 2, 0), HomeLayout.p(.timer, .medium, 4, 0), HomeLayout.p(.shelf, .medium, 4, 1)])
        case .work: HomeLayout(placements: [HomeLayout.p(.agents, .large, 0, 0), HomeLayout.p(.aiUsage, .medium, 2, 0), HomeLayout.p(.timer, .medium, 2, 1), HomeLayout.p(.keepAwake, .medium, 4, 0), HomeLayout.p(.clock, .small, 4, 1), HomeLayout.p(.battery, .small, 5, 1)])
        case .minimal: HomeLayout(placements: [HomeLayout.p(.clock, .small, 0, 0), HomeLayout.p(.battery, .small, 0, 1), HomeLayout.p(.nowPlaying, .small, 1, 0), HomeLayout.p(.timer, .small, 1, 1), HomeLayout.p(.shelf, .small, 2, 0), HomeLayout.p(.keepAwake, .small, 2, 1)])
        }
    }
}
