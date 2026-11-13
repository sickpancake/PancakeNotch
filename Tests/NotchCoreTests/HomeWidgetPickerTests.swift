import Testing
@testable import NotchCore

@MainActor
struct HomeWidgetPickerTests {
    @Test func disabledModulesLeaveIndependentWidgetsInGalleryOrder() {
        let resolver = HomeWidgetResolver(modules: [], arrangement: ModuleArrangement())
        #expect(HomeWidgetPicker.addable(layout: HomeLayout(), resolver: resolver)
                == [.allModules, .clock, .battery, .statistics])
    }

    @Test func timerEnablesBothWidgetsButPlacementExcludesOnlyOne() throws {
        let resolver = HomeWidgetResolver(modules: [RankedModule("timer")], arrangement: ModuleArrangement())
        let available = HomeWidgetPicker.addable(layout: HomeLayout(), resolver: resolver)
        #expect(available == [.timer, .stopwatch, .allModules, .clock, .battery, .statistics])
        let layout = try HomeLayout().adding(.timer).get()
        let remaining = HomeWidgetPicker.addable(layout: layout, resolver: resolver)
        #expect(!remaining.contains(.timer))
        #expect(remaining.contains(.stopwatch))
    }

    @Test func placementOnAnotherPageIsExcludedAndAllPlacedIsEmpty() {
        let kinds: [HomeWidgetKind] = [.allModules, .clock, .battery, .statistics]
        let resolver = HomeWidgetResolver(modules: [], arrangement: ModuleArrangement())
        let layout = HomeLayout(placements: kinds.enumerated().map { index, kind in
            HomePlacement(kind: kind, size: kind.defaultSize,
                          slot: HomeSlot(page: index % 3, column: index, row: 0))
        })
        #expect(HomeWidgetPicker.addable(layout: layout, resolver: resolver).isEmpty)
    }
}
