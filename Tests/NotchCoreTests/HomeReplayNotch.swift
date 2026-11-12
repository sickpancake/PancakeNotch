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

extension HomeReplayNotch {
    /// FirstPage trace: open Home, second page, module, remove last module.
    @Test func lastModuleRemovalStartsHomeOnFirstPage() {
        let m = model()
        m.home.layout = HomeLayout(placements: [
            HomePlacement(kind: .clock, size: .small, slot: .init(page: 0, column: 0, row: 0)),
            HomePlacement(kind: .battery, size: .small, slot: .init(page: 1, column: 0, row: 0))
        ])
        m.open(); m.showHomePage(1); m.toggleHome(); m.modules = []
        #expect(m.showsHome)
        #expect(m.homePage == 0)
    }
    @Test func waitingWinsAndWidgetOpensModule() {
        let m = model(), waiting = WaitingModule("agents")
        waiting.waitsForYou = true
        m.modules.append(waiting)
        m.open()
        #expect(!m.showsHome)
        #expect(m.selectedModule?.moduleID == "agents")
        m.toggleHome(); m.openFromHome(.stopwatch)
        #expect(!m.showsHome)
        #expect(m.selectedModule?.moduleID == "timer")
        m.close(); m.home.opening = .lastModule; waiting.waitsForYou = false
        m.open(); #expect(!m.showsHome)
    }
    @Test func tabsWithNoModulesShowsPlaceholder() {
        let m = model(); m.arrangement.navigation = .tabs; m.modules = []; m.open()
        #expect(!m.showsHome); #expect(m.selectedModule == nil)
    }
}

extension HomeReplayNotch {
    @Test func callbacksBalanceAcrossHomeAndRemoval() {
        let m = model(), a = RankedModule("timer"), b = RankedModule("shelf")
        m.modules = [a,b]; m.home.opening = .lastModule
        m.open(); #expect(a.opens - a.closes == 1)
        m.toggleHome(); #expect(a.opens == a.closes)
        m.openFromHome(.shelf); #expect(b.opens - b.closes == 1)
        m.select("timer"); #expect(b.opens == b.closes); #expect(a.opens - a.closes == 1)
        m.modules = [b]; #expect(a.opens == a.closes); #expect(b.opens - b.closes == 1)
        m.close(); #expect(b.opens == b.closes)
    }
    @Test func reopenAndToggleStartOnFirstPage() {
        let m = model()
        m.home.layout = HomeLayout(placements: [
            HomePlacement(kind: .clock, size: .small, slot: .init(page: 0, column: 0, row: 0)),
            HomePlacement(kind: .battery, size: .small, slot: .init(page: 2, column: 0, row: 0))
        ])
        m.open(); m.showHomePage(1); m.close(); m.open(); #expect(m.homePage == 0)
        m.showHomePage(1); m.toggleHome(); m.toggleHome(); #expect(m.homePage == 0)
    }
}


extension HomeReplayNotch {
    // Model paths: Settings(idle), Select, Open; targeted and waiting opens still win.
    @Test(arguments: [true, false]) func idleLastModuleUsesHomeWhenAvailable(tabs: Bool) {
        let m = model(), idle = WaitingModule("idle")
        idle.isIdleForOpening = true
        m.modules = [idle]
        m.home.opening = .lastModule
        m.arrangement.navigation = tabs ? .tabs : .tabsAndMenu
        m.open()
        #expect(m.showsHome == !tabs)
        #expect(m.selectedModule?.moduleID == "idle")
    }

    @Test func focusAndWaitingBeatIdleFallback() {
        let m = model(), idle = WaitingModule("idle"), active = WaitingModule("active")
        idle.isIdleForOpening = true
        active.wantsFocus = true
        m.modules = [idle, active]
        m.home.opening = .lastModule
        m.open()
        #expect(!m.showsHome)
        #expect(m.selectedModule?.moduleID == "active")
        m.close()
        active.wantsFocus = false
        active.waitsForYou = true
        m.select("idle")
        m.open()
        #expect(!m.showsHome)
        #expect(m.selectedModule?.moduleID == "active")
        m.close()
        m.open(focusing: "idle")
        #expect(!m.showsHome)
        #expect(m.selectedModule?.moduleID == "idle")
    }
}
