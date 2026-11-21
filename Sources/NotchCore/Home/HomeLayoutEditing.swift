import Foundation

/// Why an edit could not be applied; the saved layout stays intact.
public enum HomeEditRefusal: Error, Equatable, Sendable {
    case full, alreadyOnHome, unsupportedSize, notOnHome, outOfRange
    public var message: String {
        switch self {
        case .full: String(localized: "Home is full. Remove a widget or make one smaller first.")
        case .alreadyOnHome: String(localized: "This widget is already on Home.")
        case .unsupportedSize: String(localized: "This widget doesn't come in that size.")
        case .notOnHome: String(localized: "This widget isn't on Home.")
        case .outOfRange: String(localized: "That spot is outside Home.")
        }
    }
}

/// A one-cell keyboard move.
public enum HomeNudge: Sendable { case left, right, up, down }

extension HomeLayout {
    /// Adds at the first gap, trying smaller sizes if needed. With `page`, that page comes first (the one
    /// the person is looking at, even a blank new one); only if it has no room does it go elsewhere.
    public func adding(_ kind: HomeWidgetKind, size: HomeWidgetSize? = nil, preferring page: Int? = nil) -> Result<Self, HomeEditRefusal> {
        guard !contains(kind) else { return .failure(.alreadyOnHome) }
        let requested = size ?? kind.defaultSize
        guard kind.supports(requested) else { return .failure(.unsupportedSize) }
        if let page, (0..<Self.pageCount).contains(page) {
            for candidate in kind.sizes.reversed() where candidate <= requested {
                if let slot = firstSpot(kind, candidate, pages: [page]) {
                    var next = self
                    next.placements.append(HomePlacement(kind: kind, size: candidate, slot: slot))
                    return .success(next)
                }
            }
        }
        for candidate in kind.sizes.reversed() where candidate <= requested {
            if let slot = firstSpot(kind, candidate, pages: Array(0..<Self.pageCount)) {
                var next = self
                next.placements.append(HomePlacement(kind: kind, size: candidate, slot: slot))
                return .success(next)
            }
        }
        return .failure(.full)
    }

    /// Drops a new gallery widget and makes room around it.
    public func inserting(_ kind: HomeWidgetKind, size: HomeWidgetSize, at slot: HomeSlot) -> Result<Self, HomeEditRefusal> {
        guard !contains(kind) else { return .failure(.alreadyOnHome) }
        guard kind.supports(size) else { return .failure(.unsupportedSize) }
        return placing(HomePlacement(kind: kind, size: size, slot: slot))
    }

    /// Moves one widget, keeping unaffected neighbours in place when possible.
    public func moving(_ kind: HomeWidgetKind, to slot: HomeSlot) -> Result<Self, HomeEditRefusal> {
        guard var item = placement(of: kind) else { return .failure(.notOnHome) }
        if item.slot == slot { return .success(self) }
        item.slot = slot
        return placing(item)
    }

    /// Changes the footprint while keeping its top-left corner when possible.
    public func resizing(_ kind: HomeWidgetKind, to size: HomeWidgetSize) -> Result<Self, HomeEditRefusal> {
        guard var item = placement(of: kind) else { return .failure(.notOnHome) }
        guard kind.supports(size) else { return .failure(.unsupportedSize) }
        if item.size == size { return .success(self) }
        item.size = size
        return placing(item)
    }

    /// Removing a widget keeps its saved options for next time.
    public func removing(_ kind: HomeWidgetKind) -> Self {
        var next = self; next.placements.removeAll { $0.kind == kind }; return next
    }

    /// Prefers a free gap on the requested page before displacing neighbours.
    public func movingToPage(_ kind: HomeWidgetKind, page: Int) -> Result<Self, HomeEditRefusal> {
        guard let item = placement(of: kind) else { return .failure(.notOnHome) }
        guard (0..<Self.pageCount).contains(page) else { return .failure(.outOfRange) }
        let space = removing(kind)
        let slot = space.firstSpot(kind, item.size, pages: [page])
            ?? HomeSlot(page: page, column: item.slot.column, row: item.slot.row)
        return moving(kind, to: slot)
    }

    /// Horizontal moves can cross a page boundary; vertical moves stay on the page.
    public func nudging(_ kind: HomeWidgetKind, by direction: HomeNudge) -> Result<Self, HomeEditRefusal> {
        guard let item = placement(of: kind) else { return .failure(.notOnHome) }
        var slot = item.slot
        switch direction {
        case .left:
            if slot.column == 0 { slot.page -= 1; slot.column = Self.columns - item.size.columns }
            else { slot.column -= 1 }
        case .right:
            if slot.column == Self.columns - item.size.columns { slot.page += 1; slot.column = 0 }
            else { slot.column += 1 }
        case .up: slot.row -= 1
        case .down: slot.row += 1
        }
        guard slot.row >= 0, slot.row <= Self.rows - item.size.rows else { return .failure(.outOfRange) }
        return moving(kind, to: slot)
    }

    /// Presets replace the arrangement but remember the Statistics option.
    public func applying(_ preset: HomePreset) -> Self {
        var next = preset.layout; next.statisticsMetric = statisticsMetric; return next
    }
    /// The editor uses the same rules for drag previews and the final drop.
    public func previewMoving(_ kind: HomeWidgetKind, to slot: HomeSlot) -> Self? { try? moving(kind, to: slot).get() }
    /// A gallery preview also shows the neighbours that would move.
    public func previewInserting(_ kind: HomeWidgetKind, size: HomeWidgetSize, at slot: HomeSlot) -> Self? {
        try? inserting(kind, size: size, at: slot).get()
    }

    func firstSpot(_ kind: HomeWidgetKind, _ size: HomeWidgetSize, pages: [Int]) -> HomeSlot? {
        pages.flatMap { Self.slots(onPage: $0) }.first { isFree(HomePlacement(kind: kind, size: size, slot: $0)) }
    }
    private static func largestFirst(_ a: HomePlacement, _ b: HomePlacement) -> Bool {
        a.size != b.size ? a.size > b.size : readingOrder(a, b)
    }
    private func placing(_ proposed: HomePlacement) -> Result<Self, HomeEditRefusal> {
        guard (0..<Self.pageCount).contains(proposed.slot.page) else { return .failure(.outOfRange) }
        var fixed = proposed
        fixed.slot.column = min(max(0, fixed.slot.column), Self.columns - fixed.size.columns)
        fixed.slot.row = min(max(0, fixed.slot.row), Self.rows - fixed.size.rows)
        let others = placements.filter { $0.kind != fixed.kind }
        let displaced = others.filter { $0.overlaps(fixed) }.sorted(by: Self.largestFirst)
        var next = Self(placements: others.filter { !$0.overlaps(fixed) } + [fixed], statisticsMetric: statisticsMetric)
        var failed = false
        for item in displaced {
            let nearest = Self.slots(onPage: item.slot.page).sorted {
                let left = abs($0.column - item.slot.column) + abs($0.row - item.slot.row)
                let right = abs($1.column - item.slot.column) + abs($1.row - item.slot.row)
                if left != right { return left < right }
                return $0.column != $1.column ? $0.column < $1.column : $0.row < $1.row
            }.first { next.isFree(HomePlacement(kind: item.kind, size: item.size, slot: $0)) }
            let pages = Array((item.slot.page + 1)..<Self.pageCount) + Array(0..<item.slot.page)
            guard let spot = nearest ?? next.firstSpot(item.kind, item.size, pages: pages) else { failed = true; break }
            next.placements.append(HomePlacement(kind: item.kind, size: item.size, slot: spot))
        }
        if !failed { return .success(next) }
        next = Self(placements: [fixed], statisticsMetric: statisticsMetric)
        for item in others.sorted(by: Self.largestFirst) {
            guard let spot = next.firstSpot(item.kind, item.size, pages: Array(0..<Self.pageCount)) else { return .failure(.full) }
            next.placements.append(HomePlacement(kind: item.kind, size: item.size, slot: spot))
        }
        return .success(next)
    }
}
