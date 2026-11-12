import AppKit
import Testing
@testable import NotchCore

/// Replays of two bugs a model of Home's navigation found: both must stay fixed.
@MainActor struct HomeReplayNotch {
    func model() -> NotchViewModel {
        let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        let model = NotchViewModel(layout: layout)
        model.modules = [RankedModule("timer")]
        model.home.opening = .home
        return model
    }

    /// Choosing tabs only while Home shows goes back to a module.
    @Test func tabsWhileHomeIsOpen() async {
        let m = model()
        m.open()
        #expect(m.showsHome)
        m.arrangement.navigation = .tabs
        for _ in 0..<5 { await Task.yield() }
        #expect(!m.showsHome)
        #expect(m.selectedModule?.moduleID == "timer")
        // And back: Home can be opened again once it's available.
        m.arrangement.navigation = .tabsAndMenu
        for _ in 0..<5 { await Task.yield() }
        m.toggleHome()
        #expect(m.showsHome)
    }

    /// Emptying the page that shows falls back to a page that exists.
    @Test func removingCurrentPage() {
        let m = model()
        m.home.layout = HomeLayout(placements: [
            HomePlacement(kind: .clock, size: .small, slot: HomeSlot(page: 0, column: 0, row: 0)),
            HomePlacement(kind: .battery, size: .small, slot: HomeSlot(page: 1, column: 0, row: 0))
        ])
        m.open()
        m.showHomePage(1)
        #expect(m.homePage == 1)
        m.home.layout = m.home.layout.removing(.battery)
        #expect(m.homePage == 0)
        // The arrow keys and scrolling still work from there.
        m.home.layout = HomeLayout(placements: [
            HomePlacement(kind: .clock, size: .small, slot: HomeSlot(page: 0, column: 0, row: 0)),
            HomePlacement(kind: .battery, size: .small, slot: HomeSlot(page: 1, column: 0, row: 0))
        ])
        m.showHomePage(1)
        #expect(m.homePage == 1)
    }
}
