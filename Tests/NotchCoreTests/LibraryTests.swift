import AppKit
import SwiftUI
import Testing
@testable import NotchCore

/// A module with its real name and symbol, for the Library's search and tiles.
@MainActor
final class CatalogModule: NotchModule {
    let moduleID: String
    var status: String?
    var waits = false
    var holds = false
    var opens = 0
    weak var notch: NotchViewModel?

    init(_ id: String, status: String? = nil) {
        moduleID = id
        self.status = status
    }

    var title: String { ModuleCatalog.info(moduleID).title }
    var symbol: String { ModuleCatalog.info(moduleID).symbol }
    var menuStatus: String? { status }
    var waitsForYou: Bool { waits }
    var holdsOpen: Bool { holds }
    func attach(to notch: NotchViewModel?) { self.notch = notch }
    func expandedView(layout: NotchLayout) -> AnyView { AnyView(EmptyView()) }
    func notchDidOpen() { opens += 1 }
}

/// The Library (ADR-0045): the bar's order, search, keys, favorites with a full bar, Recently used and the
/// module menu.
@MainActor
struct LibraryTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    func makeModel(_ ids: [String] = ModuleArrangement.knownModules, keyFocus: Bool = true) -> NotchViewModel {
        let model = NotchViewModel(
            layout: layout,
            state: .closed,
            behavior: NotchBehavior(openDelay: .milliseconds(10), closeDelay: .milliseconds(10)),
            pointerLocation: { CGPoint(x: 756, y: 300) },
            isMissionControlActive: { false }
        )
        model.modules = ids.map { CatalogModule($0) }
        model.hasKeyFocus = { keyFocus }
        return model
    }

    static func key(_ keyCode: UInt16, _ characters: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                         keyCode: keyCode)!
    }

    static let escape = key(53, "\u{1B}")
    static let returnKey = key(36, "\r")
    static let left = key(123)
    static let right = key(124)
    static let down = key(125)

    // MARK: The bar is a map

    @Test func theBarOrderPutsTheLibraryOnItsSide() {
        let model = makeModel(["nowPlaying", "shelf"])
        #expect(model.strip == [.library, .home, .module("nowPlaying"), .module("shelf")])
        model.arrangement.librarySide = .right
        #expect(model.strip == [.home, .library, .module("nowPlaying"), .module("shelf")])
        model.arrangement.navigation = .tabs
        #expect(model.strip == [.module("nowPlaying"), .module("shelf"), .library])
        model.arrangement.librarySide = .left
        #expect(model.strip == [.library, .module("nowPlaying"), .module("shelf")])
        model.arrangement.navigation = .menu
        #expect(model.strip == [.library, .home, .module("nowPlaying"), .module("shelf")])
    }

    @Test func theArrowKeysOnHomeWalkTheBar() {
        let model = makeModel(["nowPlaying", "shelf"])
        model.open()
        model.toggleHome()
        #expect(model.showsHome)
        #expect(model.handleKey(Self.left))
        #expect(model.showsLibrary)
        // An arrow key means the keyboard: the search takes typing.
        #expect(model.library.isTyping)
        #expect(model.handleKey(Self.right))
        #expect(model.handleKey(Self.right))
        #expect(model.currentPlace == .library || model.currentPlace == .home)
    }

    @Test func theLibraryButtonComesAndGoesBackWhereYouWere() {
        let model = makeModel(["nowPlaying", "shelf", "timer"])
        model.open()
        model.select("shelf")
        model.toggleLibrary()
        #expect(model.showsLibrary)
        #expect(!model.showsModule)
        #expect(model.entrance == .reveal)
        #expect(model.library.isTyping)
        model.toggleLibrary()
        #expect(model.currentPlace == .module("shelf"))
    }

    @Test func escClearsTheSearchThenGoesBack() {
        let model = makeModel(["nowPlaying", "shelf"])
        model.open()
        model.select("shelf")
        model.toggleLibrary()
        model.setLibraryQuery("tim")
        #expect(model.handleKey(Self.escape))
        #expect(model.showsLibrary)
        #expect(model.library.query.isEmpty)
        #expect(model.handleKey(Self.escape))
        #expect(model.currentPlace == .module("shelf"))
    }

    @Test func escWithNowhereToGoBackClosesTheNotch() {
        let model = makeModel(["nowPlaying"])
        model.arrangement.navigation = .tabs
        model.open()
        model.toggleLibrary()
        model.modules = []
        #expect(model.showsLibrary)
        #expect(model.handleKey(Self.escape))
        #expect(model.state != .expanded)
    }

    @Test func leavingTheLibraryWithASearchTypedLetsTheNotchClose() async throws {
        let model = makeModel(["nowPlaying", "shelf", "timer"])
        model.open()
        model.toggleLibrary()
        model.setLibraryQuery("tim")
        #expect(model.isHeld)
        // A bar tab, not Esc: the search goes with the Library, and with it the hold.
        model.select("shelf")
        #expect(!model.isHeld)
        // The close is scheduled 10 ms out; give a busy test run up to two seconds to get to it.
        for _ in 0..<40 where model.state == .expanded { try await Task.sleep(for: .milliseconds(50)) }
        #expect(model.state != .expanded)
    }

    @Test func theNameButtonNamesTheLibraryWhileItShows() {
        let model = makeModel(["nowPlaying", "shelf"])
        model.arrangement.navigation = .menu
        model.open()
        model.select("shelf")
        #expect(NotchModuleBar.menuTitle(for: model) == ModuleCatalog.info("shelf").title)
        model.toggleLibrary()
        #expect(NotchModuleBar.menuTitle(for: model) == "Library")
        #expect(NotchModuleBar.menuSymbol(for: model) == LibrarySymbol.name)
        model.toggleHome()
        #expect(NotchModuleBar.menuSymbol(for: model) == HomeSymbol.name)
    }

    @Test func aSwipeArrivesWithoutTakingTheKeyboardFromAnotherApp() {
        let model = makeModel(["nowPlaying", "shelf"], keyFocus: false)
        model.open()
        model.toggleHome()
        model.showAdjacentPlace(forward: false)
        #expect(model.showsLibrary)
        #expect(!model.library.isTyping)
        model.libraryFieldClicked()
        #expect(model.library.isTyping)
    }

    @Test func aModuleThatHoldsTheNotchKeepsTheLibraryAway() {
        let model = makeModel(["nowPlaying", "shelf"])
        model.open()
        model.select("shelf")
        (model.modules[1] as? CatalogModule)?.holds = true
        model.toggleLibrary()
        #expect(!model.showsLibrary)
        #expect(!model.showsModuleBar)
    }

    @Test func closingTheNotchClearsTheSearch() {
        let model = makeModel()
        model.open()
        model.toggleLibrary()
        model.setLibraryQuery("music")
        model.close()
        #expect(!model.showsLibrary)
        #expect(model.library.query.isEmpty)
        #expect(model.library.highlight == nil)
    }

    /// The model's ExclusivePlace rule (verify-home-notch): losing the last module while the Library shows
    /// doesn't put Home over it.
    @Test func losingEveryModuleKeepsTheLibraryAlone() {
        let model = makeModel(["nowPlaying", "shelf"])
        model.open()
        model.toggleLibrary()
        model.modules = []
        #expect(model.showsLibrary)
        #expect(!model.showsHome)
        // Home over a module comes back as before.
        let other = makeModel(["nowPlaying"])
        other.open()
        other.modules = []
        #expect(other.showsHome)
        #expect(!other.showsLibrary)
    }

    @Test func homeFromTheLibraryOpensOnItsFirstPage() {
        let model = makeModel(["nowPlaying", "shelf"])
        model.open()
        model.toggleLibrary()
        model.toggleHome()
        #expect(model.showsHome)
        #expect(!model.showsLibrary)
        #expect(model.homePage == 0)
    }

    // MARK: Search

    @Test func searchFindsNamesFirstThenOtherWords() {
        let model = makeModel()
        model.open()
        model.toggleLibrary()
        model.setLibraryQuery("music")
        #expect(model.libraryResults.map(\.id) == ["nowPlaying"])
        model.setLibraryQuery("files")
        #expect(model.libraryResults.first?.id == "shelf")
        model.setLibraryQuery("coffee")
        #expect(model.libraryResults.map(\.id) == ["keepAwake"])
        model.setLibraryQuery("todo")
        #expect(model.libraryResults.map(\.id) == ["notes"])
        model.setLibraryQuery("AI")
        #expect(Set(model.libraryResults.map(\.id)).isSuperset(of: ["agents", "aiUsage"]))
        // "ai" starts the name "AI Usage": it comes before Agents, found by a word.
        #expect(model.libraryResults.first?.id == "aiUsage")
    }

    @Test func searchIgnoresCaseAndAccentsAndMatchesTheStartOfWords() {
        #expect(SearchWords.matches("NÓTES", in: ["Notes"]))
        #expect(SearchWords.matches("play", in: ["Now Playing"]))
        #expect(!SearchWords.matches("laying", in: ["Now Playing"]))
        #expect(SearchWords.matches("", in: ["Timer"]))
    }

    @Test func typingHighlightsTheBestMatchAndReturnOpensIt() {
        let model = makeModel()
        model.open()
        model.toggleLibrary()
        model.setLibraryQuery("tim")
        #expect(model.library.highlight == "timer")
        model.libraryTileAnchors["timer"] = UnitPoint(x: 0.7, y: 0.6)
        #expect(model.handleKey(Self.returnKey))
        #expect(model.currentPlace == .module("timer"))
        #expect(model.entrance == .grow(from: UnitPoint(x: 0.7, y: 0.6)))
    }

    @Test func aSearchThatFindsNothingSaysSo() {
        let model = makeModel()
        model.open()
        model.toggleLibrary()
        model.setLibraryQuery("zzz")
        #expect(model.libraryResults.isEmpty)
        #expect(model.library.highlight == nil)
        #expect(!model.handleKey(Self.returnKey))
        #expect(model.libraryRecents.isEmpty)
    }

    @Test func theArrowsWalkTheTilesAndLeaveAtTheEnds() {
        let model = makeModel(["nowPlaying", "shelf", "timer"])
        // A practice notch lists only its own three modules: less than a row.
        model.homeLeavesOutMissing = true
        model.open()
        model.toggleLibrary()
        let ids = model.libraryResults.map(\.id)
        #expect(ids.count == 3)
        #expect(model.handleKey(Self.right))
        #expect(model.library.highlight == ids.first)
        #expect(model.handleKey(Self.down))
        // Fewer tiles than a row: ↓ has nowhere to go.
        #expect(model.library.highlight == ids.first)
        for _ in 1..<ids.count { _ = model.handleKey(Self.right) }
        #expect(model.library.highlight == ids.last)
        // Past the last tile, → goes on along the bar: Home.
        #expect(model.handleKey(Self.right))
        #expect(model.showsHome)
    }

    @Test func whileSearchingTheArrowsStayAmongTheMatches() {
        let model = makeModel()
        model.open()
        model.toggleLibrary()
        model.setLibraryQuery("tim")
        let matches = model.libraryResults.map(\.id)
        #expect(!matches.isEmpty)
        for _ in 0...matches.count { #expect(model.handleKey(Self.right)) }
        #expect(model.showsLibrary)
        #expect(model.library.query == "tim")
        #expect(model.library.highlight == matches.last)
        for _ in 0...matches.count { #expect(model.handleKey(Self.left)) }
        #expect(model.showsLibrary)
        #expect(model.library.highlight == matches.first)
        // Nothing found: the arrows still don't leave.
        model.setLibraryQuery("zebra")
        #expect(model.handleKey(Self.right))
        #expect(model.handleKey(Self.left))
        #expect(model.showsLibrary)
        #expect(model.library.query == "zebra")
    }

    // MARK: Favorites

    @Test func newInstallsStartWithTheEverydayFour() {
        let defaults = UserDefaults(suiteName: "LibraryTests.defaults.\(UUID().uuidString)")!
        #expect(ModuleArrangement(defaults: defaults).favorites == ["nowPlaying", "shelf", "timer", "notes"])
    }

    @Test func aFullBarRefusesAnotherFavoriteAndSaysWhy() {
        let model = makeModel()
        model.open()
        model.arrangement.favorites = ["nowPlaying", "shelf", "timer", "notes", "agents"]
        #expect(model.favoriteCapacity == 5)
        #expect(!model.canAddFavorite)
        #expect(!model.toggleFavorite("keepAwake"))
        #expect(!model.arrangement.isFavorite("keepAwake"))
        #expect(model.library.note == .barFull)
        #expect(model.toggleFavorite("agents"))
        #expect(model.canAddFavorite)
        #expect(model.toggleFavorite("keepAwake"))
        #expect(model.arrangement.isFavorite("keepAwake"))
    }

    @Test func savedFavoritesPastTheRoomStaySavedAndTheLibrarySaysNoRoom() {
        let model = makeModel()
        model.arrangement.favorites = Set(ModuleArrangement.knownModules)
        #expect(model.barTabIDs.count == model.favoriteCapacity)
        let without = model.libraryEntries.filter(\.isFavoriteWithoutRoom).map(\.id)
        #expect(without.count == ModuleArrangement.knownModules.count - model.favoriteCapacity)
        #expect(Set(without).isDisjoint(with: model.barTabIDs))
        #expect(model.arrangement.favorites.count == ModuleArrangement.knownModules.count)
    }

    @Test func practiceNotchesNeitherEditFavoritesNorListOtherModules() {
        let model = makeModel(["nowPlaying", "shelf"])
        model.homeLeavesOutMissing = true
        #expect(!model.editsFavorites)
        #expect(model.libraryEntries.map(\.id) == ["nowPlaying", "shelf"])
        model.homeLeavesOutMissing = false
        #expect(model.editsFavorites)
        #expect(model.libraryEntries.count == ModuleArrangement.knownModules.count)
        #expect(model.libraryEntries.first { $0.id == "notes" }?.isOn == false)
    }

    // MARK: Switched-off modules and settings

    @Test func aSwitchedOffTileOpensItsCardInTheAppWindow() {
        let model = makeModel(["nowPlaying", "shelf"])
        var asked: [String] = []
        model.openAppPage = { page in if case .module(let id) = page { asked.append(id) } }
        model.open()
        model.toggleLibrary()
        model.openFromLibrary("notes")
        #expect(asked == ["notes"])
        #expect(model.showsLibrary)
        model.openModuleCard("shelf")
        #expect(asked == ["notes", "shelf"])
    }

    // MARK: Recently used

    @Test func recentlyUsedListsTheLastThreeOpenedNewestFirst() {
        let model = makeModel()
        model.open()
        for id in ["shelf", "timer", "notes", "agents"] { model.select(id) }
        model.toggleLibrary()
        #expect(model.libraryRecents.map(\.id) == ["agents", "notes", "timer"])
        model.setLibraryQuery("s")
        #expect(model.libraryRecents.isEmpty)
    }

    @Test func everyWayIntoAModuleCountsAsRecentlyUsed() {
        let model = makeModel(["nowPlaying", "shelf", "timer"])
        model.open()
        model.select("shelf")                  // a tab
        model.toggleHome()
        model.showAdjacentPlace(forward: true) // a swipe from Home
        #expect(model.arrangement.recent.first == "nowPlaying")
        model.select("timer")
        model.toggleHome()
        model.select("shelf")                  // a tab while Home shows
        model.toggleHome()
        model.toggleHome()                     // Home again: back to the module behind it
        #expect(model.currentPlace == .module("shelf"))
        model.select("timer")
        model.toggleHome()
        model.toggleHome()
        #expect(model.arrangement.recent.prefix(3) == ["timer", "shelf", "nowPlaying"])
    }

    @Test func recentlyUsedSkipsModulesThatAreOff() {
        let model = makeModel(["nowPlaying", "shelf"])
        model.arrangement.noteOpened("notes")
        model.arrangement.noteOpened("shelf")
        #expect(model.libraryRecents.map(\.id) == ["shelf"])
    }

    // MARK: Swiping between Home and the Library

    @Test func aSwipeFollowsTheFingersAndAFlickFinishesIt() {
        let model = makeModel(["nowPlaying", "shelf"])
        model.open()
        model.toggleHome()
        // Fingers move right on Home: the Library (on the left) slides in, following them.
        model.handleHubPreciseScroll(phase: .began, deltaY: 0, fingersX: 0, time: 0)
        model.handleHubPreciseScroll(phase: .changed, deltaY: 0, fingersX: 40, time: 0.016)
        let position = model.hubPosition
        #expect(position != nil)
        #expect((position ?? 1) < 1)
        #expect(model.showsHome)
        model.handleHubPreciseScroll(phase: .changed, deltaY: 0, fingersX: 30, time: 0.032)
        model.handleHubPreciseScroll(phase: .ended, deltaY: 0, fingersX: 0, time: 0.04)
        #expect(model.showsLibrary)
    }

    @Test func aShortSlowSwipeStaysPut() {
        let model = makeModel(["nowPlaying", "shelf"])
        model.open()
        model.toggleHome()
        model.handleHubPreciseScroll(phase: .began, deltaY: 0, fingersX: 0, time: 0)
        model.handleHubPreciseScroll(phase: .changed, deltaY: 0, fingersX: 8, time: 0.1)
        model.handleHubPreciseScroll(phase: .ended, deltaY: 0, fingersX: 0, time: 0.6)
        #expect(model.showsHome)
    }

    // MARK: The module menu

    @Test func theMenuOffersOpenFavoritesAndSettings() {
        let model = makeModel()
        model.openAppPage = { _ in }
        model.open()
        model.select("shelf")
        model.arrangement.favorites = ["shelf"]
        let titles = ModuleMenu.make(model: model, moduleID: "timer", open: {})?.items.map(\.title) ?? []
        #expect(titles.contains(LibraryText.open))
        #expect(titles.contains(LibraryText.addFavorite))
        #expect(titles.contains(LibraryText.settings))
        // The module showing has no Open.
        let current = ModuleMenu.make(model: model, moduleID: "shelf", open: {})?.items.map(\.title) ?? []
        #expect(!current.contains(LibraryText.open))
        #expect(current.contains(LibraryText.removeFavorite))
    }

    @Test func theMenuRefusesAFavoriteInPlaceWhenTheBarIsFull() {
        let model = makeModel()
        model.open()
        model.arrangement.favorites = ["nowPlaying", "shelf", "timer", "notes", "agents"]
        let items = ModuleMenu.make(model: model, moduleID: "keepAwake", open: {})?.items ?? []
        let add = items.first { $0.title == LibraryText.addFavorite }
        #expect(add?.isEnabled == false)
        #expect(items.contains { $0.title == LibraryText.barFull })
    }

    @Test func aSwitchedOffModuleOnlyOffersToTurnItOn() {
        let model = makeModel(["nowPlaying"])
        model.openAppPage = { _ in }
        let titles = ModuleMenu.make(model: model, moduleID: "notes", open: {})?.items.map(\.title) ?? []
        #expect(titles == [LibraryText.turnOn])
    }
}
