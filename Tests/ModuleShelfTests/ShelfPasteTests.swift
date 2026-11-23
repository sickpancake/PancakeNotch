import AppKit
import Foundation
import NotchCore
import Testing
@testable import ModuleShelf

/// ⌘V in the open Shelf: the clipboard takes the same path as a drop (issue #111).
@MainActor
struct ShelfPasteTests {
    /// A Shelf that pastes from a private clipboard, never the real one.
    func makeModule(_ fixture: ShelfFixture, items: [NSPasteboardItem] = [], policy: ShelfSettings.DuplicatePolicy = .ask)
        -> (ShelfModule, NSPasteboard) {
        let defaults = UserDefaults(suiteName: "ShelfPasteTests-\(UUID().uuidString)")!
        let settings = ShelfSettings(defaults: defaults)
        settings.duplicatePolicy = policy
        let module = ShelfModule(store: fixture.makeStore(), settings: settings)
        let notch = NotchViewModel(
            layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))),
            pointerLocation: { CGPoint(x: 756, y: 300) }
        )
        notch.module = module
        let board = NSPasteboard(name: NSPasteboard.Name("ShelfPasteTests-\(UUID().uuidString)"))
        board.clearContents()
        board.writeObjects(items)
        module.pasteboardForPaste = { board }
        return (module, board)
    }

    func item(_ values: [(NSPasteboard.PasteboardType, String)]) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for (type, value) in values { item.setString(value, forType: type) }
        return item
    }

    func commandKey(_ character: String, shift: Bool = false) throws -> NSEvent {
        let codes = ["v": UInt16(9), "c": 8]
        return try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: shift ? [.command, .shift] : [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character,
            isARepeat: false, keyCode: codes[character] ?? 0
        ))
    }

    @Test func pastesAFileAsAReferenceAndSelectsIt() throws {
        let fixture = try ShelfFixture()
        let file = try fixture.file("notes.txt")
        let (module, _) = makeModule(fixture, items: [item([(.fileURL, file.absoluteString)])])

        #expect(module.handleKey(try commandKey("v")))
        let pasted = try #require(module.store.items.first)
        #expect(module.store.items.count == 1)
        #expect(pasted.isFile && !pasted.isOwnedFile)
        #expect(pasted.displayName == "notes.txt")
        #expect(module.selection == [pasted.id])
        #expect(module.pasteFeedback == .pasted(count: 1))
    }

    @Test func pastesAPictureAsAnOwnedImageFile() throws {
        let fixture = try ShelfFixture()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 9, 9, 9])
        let image = NSPasteboardItem()
        image.setData(bytes, forType: .png)
        let (module, _) = makeModule(fixture, items: [image])

        #expect(module.paste())
        let pasted = try #require(module.store.items.first)
        #expect(pasted.isOwnedFile)
        let url = try #require(pasted.fileURL)
        #expect(url.pathExtension == "png")
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func pastesTextAndLinksAsTheirOwnKinds() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture, items: [
            item([(.string, "Pick up the parcel")]),
            item([(.URL, "https://github.com/sickpancake"), (.string, "https://github.com/sickpancake")]),
        ])

        #expect(module.paste())
        let kinds = module.store.items.map(\.kind)
        #expect(kinds.count == 2)
        #expect(kinds.contains(.text("Pick up the parcel")))
        #expect(kinds.contains(.link(URL(string: "https://github.com/sickpancake")!)))
        #expect(module.selection.count == 2)
        #expect(module.pasteFeedback == .pasted(count: 2))
    }

    @Test func anEmptyOrForeignClipboardSaysNothingToPaste() throws {
        let fixture = try ShelfFixture()
        let (module, board) = makeModule(fixture)
        #expect(module.paste())
        #expect(module.pasteFeedback == .nothing)

        board.clearContents()
        let other = NSPasteboardItem()
        other.setData(Data([1]), forType: NSPasteboard.PasteboardType("com.example.private"))
        board.writeObjects([other])
        module.pasteFeedback = nil
        #expect(module.paste())
        #expect(module.pasteFeedback == .nothing)

        board.clearContents()
        board.writeObjects([item([(.string, "   \n")])])
        module.pasteFeedback = nil
        #expect(module.paste())
        #expect(module.pasteFeedback == .nothing)
        #expect(module.store.items.isEmpty)
    }

    /// Switched off, ⌘V isn't the Shelf's: the key goes back to the notch.
    @Test func switchedOffLeavesTheKeyAlone() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture, items: [item([(.string, "Hi")])])
        module.settings.pasteEnabled = false
        #expect(!module.handleKey(try commandKey("v")))
        #expect(!module.paste())
        #expect(module.store.items.isEmpty)

        module.settings.pasteEnabled = true
        #expect(module.handleKey(try commandKey("v")))
        #expect(module.store.items.count == 1)
    }

    @Test func settingIsRemembered() {
        let defaults = UserDefaults(suiteName: "ShelfPasteTests-\(UUID().uuidString)")!
        #expect(ShelfSettings(defaults: defaults).pasteEnabled)
        ShelfSettings(defaults: defaults).pasteEnabled = false
        #expect(!ShelfSettings(defaults: defaults).pasteEnabled)
    }

    /// ⇧⌘V isn't paste.
    @Test func shiftCommandVIsNotPaste() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture, items: [item([(.string, "Hi")])])
        #expect(!module.handleKey(try commandKey("v", shift: true)))
        #expect(module.store.items.isEmpty)
    }

    /// Pasting twice asks about the duplicate like a drop does, and says nothing until it's answered.
    @Test func pastingAgainAsksAboutDuplicates() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture, items: [item([(.string, "Same text")])])
        module.paste()
        #expect(module.pasteFeedback == .pasted(count: 1))
        module.paste()
        // The card takes over: the first paste's "1 item pasted" doesn't stay above it.
        #expect(module.prompt == .duplicates(inputs: [.text("Same text")], count: 1))
        #expect(module.pasteFeedback == nil)
        #expect(module.store.items.count == 1)
    }

    /// With "Move to front", pasting what's already there selects it at the front.
    @Test func movedToFrontIsSelected() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture, items: [item([(.string, "Old")])], policy: .moveToFront)
        module.paste()
        module.offer([.text("Newer")])
        module.selection = []
        module.paste()
        #expect(module.store.items.first?.kind == .text("Old"))
        #expect(module.selection == [module.store.items[0].id])
        #expect(module.pasteFeedback == .pasted(count: 1))
    }

    /// A copied file that was deleted before the paste adds nothing, so it doesn't claim success.
    @Test func aMissingFileSaysNothingToPaste() throws {
        let fixture = try ShelfFixture()
        let gone = fixture.root.appendingPathComponent("gone.txt")
        let (module, _) = makeModule(fixture, items: [item([(.fileURL, gone.absoluteString)])])
        module.paste()
        #expect(module.store.items.isEmpty)
        #expect(module.pasteFeedback == .nothing)
    }

    /// A full Shelf holds the pasted items back, like dropped ones.
    @Test func aFullShelfHoldsPastedItems() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture, items: [item([(.string, "One too many")])])
        module.offer(try fixture.files(ShelfStore.capacity))
        module.paste()
        #expect(module.prompt == .full(pending: [.text("One too many")]))
        #expect(module.pasteFeedback == nil)
    }

    /// Text that Notes takes becomes a note instead of a Shelf item.
    @Test func notesCanTakePastedText() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture, items: [item([(.string, "A note")])])
        var noted: [ShelfInput] = []
        module.takesNotes = { inputs in
            noted = inputs
            return []
        }
        module.paste()
        #expect(noted == [.text("A note")])
        #expect(module.store.items.isEmpty)
        #expect(module.notedCount == 1)
    }

    /// While an item is open, ⌘V belongs to its editor, not the tiles.
    @Test func anOpenItemKeepsCommandVForItsEditor() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture, items: [item([(.string, "Pasted")])])
        module.offer([.text("Open me")])
        module.openDetail(module.store.items[0].id)
        _ = module.handleKey(try commandKey("v"))
        #expect(module.store.items.count == 1)
    }

    @Test func clipboardPromisesAreSkippedForImageData() throws {
        let fixture = try ShelfFixture()
        let image = NSPasteboardItem()
        image.setData(Data([1, 2, 3]), forType: .tiff)
        let board = NSPasteboard(name: NSPasteboard.Name("ShelfPasteTests-\(UUID().uuidString)"))
        board.clearContents()
        board.writeObjects([image])
        let drop = ShelfDropReader.read(board, readsPromises: false) { try fixture.makeStore().newFilesFolder() }
        #expect(drop.promises.isEmpty)
        #expect(drop.inputs.count == 1)
    }
}
