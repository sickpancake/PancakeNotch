import CoreGraphics
import Testing
@testable import NotchCore

@MainActor
struct ModuleBarLayoutTests {
    private func model(modules: [String] = ModuleArrangement.knownModules, cutoutWidth: CGFloat? = nil) -> NotchViewModel {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = cutoutWidth.map { NotchGeometry.simulated(in: screen, size: CGSize(width: $0, height: 32)) }
            ?? .simulated(in: screen)
        let model = NotchViewModel(layout: NotchLayout(geometry: geometry), state: .expanded, arrangement: ModuleArrangement())
        model.modules = modules.map(RankedModule.init)
        return model
    }

    @Test(arguments: [NotchNavigation.tabsAndMenu, .tabs, .menu])
    func everyButtonStaysBesideTheHardwareCutout(navigation: NotchNavigation) {
        // Vary both display scaling (the cutout's point width) and module count.
        for cutoutWidth in [160.0, 185, 200, 240, 300] {
            for count in 2...12 {
                let model = model(modules: (0..<count).map { "module-\($0)" }, cutoutWidth: cutoutWidth)
                model.arrangement.favorites = Set(model.modules.map(\.moduleID))
                model.arrangement.navigation = navigation
                model.select("module-\(count - 1)")
                let fit = NotchModuleBar.fit(for: model)
                let cutoutLeft = (model.layout.bodySize(for: .expanded).width - cutoutWidth) / 2
                #expect(NotchModuleBar.width(for: model) <= cutoutLeft)
                #expect(fit.contentWidth <= fit.available)
                #expect(fit.buttonWidth >= NotchModuleBar.minButtonWidth)
                #expect(fit.tabModuleIDs.count <= fit.capacity)
            }
        }
    }

    @Test func aFullBarShowsTheTopRankedFavoritesAndTheLibraryHasTheRest() {
        let model = model()
        model.arrangement.favorites = Set(ModuleArrangement.knownModules)
        model.select("notes")
        let fit = NotchModuleBar.fit(for: model)
        #expect(!fit.usesNameButton)
        #expect(fit.capacity < ModuleArrangement.knownModules.count)
        #expect(fit.tabModuleIDs == Array(model.tabModules.map(\.moduleID).prefix(fit.capacity)))
        // The current module isn't pushed in: it shows beside the camera instead.
        #expect(!fit.tabModuleIDs.contains("notes"))
        #expect(model.visitingModule?.moduleID == "notes")
        #expect(model.libraryEntries.first { $0.id == "notes" }?.isFavoriteWithoutRoom == true)
    }

    @Test func theDefaultScreenHasRoomForFiveFavoritesBesideHomeAndTheLibrary() {
        let model = model()
        #expect(model.favoriteCapacity == 5)
        model.arrangement.navigation = .tabs
        // With tabs only there's no Home button: one more tab fits.
        #expect(model.favoriteCapacity == 6)
    }

    @Test func aModuleWithATabNeverVisits() {
        let model = model()
        model.arrangement.favorites = ["timer"]
        model.select("timer")
        #expect(NotchModuleBar.fit(for: model).tabModuleIDs == ["timer"])
        #expect(model.visitingModule == nil)
        model.select("shelf")
        #expect(model.visitingModule?.moduleID == "shelf")
    }

    @Test func theNameButtonShowsOnlyWhenChosen() {
        let model = model()
        model.select("keepAwake")
        #expect(model.arrangement.navigation == .tabsAndMenu)
        #expect(!NotchModuleBar.fit(for: model).usesNameButton)
        model.arrangement.navigation = .menu
        #expect(NotchModuleBar.fit(for: model).usesNameButton)
        // The name button names the module already: nothing beside the camera.
        #expect(model.visitingModule == nil)
    }
}
