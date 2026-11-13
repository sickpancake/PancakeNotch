import Foundation

/// The pages the Home editor offers as tabs: the ones that hold widgets, plus the page being edited if
/// it's empty (a fresh page made with "+", or an empty Home). Tabs are named by their place in this list,
/// not by the page's stored number, because stored pages can have gaps (0 and 2, say).
public struct HomePageList: Equatable, Sendable {
    /// Stored page numbers, in order.
    public let pages: [Int]
    /// The page being edited.
    public let editing: Int
    /// The first stored page that isn't a tab yet (so it's empty), or `nil` when all of them are.
    public let newPage: Int?
    /// Whether the page being edited holds nothing.
    public let editingIsEmpty: Bool

    public init(layout: HomeLayout, editing: Int) {
        let editing = min(max(0, editing), HomeLayout.pageCount - 1)
        self.editing = editing
        let pages = Set(layout.nonEmptyPages + [editing]).sorted()
        self.pages = pages
        newPage = (0..<HomeLayout.pageCount).first { !pages.contains($0) }
        editingIsEmpty = layout.isPageEmpty(editing)
    }

    /// The "+" button: a free page exists, and the page being edited isn't a blank one already.
    public var canAddPage: Bool { newPage != nil && !editingIsEmpty }

    /// The 1-based place of a stored page in the list ("Page 1"), or `nil` if it isn't one of the tabs.
    public func number(of page: Int) -> Int? { pages.firstIndex(of: page).map { $0 + 1 } }

    /// The other tabs, for a "Move to" menu.
    public func others(than page: Int) -> [Int] { pages.filter { $0 != page } }

    /// The page with widgets that is closest to `page` (the earlier one on a tie), for after an edit empties
    /// a page; `nil` when Home is empty.
    public static func nearestNonEmptyPage(to page: Int, in layout: HomeLayout) -> Int? {
        layout.nonEmptyPages.min { left, right in
            let (a, b) = (abs(left - page), abs(right - page))
            return a != b ? a < b : left < right
        }
    }
}
