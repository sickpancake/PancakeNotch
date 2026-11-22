import AppKit
import Foundation
import NotchCore
import Testing
@testable import ModuleShelf

/// Pinning (issue #109): pinned items sit first and are never cleared automatically.
@MainActor
struct ShelfPinStoreTests {
    private func names(_ store: ShelfStore) -> [String] { store.items.map(\.displayName) }

    private func id(_ store: ShelfStore, _ name: String) throws -> UUID {
        try #require(store.items.first { $0.displayName == name }?.id)
    }

    @Test func pinnedItemsMoveToTheFrontAndStayThere() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        store.add([.text("c"), .text("b"), .text("a")], duplicates: .ask)
        #expect(names(store) == ["c", "b", "a"])

        store.setPinned([try id(store, "a")], true)
        #expect(names(store) == ["a", "c", "b"])
        #expect(store.pinnedCount == 1)

        // New drops land after the pinned items, newest first.
        store.add([.text("new")], duplicates: .ask)
        #expect(names(store) == ["a", "new", "c", "b"])

        // A second pin keeps the line's order among pinned items.
        store.setPinned([try id(store, "b")], true)
        #expect(names(store) == ["a", "b", "new", "c"])
    }

    @Test func movingADuplicateToTheFrontStaysBehindPinnedItems() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        store.add([.text("old"), .text("pinned")], duplicates: .ask)
        store.setPinned([try id(store, "pinned")], true)
        store.add([.text("old")], duplicates: .moveToFront)
        #expect(names(store) == ["pinned", "old"])
    }

    @Test func unpinningGoesBackToTheFrontOfTheRest() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        store.add([.text("a"), .text("b"), .text("c")], duplicates: .ask)
        store.setPinned([try id(store, "c"), try id(store, "b")], true)
        #expect(names(store) == ["b", "c", "a"])
        store.setPinned([try id(store, "b")], false)
        #expect(names(store) == ["c", "b", "a"])
        #expect(store.items.map(\.isPinned) == [true, false, false])
    }

    @Test func pinsAreSavedAndOldShelvesStillLoad() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        store.add([.text("a"), .text("b")], duplicates: .ask)
        store.setPinned([try id(store, "b")], true)
        let reloaded = fixture.makeStore()
        #expect(reloaded.items == store.items)
        #expect(reloaded.items.first?.isPinned == true)

        // A Shelf saved before pinning existed has no "isPinned": its items load unpinned.
        let legacy = #"[{"id":"\#(UUID().uuidString)","kind":{"text":{"_0":"old note"}},"addedAt":0}]"#
        try Data(legacy.utf8).write(to: fixture.shelfDirectory.appending(path: "items.json"))
        let old = fixture.makeStore()
        #expect(old.items.map(\.displayName) == ["old note"])
        #expect(old.items.first?.isPinned == false)
    }

    @Test func unpinnedItemsAreSavedWithoutThePinKey() throws {
        let item = ShelfItem(kind: .text("x"), addedAt: Date(timeIntervalSince1970: 0))
        let json = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        #expect(!json.contains("isPinned"))
        var pinned = item
        pinned.isPinned = true
        let decoded = try JSONDecoder().decode(ShelfItem.self, from: try JSONEncoder().encode(pinned))
        #expect(decoded == pinned)
    }

    @Test func autoClearKeepsPinnedItems() async throws {
        let fixture = try ShelfFixture()
        let old = fixture.makeStore()
        old.add([.text("old"), .text("old pinned")], duplicates: .ask)
        old.setPinned([try id(old, "old pinned")], true)
        fixture.clock += 2 * 86_400
        let store = fixture.makeStore()
        store.add([.text("fresh")], duplicates: .ask)

        await store.prune(maxAge: 86_400)
        #expect(names(store) == ["old pinned", "fresh"])
    }

    @Test func clearCanKeepPinnedItems() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        store.add([.text("a"), .text("b")], duplicates: .ask)
        store.setPinned([try id(store, "a")], true)
        store.clear(keepingPinned: true)
        #expect(names(store) == ["a"])
        store.clear()
        #expect(store.items.isEmpty)
    }

    @Test func restoringPinsPutsTheOrderBack() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        store.add([.text("a"), .text("b"), .text("c")], duplicates: .ask)
        let order = store.items.map(\.id)
        let c = try id(store, "c")
        store.setPinned([c], true)
        store.add([.text("new")], duplicates: .ask)
        store.restorePins([c: false], order: order)
        // The item added since stays in front; the rest is back in its old line.
        #expect(names(store) == ["new", "a", "b", "c"])
        #expect(store.pinnedCount == 0)
    }
}

@MainActor
struct ShelfPinModuleTests {
    func makeModule(_ fixture: ShelfFixture) -> (ShelfModule, NotchViewModel) {
        let settings = ShelfSettings(defaults: UserDefaults(suiteName: "ShelfPinModuleTests-\(UUID().uuidString)")!)
        let module = ShelfModule(store: fixture.makeStore(), settings: settings)
        let notch = NotchViewModel(layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))))
        notch.module = module
        return (module, notch)
    }

    private func item(_ module: ShelfModule, _ name: String) throws -> ShelfItem {
        try #require(module.store.items.first { $0.displayName == name })
    }

    @Test func togglePinPinsUnlessAllArePinned() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a"), .text("b")])
        module.togglePin([try item(module, "b")])
        let pinnedB = try item(module, "b")
        #expect(pinnedB.isPinned)
        // A mix pins the rest…
        module.togglePin(module.store.items)
        #expect(module.store.pinnedCount == module.store.items.count)
        // …and all pinned unpins them all.
        module.togglePin(module.store.items)
        #expect(module.store.pinnedCount == 0)
    }

    @Test func undoPutsPinAndPlaceBack() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a"), .text("b"), .text("c")])
        let before = module.store.items.map(\.displayName)
        module.togglePin([try item(module, "a")])
        #expect(module.store.items.first?.displayName == "a")
        #expect(module.pinNote?.pinned == true)
        module.undoPin()
        #expect(module.store.items.map(\.displayName) == before)
        #expect(module.store.pinnedCount == 0)
        #expect(module.pinNote == nil)
    }

    @Test func undoAfterUnpinningRestoresTheOldPlaceAmongPinnedItems() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a"), .text("b"), .text("c")])
        module.store.setPinned(module.store.items.map(\.id), true)
        let before = module.store.items.map(\.displayName)
        module.togglePin([try item(module, before[0])])
        #expect(module.store.items.map(\.displayName) == [before[1], before[2], before[0]])
        module.undoPin()
        #expect(module.store.items.map(\.displayName) == before)
        #expect(module.store.pinnedCount == module.store.items.count)
    }

    @Test func thePinNoteGoesWhenTheNotchCloses() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a")])
        module.togglePin(module.store.items)
        #expect(module.pinNote != nil)
        module.notchDidClose()
        #expect(module.pinNote == nil)
    }

    @Test func pressingPPinsTheSelection() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a"), .text("b")])
        let b = try item(module, "b")
        module.click(b.id, modifiers: [])
        #expect(try module.handleKey(ShelfKey.event(35)))
        let pressedB = try item(module, "b")
        #expect(pressedB.isPinned)
        #expect(try module.handleKey(ShelfKey.event(35)))
        #expect(module.store.pinnedCount == 0)
        // Nothing selected: P isn't the Shelf's.
        module.selection = []
        #expect(try !module.handleKey(ShelfKey.event(35)))
    }

    @Test func clearAllKeepsPinnedItemsUnlessTurnedOff() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a"), .text("b"), .text("c")])
        module.togglePin([try item(module, "a")])
        #expect(module.settings.clearAllKeepsPinned)
        #expect(module.clearableCount == 2)
        module.clearAll()
        module.clearAll()
        #expect(module.store.items.map(\.displayName) == ["a"])
        #expect(module.clearableCount == 0)

        module.settings.clearAllKeepsPinned = false
        #expect(module.clearableCount == 1)
        module.clearAll()
        module.clearAll()
        #expect(module.store.items.isEmpty)
    }

    @Test func clearAllKeepsPinnedIsRemembered() {
        let defaults = UserDefaults(suiteName: "ShelfPinModuleTests-\(UUID().uuidString)")!
        ShelfSettings(defaults: defaults).clearAllKeepsPinned = false
        #expect(!ShelfSettings(defaults: defaults).clearAllKeepsPinned)
    }

    @Test func draggingOutNeverRemovesPinnedItems() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.settings.removeAfterDragOut = true
        module.offer([.text("a"), .text("b")])
        module.togglePin([try item(module, "a")])
        module.setDraggingOut(true)
        module.dragOutEnded(module.store.items.map(\.id), operation: .copy)
        #expect(module.store.items.map(\.displayName) == ["a"])
    }

    @Test func aFullShelfOfPinnedItemsCanOnlyBeChosenFrom() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer(try fixture.files(20))
        module.store.setPinned(module.store.items.map(\.id), true)
        module.offer([.text("waiting")])
        #expect(module.prompt == .full(pending: [.text("waiting")]))
        // Clear all would keep everything: nothing to clear, so the card offers only choosing.
        #expect(module.clearableCount == 0)
        module.startChoosing()
        module.click(module.store.items[0].id, modifiers: [])
        module.removeChosen()
        #expect(module.store.items.contains { $0.displayName == "waiting" })
    }

    @Test func menuOffersPinThenUnpin() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a"), .text("b")])
        let items = module.store.items
        let titles = { ShelfMenu.entries(for: $0, module: module, anchor: NSView()).map(\.title) }
        #expect(titles([items[0]]).contains("Pin"))
        #expect(titles(items).contains("Pin 2 Items"))
        module.togglePin(items)
        #expect(titles(module.store.items).contains("Unpin 2 Items"))
        // Choosing Pin from the menu pins it.
        let pin = try #require(ShelfMenu.entries(for: [module.store.items[0]], module: module, anchor: NSView()).first { $0.title == "Unpin" })
        pin.action()
        #expect(module.store.pinnedCount == 1)
    }

    @Test func keepTextSaysHowLongAnItemStays() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a")])
        let a = try item(module, "a")
        #expect(module.keepText(for: a, now: fixture.clock) == nil)
        module.settings.autoClear = .week
        #expect(module.keepText(for: a, now: fixture.clock.addingTimeInterval(2 * 86_400))?.contains("5 days") == true)
        #expect(module.keepText(for: a, now: fixture.clock.addingTimeInterval(6.5 * 86_400))?.contains("within a day") == true)
        module.togglePin([a])
        let pinnedA = try item(module, "a")
        #expect(module.keepText(for: pinnedA)?.contains("Pinned") == true)
    }
}
