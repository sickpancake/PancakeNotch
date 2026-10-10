import AppKit
import Testing
@testable import ModuleShelf

@MainActor
struct ShelfDropReaderTests {
    func pasteboard(_ items: [NSPasteboardItem]) -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("ShelfTests-\(UUID().uuidString)"))
        board.clearContents()
        board.writeObjects(items)
        return board
    }

    func item(_ values: [(NSPasteboard.PasteboardType, String)]) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for (type, value) in values { item.setString(value, forType: type) }
        return item
    }

    @Test func readsFilesLinksAndText() throws {
        let fixture = try ShelfFixture()
        let file = try fixture.file("a.pdf")
        let board = pasteboard([
            item([(.fileURL, file.absoluteString)]),
            item([(.URL, "https://example.com/page"), (.string, "https://example.com/page")]),
            item([(.string, "Hello there")]),
        ])
        let drop = ShelfDropReader.read(board) { try fixture.makeStore().newFilesFolder() }
        #expect(drop.inputs == [
            .file(file.standardizedFileURL, owned: false),
            .link(URL(string: "https://example.com/page")!),
            .text("Hello there"),
        ])
        #expect(drop.promises.isEmpty)
    }

    @Test func savesImageDataAsAnOwnedFileWithoutDecoding() throws {
        let fixture = try ShelfFixture()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let image = NSPasteboardItem()
        image.setData(bytes, forType: .png)
        let drop = ShelfDropReader.read(pasteboard([image])) { try fixture.makeStore().newFilesFolder() }

        guard case .file(let url, true) = try #require(drop.inputs.first) else {
            Issue.record("expected an owned file")
            return
        }
        #expect(try Data(contentsOf: url) == bytes)
        #expect(url.pathExtension == "png")
    }

    @Test func textThatIsALinkBecomesALink() throws {
        let fixture = try ShelfFixture()
        let input = ShelfDropReader.textInput("  https://apple.com\n") { try fixture.makeStore().newFilesFolder() }
        #expect(input == .link(URL(string: "https://apple.com")!))
        #expect(ShelfDropReader.textInput("see https://apple.com") { throw CocoaError(.fileNoSuchFile) } == .text("see https://apple.com"))
        #expect(ShelfDropReader.textInput("file:///etc/passwd") { throw CocoaError(.fileNoSuchFile) } == .text("file:///etc/passwd"))
        #expect(ShelfDropReader.textInput("   ") { throw CocoaError(.fileNoSuchFile) } == nil)
    }

    @Test func longTextBecomesATextFile() throws {
        let fixture = try ShelfFixture()
        let long = String(repeating: "word ", count: 30_000)
        let input = ShelfDropReader.textInput(long) { try fixture.makeStore().newFilesFolder() }
        guard case .file(let url, true) = input else {
            Issue.record("expected an owned .txt file")
            return
        }
        #expect(url.pathExtension == "txt")
    }

    @Test func recognisesAcceptedTypes() {
        #expect(ShelfDropReader.canRead(pasteboard([item([(.string, "hi")])])))
        let other = NSPasteboardItem()
        other.setData(Data([1]), forType: NSPasteboard.PasteboardType("com.example.private"))
        #expect(!ShelfDropReader.canRead(pasteboard([other])))
    }
}
