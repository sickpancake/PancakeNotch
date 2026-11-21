import AppKit
import Foundation
import NotchCore
import Testing
@testable import ModuleShelf

/// Key presses for the keyboard tests (the Shelf's panel hands them to `handleKey`).
enum ShelfKey {
    static let left: UInt16 = 123, right: UInt16 = 124, space: UInt16 = 49, `return`: UInt16 = 36
    static let tab: UInt16 = 48, delete: UInt16 = 51, escape: UInt16 = 53

    static func event(_ code: UInt16, shift: Bool = false, isRepeat: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: isRepeat, keyCode: code
        ))
    }
}

@MainActor
struct ShelfModuleTests {
    func makeModule(_ fixture: ShelfFixture, policy: ShelfSettings.DuplicatePolicy = .ask) -> (ShelfModule, NotchViewModel) {
        let defaults = UserDefaults(suiteName: "ShelfModuleTests-\(UUID().uuidString)")!
        let settings = ShelfSettings(defaults: defaults)
        settings.duplicatePolicy = policy
        let module = ShelfModule(store: fixture.makeStore(), settings: settings)
        let notch = NotchViewModel(
            layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))),
            pointerLocation: { CGPoint(x: 756, y: 300) }
        )
        notch.module = module
        return (module, notch)
    }

    /// Drags the Shelf takes stop below the menu bar unless the user lets Mission Control have the top.
    @Test func keepsDragsBelowTheMenuBarByDefault() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        #expect(module.settings.dragToTop == .openShelf)
        #expect(module.keepsDragsBelowMenuBar)
        module.settings.dragToTop = .allowMissionControl
        #expect(!module.keepsDragsBelowMenuBar)
    }

    @Test func dragToTopIsRemembered() {
        let defaults = UserDefaults(suiteName: "ShelfModuleTests-\(UUID().uuidString)")!
        ShelfSettings(defaults: defaults).dragToTop = .allowMissionControl
        #expect(ShelfSettings(defaults: defaults).dragToTop == .allowMissionControl)
    }

    /// From 15 items the notch rests with the Shelf in its ear, unless that's switched off.
    @Test func restsInCompactFromFifteenItems() async throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        module.offer(try fixture.files(14))
        #expect(notch.restingState == .closed)
        #expect(module.accessibilityStatus == nil)
        module.offer([.text("One more")])
        #expect(notch.restingState == .compact)
        #expect(module.accessibilityStatus == "Shelf, 15 items")

        // The setting is observed: the change arrives on a later main-actor turn.
        module.settings.showsInEars = false
        for _ in 0..<100 where notch.restingState != .closed { try await Task.sleep(for: .milliseconds(20)) }
        #expect(notch.restingState == .closed)
        module.settings.showsInEars = true
        for _ in 0..<100 where notch.restingState != .compact { try await Task.sleep(for: .milliseconds(20)) }
        #expect(notch.restingState == .compact)
    }

    /// A click on empty space clears the selection first; with nothing selected it shrinks the notch.
    @Test func emptySpaceClickDeselectsThenShrinks() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        module.offer(try fixture.files(2))
        notch.open()
        module.selection = [module.store.items[0].id]
        module.backgroundClicked()
        #expect(module.selection.isEmpty)
        #expect(notch.state == .expanded)
        module.backgroundClicked()
        #expect(notch.state == .compact)
    }

    @Test func earLabels() {
        #expect(ShelfModule.earLabel(count: 0) == "Shelf is empty")
        #expect(ShelfModule.earLabel(count: 16) == "Shelf, 16 items")
        #expect(ShelfModule.earLabel(count: 20) == "Shelf is full, 20 items")
    }

    /// A drag that opened the notch early shows the drop zones (with AirDrop, also for text) before
    /// AppKit reports it over the window.
    @Test func approachingDragShowsDropZonesWithAirDrop() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        notch.open()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ShelfModuleTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("Pick up the cake", forType: .string)

        let airDrop = ShelfLayout(notch.layout).airDropZone
        module.dragApproaching(pasteboard, at: CGPoint(x: airDrop.midX, y: airDrop.midY))
        #expect(module.dragCanAirDrop)
        #expect(module.dropZone == .airDrop)
        module.dragApproaching(pasteboard, at: CGPoint(x: airDrop.minX - 100, y: airDrop.midY))
        #expect(module.dropZone == .shelf)
        module.dragEnded()
        #expect(module.dropZone == nil)
    }

    @Test func fullShelfHoldsTheRestAndAddsThemOnceThereIsRoom() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        let inputs = try fixture.files(22)
        module.offer(inputs)
        #expect(module.prompt == .full(pending: Array(inputs.suffix(2))))
        #expect(notch.restingState == .compact)
        #expect(module.holdsOpen)

        module.startChoosing()
        module.selection = Set(module.store.items.prefix(3).map(\.id))
        module.removeChosen()

        #expect(module.prompt == nil)
        #expect(module.store.items.count == 19)
        #expect(module.store.items.filter { $0.displayName == "f20.txt" }.count == 1)
        // Still nearly full (19): the tray stays in the ear.
        #expect(notch.restingState == .compact)
        #expect(!module.holdsOpen)
    }

    @Test func clearingForPendingAddsEverythingWaiting() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer(try fixture.files(25))
        // The first click only asks; nothing is removed yet.
        module.clearForPending()
        #expect(module.confirmingClear)
        #expect(module.store.items.count == 20)
        #expect(module.prompt != nil)
        module.clearForPending()
        #expect(!module.confirmingClear)
        #expect(module.prompt == nil)
        #expect(module.store.items.count == 5)
    }

    @Test func duplicatePromptAndRememberedAnswer() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a"), .text("b")])
        module.offer([.text("a"), .text("c")])
        #expect(module.prompt == .duplicates(inputs: [.text("a"), .text("c")], count: 1))

        module.answerDuplicates(.moveToFront, remember: true)
        #expect(module.prompt == nil)
        #expect(module.store.items.map(\.displayName) == ["c", "a", "b"])
        #expect(module.settings.duplicatePolicy == .moveToFront)
    }

    @Test func dismissingDuplicatesAddsOnlyTheNewOnes() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a")])
        module.offer([.text("a"), .text("new")])
        module.dismissPrompt()
        #expect(module.store.items.map(\.displayName) == ["new", "a"])
    }

    @Test func closingTheNotchDiscardsHeldItems() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        notch.open()
        module.offer(try fixture.files(21))
        notch.close()
        #expect(module.prompt == nil)
        #expect(module.store.items.count == 20)
    }

    @Test func shiftClickSelectsARange() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a"), .text("b"), .text("c"), .text("d")])
        let ids = module.store.items.map(\.id)
        module.click(ids[0], modifiers: [])
        module.click(ids[2], modifiers: .shift)
        #expect(module.selection == Set(ids[0...2]))
        module.click(ids[3], modifiers: .command)
        #expect(module.selection.count == 4)
        #expect(module.targets(for: ids[1]).count == 4)
    }

    @Test func clearAllNeedsASecondClick() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a")])
        module.clearAll()
        #expect(module.store.items.count == 1)
        #expect(module.confirmingClear)
        module.clearAll()
        #expect(module.store.items.isEmpty)
    }

    @Test func dragOutRemovesOnlyWhenAskedTo() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a")])
        let id = try #require(module.store.items.first?.id)
        module.setDraggingOut(true)
        module.dragOutEnded([id], operation: .copy)
        #expect(module.store.items.count == 1)
        #expect(!module.holdsOpen)

        module.settings.removeAfterDragOut = true
        module.dragOutEnded([id], operation: .copy)
        #expect(module.store.items.isEmpty)
    }

    @Test func dragOutIsCopyUnlessMoveIsChosen() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        #expect(module.dragOperations(outside: true) == .copy)
        #expect(module.dragOperations(outside: false) == [])
        module.settings.dragOutMode = .move
        #expect(module.dragOperations(outside: true).contains(.move))
    }
}

@MainActor
struct ShelfModuleReviewTests {
    func makeModule(_ fixture: ShelfFixture) -> (ShelfModule, NotchViewModel) {
        let settings = ShelfSettings(defaults: UserDefaults(suiteName: "ShelfModuleReviewTests-\(UUID().uuidString)")!)
        let module = ShelfModule(store: fixture.makeStore(), settings: settings)
        let notch = NotchViewModel(layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))))
        notch.module = module
        return (module, notch)
    }

    @Test func duplicatesDroppedWhileFullAreNotQueued() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        let inputs = try fixture.files(21)
        module.offer(inputs)
        module.offer([inputs[0], inputs[20]])
        #expect(module.prompt == .full(pending: [inputs[20]]))
    }

    @Test func switchingTheShelfOffDiscardsWaitingItems() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        module.offer(try fixture.files(21))
        notch.module = nil
        #expect(module.prompt == nil)
        #expect(notch.restingState == .closed)
    }

    @Test func shiftArrowGrowsAndShrinksFromTheAnchor() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a"), .text("b"), .text("c")])
        let ids = module.store.items.map(\.id)
        module.click(ids[0], modifiers: [])
        module.moveSelection(by: 1, extending: true)
        module.moveSelection(by: 1, extending: true)
        #expect(module.selection == Set(ids))
        module.moveSelection(by: -1, extending: true)
        #expect(module.selection == Set(ids[0...1]))
    }

    @Test func aCardRaisedWhileClosedOpensTheNotch() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        module.offer([.text("a")])
        module.offer([.text("a")])
        #expect(notch.state == .expanded)
    }

    // MARK: Keyboard cursor

    /// The arrow keys move a cursor the tile row scrolls to, so the selected tile never sits off screen.
    @Test func theCursorFollowsTheArrowKeys() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer(try fixture.files(12))
        let ids = module.store.items.map(\.id)

        func press(_ code: UInt16, shift: Bool = false) throws { #expect(module.handleKey(try ShelfKey.event(code, shift: shift))) }
        for _ in 0..<8 { try press(ShelfKey.right) }
        #expect(module.selectionCursor == ids[7])
        #expect(module.selection == [ids[7]])

        // ⇧ extends from where the selection started; the cursor is the far end.
        try press(ShelfKey.right, shift: true)
        try press(ShelfKey.right, shift: true)
        #expect(module.selection == Set(ids[7...9]))
        #expect(module.selectionCursor == ids[9])
        try press(ShelfKey.left, shift: true)
        #expect(module.selection == Set(ids[7...8]))
        #expect(module.selectionCursor == ids[8])

        // A click moves it too, and the end of the row stops it.
        module.click(ids[2], modifiers: [])
        #expect(module.selectionCursor == ids[2])
        for _ in 0..<20 { try press(ShelfKey.right) }
        #expect(module.selectionCursor == ids[11])

        // A removed tile can't be the cursor.
        module.remove([ids[11]])
        #expect(module.selectionCursor == nil)
    }

    /// Choosing what to remove from the keyboard: arrows move a ring, Space or Return ticks, Delete removes.
    @Test func choosingWorksFromTheKeyboard() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer(try fixture.files(ShelfStore.capacity + 3))
        guard case .full(let waiting) = module.prompt else { Issue.record("expected the full card"); return }
        #expect(waiting.count == 3)
        let ids = module.store.items.map(\.id)

        module.startChoosing()
        #expect(module.isChoosing)
        #expect(module.selectionCursor == ids[0])

        func press(_ code: UInt16, isRepeat: Bool = false) throws {
            #expect(module.handleKey(try ShelfKey.event(code, isRepeat: isRepeat)))
        }
        try press(ShelfKey.right)
        try press(ShelfKey.right)
        #expect(module.selectionCursor == ids[2])
        #expect(module.selection.isEmpty) // moving the ring doesn't tick

        try press(ShelfKey.space)
        #expect(module.selection == [ids[2]])
        try press(ShelfKey.space, isRepeat: true) // a held key doesn't tick and untick
        #expect(module.selection == [ids[2]])
        try press(ShelfKey.right)
        try press(ShelfKey.return)
        #expect(module.selection == [ids[2], ids[3]]) // ticking adds: several can be chosen
        try press(ShelfKey.left)
        try press(ShelfKey.space)
        #expect(module.selection == [ids[3]])

        // The mouse still works and moves the ring with it.
        module.click(ids[9], modifiers: [])
        #expect(module.selection == [ids[3], ids[9]])
        #expect(module.selectionCursor == ids[9])
        #expect(module.isChoosing)

        // Delete removes what's ticked; the waiting items take the room, and what still waits stays a choice.
        try press(ShelfKey.delete)
        #expect(!module.store.items.contains { ids[3] == $0.id || ids[9] == $0.id })
        #expect(module.store.items.count == ShelfStore.capacity)
        guard case .choosing(let rest) = module.prompt else { Issue.record("expected to keep choosing"); return }
        #expect(rest.count == 1)
        // Delete with nothing ticked removes nothing.
        module.selection = []
        let count = module.store.items.count
        try press(ShelfKey.delete)
        #expect(module.store.items.count == count)

        // Esc goes back to the full card, as before.
        try press(ShelfKey.escape)
        #expect(module.prompt == .full(pending: rest))
    }

}
