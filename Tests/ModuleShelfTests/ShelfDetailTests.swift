import AppKit
import NotchCore
import Testing
@testable import ModuleShelf

/// The tall notch: one click (or Space) shows an item, text and links can be edited.
@MainActor
struct ShelfDetailTests {
    func makeModule(_ fixture: ShelfFixture) -> (ShelfModule, NotchViewModel) {
        let settings = ShelfSettings(defaults: UserDefaults(suiteName: "ShelfDetailTests-\(UUID().uuidString)")!)
        let module = ShelfModule(store: fixture.makeStore(), settings: settings)
        let notch = NotchViewModel(
            layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))),
            state: .expanded,
            pointerLocation: { CGPoint(x: 756, y: 300) }
        )
        notch.module = module
        return (module, notch)
    }

    static func key(_ characters: String, code: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code
        ))
    }

    @Test func spaceShowsTheSelectionTallAndEscapeGoesBack() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        module.offer([.text("hello"), .text("world")])
        let id = try #require(module.store.items.last?.id)
        module.click(id, modifiers: [])

        #expect(module.handleKey(try Self.key(" ", code: 49)))
        #expect(module.detailID == id)
        #expect(notch.layout.isTall)
        #expect(module.holdsOpen)

        // Keys other than Esc belong to the editor.
        #expect(!module.handleKey(try Self.key(" ", code: 49)))
        #expect(!module.handleKey(try Self.key("\u{7f}", code: 51)))
        #expect(module.store.items.count == 2)

        #expect(module.handleKey(try Self.key("\u{1b}", code: 53)))
        #expect(module.detailID == nil)
        #expect(!notch.layout.isTall)
        #expect(!module.holdsOpen)
        #expect(notch.state == .expanded)
    }

    @Test func editingTextSavesAndEmptyTextIsRemovedOnLeaving() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("one"), .text("two")])
        let first = try #require(module.store.items.first?.id)
        let second = try #require(module.store.items.last?.id)

        module.openDetail(first)
        module.editText(first, "two, edited")
        module.closeDetail()
        #expect(fixture.makeStore().items.first?.kind == .text("two, edited"))

        module.openDetail(second)
        module.editText(second, "  \n")
        #expect(module.store.items.count == 2)
        module.closeDetail()
        #expect(module.store.items.map(\.id) == [first])
    }

    @Test func linksKeepOnlyValidAddresses() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.link(URL(string: "https://example.com")!)])
        let id = try #require(module.store.items.first?.id)
        module.openDetail(id)

        #expect(module.editLink(id, "apple.com/mac"))
        #expect(module.store.items.first?.kind == .link(URL(string: "https://apple.com/mac")!))
        #expect(!module.editLink(id, "not a link"))
        #expect(!module.editLink(id, "ftp://files.example.com"))
        #expect(module.store.items.first?.kind == .link(URL(string: "https://apple.com/mac")!))
    }

    @Test(arguments: [
        ("example.com", "https://example.com"),
        ("http://localhost:8080/x", "http://localhost:8080/x"),
        ("mailto:me@example.com", "mailto:me@example.com"),
        ("mailto:", nil),
        ("javascript:alert(1)", nil),
        ("hello", nil),
        ("https://", nil),
    ] as [(String, String?)])
    func typedLinks(typed: String, expected: String?) {
        #expect(ShelfModule.link(from: typed)?.absoluteString == expected)
    }

    @Test func aCardLeavesTheItemView() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        module.offer([.text("a")])
        module.openDetail(try #require(module.store.items.first?.id))
        module.offer([.text("a")])
        #expect(module.prompt != nil)
        #expect(module.detailID == nil)
        #expect(!notch.layout.isTall)
        #expect(module.holdsOpen)
    }

    @Test func turningTheShelfOffLeavesTheItemView() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        module.offer([.text("a")])
        module.openDetail(try #require(module.store.items.first?.id))
        notch.module = nil
        #expect(module.detailID == nil)
        #expect(module.clickAwayMonitor == nil)
        #expect(!notch.layout.isTall)
    }

    @Test func removingTheShownItemGoesBackToTheTiles() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        module.offer([.text("a")])
        let id = try #require(module.store.items.first?.id)
        module.openDetail(id)
        module.remove([id])
        #expect(module.detailID == nil)
        #expect(!notch.layout.isTall)
    }

    @Test func closingTheNotchLeavesTheTallView() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        module.offer([.text("a")])
        module.openDetail(try #require(module.store.items.first?.id))
        notch.close()
        #expect(module.detailID == nil)
        #expect(!notch.layout.isTall)
        #expect(notch.state == .closed)
    }

    @Test func nothingOpensWhileChoosingItemsToRemove() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer(try fixture.files(21))
        module.startChoosing()
        module.openDetail(try #require(module.store.items.first?.id))
        #expect(module.detailID == nil)
    }

    @Test func dragsCarryingShelfContentOpenTheNotchEarly() {
        let fixture = try? ShelfFixture()
        guard let fixture else { return }
        let (module, _) = makeModule(fixture)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ShelfDetailTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(!module.canAcceptDrag(pasteboard))
        pasteboard.setString("hello", forType: .string)
        #expect(module.canAcceptDrag(pasteboard))
    }
}
