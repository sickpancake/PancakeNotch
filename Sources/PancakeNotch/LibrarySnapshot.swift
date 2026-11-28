import AppKit
import ModuleAgents
import ModuleKeepAwake
import ModuleNotes
import ModuleNowPlaying
import ModuleShelf
import ModuleTimer
import NotchCore

/// The Library's states for the off-screen notch sheet (`PANCAKENOTCH_SNAPSHOT`, ADR-0045): the page with
/// and without Recently used, a search and one that finds nothing, a refused favorite, switched-off modules,
/// favorites without room, each side and navigation choice, the arrow keys' highlight, and modules shown
/// without a tab (their icon beside the camera).
@MainActor
enum LibrarySnapshot {
    static func models(layout: NotchLayout) -> [NotchViewModel] {
        var models: [NotchViewModel] = []
        models.append(library(layout))
        models.append(library(layout) { model in
            for id in ["shelf", "timer", "notes"] { model.arrangement.noteOpened(id) }
        })
        models.append(library(layout) { model in
            model.libraryFieldClicked()
            model.setLibraryQuery("music")
        })
        models.append(library(layout) { model in
            model.libraryFieldClicked()
            model.setLibraryQuery("zebra")
        })
        models.append(library(layout) { model in
            model.arrangement.favorites = ["nowPlaying", "shelf", "timer", "notes", "agents"]
            model.toggleFavorite("keepAwake")
        })
        models.append(library(layout, modules: [NowPlayingSnapshot.module(), ShelfSnapshot.module(itemCount: 7), NotesSnapshot.module()]))
        models.append(library(layout) { model in
            model.arrangement.favorites = Set(ModuleArrangement.knownModules)
        })
        models.append(library(layout) { model in
            model.arrangement.librarySide = .right
            _ = model.handleKey(arrow(right: true))
            _ = model.handleKey(arrow(right: true))
        })
        models.append(library(layout) { $0.arrangement.navigation = .tabs })
        models.append(library(layout) { $0.arrangement.navigation = .menu })
        // Modules without a tab: their icon beside the camera, their own controls making room.
        // (Favorites from before Agents joined the defaults, so each of these visits.)
        for id in ["keepAwake", "agents", "aiUsage"] {
            models.append(module(layout, id) { $0.arrangement.favorites = ["nowPlaying", "shelf", "timer", "notes"] })
        }
        models.append(module(layout, "notes") { $0.arrangement.favorites = ["nowPlaying", "shelf", "timer"] })
        return models
    }

    /// The Library over every module with something to show, the five default favorites.
    private static func library(_ layout: NotchLayout, modules: [any NotchModule] = HomeSnapshot.live(),
                                setUp: (NotchViewModel) -> Void = { _ in }) -> NotchViewModel {
        let model = base(layout, modules: modules)
        model.toggleLibrary()
        setUp(model)
        return model
    }

    private static func module(_ layout: NotchLayout, _ id: String,
                               setUp: (NotchViewModel) -> Void = { _ in }) -> NotchViewModel {
        let model = base(layout, modules: HomeSnapshot.live())
        setUp(model)
        model.select(id)
        return model
    }

    private static func base(_ layout: NotchLayout, modules: [any NotchModule]) -> NotchViewModel {
        let model = NotchViewModel(layout: layout, state: .expanded, arrangement: ModuleArrangement(), home: HomeSettings())
        model.snapshotClock = HomeSnapshot.clock
        model.openAppPage = { _ in }
        model.openSettings = {}
        model.modules = modules
        return model
    }

    private static func arrow(right: Bool) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: right ? 124 : 123)!
    }
}
