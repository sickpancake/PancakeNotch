import CoreGraphics
import Testing
@testable import NotchCore

/// The editor's page tabs and where a dragged widget lands.
struct HomeEditorPagesTests {
    func layout(_ pages: Int...) -> HomeLayout {
        let kinds: [HomeWidgetKind] = [.clock, .battery, .shelf]
        return HomeLayout(placements: pages.enumerated().map { index, page in
            HomePlacement(kind: kinds[index], size: .small, slot: HomeSlot(page: page, column: 0, row: 0))
        })
    }

    @Test func emptyHomeIsOneTab() {
        let list = HomePageList(layout: HomeLayout(), editing: 0)
        #expect(list.pages == [0])
        #expect(!list.canAddPage) // already blank
        #expect(list.newPage == 1)
    }

    @Test func tabsAreNamedByPlace() {
        let list = HomePageList(layout: layout(0, 2), editing: 2)
        #expect(list.pages == [0, 2])
        #expect(list.number(of: 0) == 1)
        #expect(list.number(of: 2) == 2)
        #expect(list.number(of: 1) == nil)
        #expect(list.others(than: 2) == [0])
        #expect(list.newPage == 1)
        #expect(list.canAddPage)
    }

    @Test func blankPageBeingEditedIsATab() {
        let list = HomePageList(layout: layout(0), editing: 1)
        #expect(list.pages == [0, 1])
        #expect(list.editingIsEmpty)
        #expect(!list.canAddPage)
        #expect(list.newPage == 2)
    }

    @Test func noPlusWhenEveryPageHoldsWidgets() {
        let list = HomePageList(layout: layout(0, 1, 2), editing: 1)
        #expect(list.pages == [0, 1, 2])
        #expect(list.newPage == nil)
        #expect(!list.canAddPage)
    }

    @Test func nearestNonEmptyPage() {
        #expect(HomePageList.nearestNonEmptyPage(to: 1, in: layout(0, 2)) == 0) // tie: the earlier
        #expect(HomePageList.nearestNonEmptyPage(to: 2, in: layout(0, 1)) == 1)
        #expect(HomePageList.nearestNonEmptyPage(to: 0, in: layout(2)) == 2)
        #expect(HomePageList.nearestNonEmptyPage(to: 0, in: HomeLayout()) == nil)
    }

    @Test func outOfRangePageIsClamped() {
        #expect(HomePageList(layout: layout(0), editing: 9).editing == HomeLayout.pageCount - 1)
    }

    // MARK: Landing

    let grid = CGRect(x: 100, y: 50, width: 600, height: 200)

    @Test func landingFollowsTheWidgetsCorner() {
        let cell = HomeWidgetMetrics.cellSize(in: grid.size)
        // Holding a widget by its top-left corner, the pointer over the second column and first row.
        let pointer = CGPoint(x: grid.minX + cell.width + HomeWidgetMetrics.gap + 4, y: grid.minY + 4)
        #expect(HomeDragLanding.slot(pointer: pointer, grab: .zero, grid: grid, page: 1)
                == HomeSlot(page: 1, column: 1, row: 0))
        // Holding it by its middle, the corner is half a cell up and left of the pointer, and snaps to the nearest cell.
        let middle = CGPoint(x: cell.width / 2, y: cell.height / 2)
        let nearStart = CGPoint(x: grid.minX + cell.width / 2 + 4, y: grid.minY + cell.height / 2 + 4)
        #expect(HomeDragLanding.slot(pointer: nearStart, grab: middle, grid: grid, page: 1) == HomeSlot(page: 1, column: 0, row: 0))
        #expect(HomeDragLanding.slot(pointer: pointer, grab: middle, grid: grid, page: 1) == HomeSlot(page: 1, column: 1, row: 0))
    }

    @Test func landingNeedsThePointerNearTheGrid() {
        let cell = HomeWidgetMetrics.cellSize(in: grid.size)
        #expect(HomeDragLanding.slot(pointer: CGPoint(x: grid.midX, y: grid.minY - cell.height), grab: .zero, grid: grid, page: 0) == nil)
        #expect(HomeDragLanding.slot(pointer: CGPoint(x: grid.midX, y: grid.minY - cell.height / 3), grab: .zero, grid: grid, page: 0) != nil)
        #expect(HomeDragLanding.slot(pointer: CGPoint(x: grid.maxX + cell.width, y: grid.midY), grab: .zero, grid: grid, page: 0) == nil)
    }
}

/// Adding a widget while looking at a page (even a blank new one) puts it there when it fits.
struct HomeAddingOnPageTests {
    @Test func addsToTheBlankPageInView() throws {
        let layout = HomeLayout.default
        let next = try layout.adding(.battery, preferring: 1).get()
        #expect(next.placement(of: .battery)?.slot.page == 1)
        #expect(next.placement(of: .battery)?.slot.column == 0)
    }

    @Test func fallsBackWhenThePageIsFull() throws {
        var full = HomeLayout()
        for kind in [HomeWidgetKind.nowPlaying, .timer, .agents] {
            full = try full.adding(kind, size: .large, preferring: 0).get()
        }
        #expect(full.placements(onPage: 0).count == 3)
        let next = try full.adding(.clock, preferring: 0).get()
        #expect(next.placement(of: .clock)?.slot.page == 1)
    }

    @Test func withoutAPageItStillTakesTheFirstGap() throws {
        let next = try HomeLayout().adding(.clock).get()
        #expect(next.placement(of: .clock)?.slot == HomeSlot(page: 0, column: 0, row: 0))
    }
}
