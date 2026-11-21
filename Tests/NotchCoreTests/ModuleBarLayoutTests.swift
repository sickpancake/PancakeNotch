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
}
