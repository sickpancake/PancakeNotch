import Foundation
import ModuleShelf
import NotesCore
import Testing
@testable import PancakeNotch

/// Text dropped on the Shelf becomes notes as Notes' settings say; the rest stays on the Shelf.
@MainActor
@Suite struct ShelfNotesTests {
    private func settings(_ mode: NotesShelfText, enabled: Bool = true) -> NotesSettings {
        let suite = "ShelfNotesTests-\(UUID().uuidString)"
        let settings = NotesSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.isEnabled = enabled
        settings.shelfText = mode
        return settings
    }

    private func file(_ name: String, _ text: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func textFilesBecomeNotes() throws {
        let store = NotesStore(directory: nil)
        let txt = try file("Groceries.txt", "Groceries\nEggs")
        let image = try file("photo.png", "not text")
        let link = URL(string: "https://example.com")!
        let kept = ShelfNotes.take([.file(txt, owned: false), .file(image, owned: false), .text("hello"), .link(link)],
                                   into: store, settings: settings(.textFiles))
        #expect(kept == [.file(image, owned: false), .text("hello"), .link(link)])
        #expect(store.notes.map(\.text) == ["Groceries\nEggs"])
        #expect(store.notes.first?.source == .shelf(fileName: "Groceries.txt"))
    }

    @Test func allTextTakesTextAndLongText() throws {
        let store = NotesStore(directory: nil)
        let long = try file("Text.txt", "A long paste")
        let kept = ShelfNotes.take([.text("hello"), .file(long, owned: true)], into: store, settings: settings(.allText))
        #expect(kept.isEmpty)
        #expect(Set(store.notes.map(\.text)) == ["hello", "A long paste"])
        #expect(store.notes.allSatisfy { $0.source == .shelf(fileName: nil) })
    }

    @Test func longTextStaysWithTextFiles() throws {
        let store = NotesStore(directory: nil)
        let long = try file("Text.txt", "A long paste")
        let kept = ShelfNotes.take([.file(long, owned: true)], into: store, settings: settings(.textFiles))
        #expect(kept == [.file(long, owned: true)])
        #expect(store.notes.isEmpty)
    }

    @Test func offOrNotesOffKeepsEverything() throws {
        let txt = try file("a.txt", "text")
        for settings in [settings(.off), settings(.textFiles, enabled: false)] {
            let store = NotesStore(directory: nil)
            #expect(ShelfNotes.take([.file(txt, owned: false)], into: store, settings: settings) == [.file(txt, owned: false)])
            #expect(store.notes.isEmpty)
        }
    }

    @Test func emptyTextFileStays() throws {
        let store = NotesStore(directory: nil)
        let blank = try file("blank.txt", "  \n")
        #expect(ShelfNotes.take([.file(blank, owned: false)], into: store, settings: settings(.textFiles)) == [.file(blank, owned: false)])
    }
}
