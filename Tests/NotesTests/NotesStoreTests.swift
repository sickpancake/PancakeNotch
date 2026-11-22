import Foundation
import Testing
@testable import NotesCore

@MainActor
struct NotesStoreTests {
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    let clock = Clock()

    func makeStore(directory: URL? = nil) -> NotesStore {
        let clock = clock
        return NotesStore(directory: directory, now: { clock.now })
    }

    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "NotesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func addingEditingAndDeletingANote() {
        let store = makeStore()
        var events: [NotesEvent] = []
        store.onEvent = { events.append($0) }
        let note = store.add("Buy syrup")
        #expect(store.notes.count == 1)
        clock.now += 60
        store.update(note!.id, text: "Buy maple syrup\nThe dark one")
        #expect(store.note(note!.id)?.title == "Buy maple syrup")
        #expect(store.note(note!.id)?.preview == "The dark one")
        #expect(store.note(note!.id)?.modified == clock.now)
        store.delete(note!.id)
        #expect(store.notes.isEmpty)
        #expect(store.lastDeleted?.id == note!.id)
        store.undoDelete()
        #expect(store.notes.first?.text == "Buy maple syrup\nThe dark one")
        #expect(store.lastDeleted == nil)
        #expect(events == [.created(.typed), .edited, .deleted, .restored])
    }

    @Test func droppedTextMustHaveWords() {
        let store = makeStore()
        #expect(store.add("  \n ", source: .dropped) == nil)
        #expect(store.add("", source: .typed) != nil)
        #expect(store.add("Hello\r\nworld", source: .shelf(fileName: "a.txt"))?.text == "Hello\nworld")
    }

    @Test func emptyNotesAreCleanedUpButNotTheOneBeingWritten() {
        let store = makeStore()
        let keep = store.add()!
        store.add()
        store.add("Words")
        store.removeEmpty(except: keep.id)
        #expect(store.notes.count == 2)
        #expect(store.note(keep.id) != nil)
    }

    @Test func deletingAnEmptyNoteKeepsTheEarlierUndo() {
        let store = makeStore()
        let words = store.add("Words")!
        store.delete(words.id)
        store.delete(store.add()!.id)
        #expect(store.lastDeleted?.id == words.id)
    }

    @Test func pinnedNotesComeFirstInEveryOrder() {
        let store = makeStore()
        let first = store.add("First")!
        clock.now += 10
        let second = store.add("Second")!
        clock.now += 10
        let third = store.add("Third")!
        clock.now += 10
        store.update(first.id, text: "First, edited")
        store.togglePin(second.id)
        #expect(store.sorted(.recentlyEdited).map(\.id) == [second.id, first.id, third.id])
        #expect(store.sorted(.newestFirst).map(\.id) == [second.id, third.id, first.id])
        #expect(store.sorted(.oldestFirst).map(\.id) == [second.id, first.id, third.id])
        #expect(store.pinnedCount == 1)
    }

    @Test func aFullStoreRefusesNewNotes() {
        let store = makeStore()
        for index in 0..<NotesStore.capacity { store.add("Note \(index)") }
        #expect(store.isFull)
        #expect(store.add("One more") == nil)
        #expect(store.add([("A", .dropped), ("B", .dropped)]) == 0)
    }

    @Test func notesAreSavedAndReadBack() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = makeStore(directory: directory)
        let note = store.add("Keep me", source: .shelf(fileName: "Keep.txt"))!
        store.togglePin(note.id)
        let reopened = makeStore(directory: directory)
        #expect(reopened.notes == store.notes)
        #expect(reopened.notes.first?.isPinned == true)
    }

    @Test func anUnreadableFileIsKeptAside() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "notes.json"))
        let store = makeStore(directory: directory)
        #expect(store.notes.isEmpty)
        store.add("New")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("notes-unreadable-") })
        #expect(makeStore(directory: directory).notes.map(\.text) == ["New"])
    }

    @Test func textFilesAreReadAsNoteText() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = directory.appending(path: "Plan.txt")
        try Data("Plan\nStep one".utf8).write(to: text)
        let empty = directory.appending(path: "Empty.txt")
        try Data("  ".utf8).write(to: empty)
        let big = directory.appending(path: "Big.txt")
        try Data(repeating: 65, count: NotesImport.maxFileBytes + 1).write(to: big)
        let image = directory.appending(path: "Photo.png")
        try Data([0x89, 0x50]).write(to: image)
        #expect(NotesImport.text(of: text) == "Plan\nStep one")
        #expect(NotesImport.text(of: empty) == nil)
        #expect(NotesImport.text(of: big) == nil)
        #expect(NotesImport.text(of: image) == nil)
        #expect(NotesImport.isTextFile(directory.appending(path: "readme.md")))
        #expect(!NotesImport.isTextFile(directory.appending(path: "main.swift")))
        #expect(!NotesImport.isTextFile(directory.appending(path: "report.csv")))
        #expect(!NotesImport.isTextFile(directory.appending(path: "server.log")))
    }

    @Test func textFilesInOtherEncodingsReadCorrectlyOrNotAtAll() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let latin1 = directory.appending(path: "Latin.txt")
        try "café crème brûlée".data(using: .isoLatin1)!.write(to: latin1)
        let utf16 = directory.appending(path: "Wide.txt")
        try "Wide note".data(using: .utf16)!.write(to: utf16)
        let binary = directory.appending(path: "Binary.txt")
        try Data("Binary\0embedded\0NUL".utf8).write(to: binary)
        #expect(NotesImport.text(of: latin1) == "café crème brûlée")
        #expect(NotesImport.text(of: utf16) == "Wide note")
        #expect(NotesImport.text(of: binary) == nil)
    }

    @Test func settingsAreRemembered() {
        let defaults = UserDefaults(suiteName: "NotesTests-\(UUID().uuidString)")!
        let settings = NotesSettings(defaults: defaults)
        #expect(settings.isEnabled && settings.shelfText == .textFiles && settings.sort == .recentlyEdited)
        settings.shelfText = .allText
        settings.sort = .oldestFirst
        settings.opensNewNote = true
        let again = NotesSettings(defaults: defaults)
        #expect(again.shelfText == .allText && again.sort == .oldestFirst && again.opensNewNote)
    }
}
