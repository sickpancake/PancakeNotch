import CoreGraphics
import Testing
@testable import NotchCore

@MainActor
struct ModuleBarLayoutTests {
    @Test(arguments: [NotchNavigation.tabsAndMenu, .tabs, .menu])
    func everyButtonStaysBesideTheHardwareCutout(navigation: NotchNavigation) {
        // Vary both display scaling (the cutout's point width) and module count.
        for cutoutWidth in [160.0, 185, 200, 240, 300] {
            for count in 2...12 {
                let geometry = NotchGeometry.simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                                       size: CGSize(width: cutoutWidth, height: 32))
                let model = NotchViewModel(layout: NotchLayout(geometry: geometry), state: .expanded,
                                           arrangement: ModuleArrangement())
                model.modules = (0..<count).map { RankedModule("module-\($0)") }
                model.arrangement.favorites = Set(model.modules.map(\.moduleID))
                model.arrangement.navigation = navigation
                model.select("module-\(count - 1)")
                let fit = NotchModuleBar.fit(for: model)
                let cutoutLeft = (model.layout.bodySize(for: .expanded).width - cutoutWidth) / 2
                #expect(NotchModuleBar.width(for: model) <= cutoutLeft)
                #expect(fit.contentWidth <= fit.available)
                if !fit.usesMenu { #expect(fit.buttonWidth >= 22) }
            }
        }
    }

    @Test func sixModulesFitAsTabsInsteadOfHidingKeepAwake() {
        let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        let model = NotchViewModel(layout: layout, state: .expanded, arrangement: ModuleArrangement())
        model.modules = ["nowPlaying", "agents", "shelf", "aiUsage", "timer", "keepAwake"].map(RankedModule.init)
        model.select("keepAwake")
        let fit = NotchModuleBar.fit(for: model)
        #expect(!fit.usesMenu)
        #expect(model.tabModules.count == 6)
        #expect(fit.buttonWidth < NotchModuleBar.buttonSize.width)
    }

    @Test func sevenFavoritesKeepHomeAndTabsInsteadOfTheNameButton() {
        let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        let model = NotchViewModel(layout: layout, state: .expanded, arrangement: ModuleArrangement())
        model.modules = ModuleArrangement.knownModules.map(RankedModule.init)
        model.select("keepAwake")
        let fit = NotchModuleBar.fit(for: model)
        #expect(!fit.usesMenu)
        #expect(fit.buttonWidth >= NotchModuleBar.minButtonWidth)
        #expect(fit.tabModuleIDs.contains("keepAwake"))
        #expect(fit.tabModuleIDs.count < model.tabModules.count)
        #expect(fit.tabModuleIDs == Array(model.tabModules.map(\.moduleID).prefix(fit.tabModuleIDs.count)))
    }

    @Test func theCurrentModuleKeepsItsTabWhenTabsDropOff() {
        let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        let model = NotchViewModel(layout: layout, state: .expanded, arrangement: ModuleArrangement())
        model.modules = ModuleArrangement.knownModules.map(RankedModule.init)
        model.select("notes")
        let fit = NotchModuleBar.fit(for: model)
        #expect(!fit.usesMenu)
        #expect(fit.tabModuleIDs.last == "notes")
    }

    @Test func theNameButtonShowsOnlyWhenChosen() {
        let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        let model = NotchViewModel(layout: layout, state: .expanded, arrangement: ModuleArrangement())
        model.modules = ModuleArrangement.knownModules.map(RankedModule.init)
        model.select("keepAwake")
        #expect(model.arrangement.navigation == .tabsAndMenu)
        model.arrangement.navigation = .menu
        #expect(NotchModuleBar.fit(for: model).usesMenu)
    }
}
