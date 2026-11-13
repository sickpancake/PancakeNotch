import CoreGraphics

/// Where a widget dragged in the Home editor would land. Pure maths, so it's cheap to run on every
/// pointer move and the editor only does more when the answer changes.
public enum HomeDragLanding {
    /// The cell the dragged widget's top-left corner would land on, or `nil` while the pointer is more than half
    /// a cell away from the grid.
    /// - Parameters:
    ///   - pointer: The pointer, in the same space as `grid`.
    ///   - grab: Where the pointer holds the widget, from its top-left corner.
    ///   - grid: The grid's frame.
    ///   - page: The page being shown.
    public static func slot(pointer: CGPoint, grab: CGPoint, grid: CGRect, page: Int) -> HomeSlot? {
        let cell = HomeWidgetMetrics.cellSize(in: grid.size)
        guard grid.insetBy(dx: -cell.width / 2, dy: -cell.height / 2).contains(pointer) else { return nil }
        // The widget's first cell is the one under its top-left corner, nudged half a cell so it snaps.
        let centre = CGPoint(x: pointer.x - grab.x - grid.minX + cell.width / 2,
                             y: pointer.y - grab.y - grid.minY + cell.height / 2)
        return HomeSlot(
            page: page,
            column: Int((centre.x / (cell.width + HomeWidgetMetrics.gap)).rounded(.down)),
            row: Int((centre.y / (cell.height + HomeWidgetMetrics.gap)).rounded(.down))
        )
    }
}
