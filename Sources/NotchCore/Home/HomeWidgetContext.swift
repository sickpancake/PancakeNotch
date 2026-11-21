import CoreGraphics
import Foundation

/// What a Home widget is told when it's drawn (ADR-0042).
public struct HomeWidgetContext {
    /// The widget's whole frame, its card included. Widgets lay out inside it with `HomeWidgetMetrics.padding`.
    public var size: CGSize
    /// Home is on screen in the open notch (or a visible editor preview) and this widget is on the page
    /// that shows: only then may it tick. Everything stops the moment this turns false.
    public var isLive: Bool
    /// Drawn off-screen for a snapshot: Core Animation views use their SwiftUI stand-in, clocks use `now`.
    public var isSnapshot: Bool
    /// Drawn with pretend data in the app window (the editor's preview and gallery).
    public var isPractice: Bool
    /// The time to show when the widget must not read the clock (snapshots); `nil` reads the clock.
    public var fixedNow: Date?
    /// Which time Home has come up (counts up each time it does): for what's read once per opening.
    public var visit: Int

    public init(size: CGSize, isLive: Bool, isSnapshot: Bool = false, isPractice: Bool = false, fixedNow: Date? = nil,
                visit: Int = 0) {
        self.size = size
        self.visit = visit
        self.isLive = isLive
        self.isSnapshot = isSnapshot
        self.isPractice = isPractice
        self.fixedNow = fixedNow
    }

    /// Room inside the card.
    public var contentSize: CGSize {
        CGSize(width: max(0, size.width - 2 * HomeWidgetMetrics.padding),
               height: max(0, size.height - 2 * HomeWidgetMetrics.padding))
    }

    /// Whether the clock should be read now; snapshots use a fixed time.
    public var now: Date { fixedNow ?? Date() }
}

/// Shared sizes for Home's grid and widget cards, so the notch and the editor draw them the same.
public enum HomeWidgetMetrics {
    /// Space between cells.
    public static let gap: CGFloat = 8
    /// Inside a card, from its edge to the content.
    public static let padding: CGFloat = 10
    /// The card's corners, like the old Module Menu's tiles.
    public static let cornerRadius: CGFloat = 12
    /// The grid's distance from the panel's sides and bottom, and below the top band.
    public static let sidePadding: CGFloat = 18
    public static let topPadding: CGFloat = 8
    public static let bottomPadding: CGFloat = 14

    /// How far apart Home's pages sit as they scroll: a page plus the panel's margins above and below it,
    /// so the gap between two pages matches the space around one.
    public static func pageStride(in area: CGSize) -> CGFloat { area.height + topPadding + bottomPadding }

    /// A cell's size when the grid fills `area`.
    public static func cellSize(in area: CGSize) -> CGSize {
        CGSize(width: max(0, (area.width - CGFloat(HomeLayout.columns - 1) * gap) / CGFloat(HomeLayout.columns)),
               height: max(0, (area.height - CGFloat(HomeLayout.rows - 1) * gap) / CGFloat(HomeLayout.rows)))
    }

    /// The frame of a widget of `size` at `column`/`row`, in a grid whose cells are `cell`.
    public static func frame(column: Int, row: Int, size: HomeWidgetSize, cell: CGSize) -> CGRect {
        CGRect(x: CGFloat(column) * (cell.width + gap),
               y: CGFloat(row) * (cell.height + gap),
               width: CGFloat(size.columns) * cell.width + CGFloat(size.columns - 1) * gap,
               height: CGFloat(size.rows) * cell.height + CGFloat(size.rows - 1) * gap)
    }

    /// The area the grid fills in the open panel: under the band, inside the side and bottom padding.
    public static func gridArea(in layout: NotchLayout) -> CGSize {
        let body = layout.bodySize(for: .expanded)
        let band = layout.geometry.notchRect.height
        let height = min(body.height, NotchLayout.maxExpandedBodySize.height)
        return CGSize(width: max(0, body.width - 2 * sidePadding),
                      height: max(0, height - band - topPadding - bottomPadding))
    }
}

/// A page of the app window that Home can open.
public enum NotchAppPage: Sendable {
    /// The Home editor.
    case homeEditor
    /// Modules, where a switched-off module is turned back on.
    case modules
    /// Statistics.
    case statistics
}

/// Turns a scroll on Home into one page step per gesture: a trackpad swipe counts once it has gone far
/// enough up or down (more than sideways); a mouse wheel moves a page per notch, at most every 0.3 s.
struct HomePageScrollTracker {
    /// How far the fingers travel before a page turns.
    static let threshold: CGFloat = 30
    /// A wheel's notches closer together than this turn one page.
    static let wheelPause: TimeInterval = 0.3

    private var travelX: CGFloat = 0
    private var travelY: CGFloat = 0
    private var isSpent = false
    private var lastWheelStep: TimeInterval = -.infinity

    /// Returns `1` (the next page) or `-1` (the previous one) when a step happens. `deltaY` is the
    /// event's `scrollingDeltaY`: negative scrolls towards later content, as in any scroll view.
    mutating func handle(phase: NotchSwipeTracker.Phase, deltaY: CGFloat, deltaX: CGFloat, isPrecise: Bool,
                         time: TimeInterval) -> Int? {
        guard isPrecise else {
            // A mouse wheel: no phases, one step per notch.
            guard abs(deltaY) > abs(deltaX), deltaY != 0, time - lastWheelStep >= Self.wheelPause else { return nil }
            lastWheelStep = time
            return deltaY < 0 ? 1 : -1
        }
        switch phase {
        case .began:
            travelX = deltaX
            travelY = deltaY
            isSpent = false
        case .changed:
            travelX += deltaX
            travelY += deltaY
        case .ended, .other:
            if phase == .ended { isSpent = false; travelX = 0; travelY = 0 }
            return nil
        }
        guard !isSpent, abs(travelY) >= Self.threshold, abs(travelY) > abs(travelX) else { return nil }
        isSpent = true
        return travelY < 0 ? 1 : -1
    }
}

/// What Home tells a lesson: it came up, or a widget click opened its module.
public enum NotchHomeEvent: Sendable, Equatable {
    case opened
    case widgetOpened(HomeWidgetKind)
}
