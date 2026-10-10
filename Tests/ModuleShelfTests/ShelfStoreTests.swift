import Foundation
import Testing
@testable import ModuleShelf

/// A throwaway Shelf folder plus a few real files to shelve.
@MainActor
final class ShelfFixture {
    let root: URL
    var clock = Date(timeIntervalSince1970: 1_000_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ShelfTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "Docs"), withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var shelfDirectory: URL { root.appending(path: "Shelf", directoryHint: .isDirectory) }

    func makeStore() -> ShelfStore {
        let time = clock
        return ShelfStore(directory: shelfDirectory, now: { time })
    }

    func file(_ name: String) throws -> URL {
        let url = root.appending(path: "Docs/\(name)")
        try Data(name.utf8).write(to: url)
        return url
    }

    func files(_ count: Int) throws -> [ShelfInput] {
        try (0..<count).map { .file(try file("f\($0).txt"), owned: false) }
    }
}

@MainActor
struct ShelfStoreTests {
    @Test func addsNewestFirstAndPersists() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        store.add([.text("first")], duplicates: .ask)
        store.add([.link(URL(string: "https://example.com")!), .file(try fixture.file("a.pdf"), owned: false)], duplicates: .ask)
        #expect(store.items.map(\.displayName) == ["example.com", "a.pdf", "first"])

        let reloaded = fixture.makeStore()
        #expect(reloaded.items == store.items)
    }

    @Test func askingAboutDuplicatesChangesNothing() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        let file = try fixture.file("a.pdf")
        store.add([.file(file, owned: false), .text("x")], duplicates: .ask)
        let before = store.items
        #expect(store.add([.file(file, owned: false), .text("new")], duplicates: .ask) == .duplicates(count: 1))
        #expect(store.items == before)
    }

    @Test func moveToFrontReordersWithoutCopies() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        store.add([.text("old")], duplicates: .ask)
        store.add([.text("newer")], duplicates: .ask)
        store.add([.text("old"), .text("brand new")], duplicates: .moveToFront)
        #expect(store.items.map(\.displayName) == ["brand new", "old", "newer"])
    }

    @Test func addAgainKeepsBoth() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        store.add([.text("same")], duplicates: .ask)
        store.add([.text("same")], duplicates: .addAgain)
        #expect(store.items.count == 2)
    }

    @Test func duplicatesWithinOneDropCollapse() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        store.add([.text("a"), .text("a")], duplicates: .ask)
        #expect(store.items.count == 1)
    }

    @Test func fillsToCapacityAndHoldsTheRest() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        let inputs = try fixture.files(22)
        let result = store.add(inputs, duplicates: .ask)
        #expect(result == .overflow(added: 20, pending: Array(inputs.suffix(2))))
        #expect(store.isFull)

        store.remove(store.items.prefix(1).map(\.id))
        #expect(store.add(Array(inputs.suffix(2)), duplicates: .ask) == .overflow(added: 1, pending: [inputs[21]]))
    }

    @Test func removingOwnedItemsDeletesTheirFilesOnly() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        let ownedFolder = try store.newFilesFolder()
        let owned = ownedFolder.appending(path: "Image.png")
        try Data([1, 2, 3]).write(to: owned)
        let userFile = try fixture.file("mine.txt")
        store.add([.file(owned, owned: true), .file(userFile, owned: false)], duplicates: .ask)

        store.clear()
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: ownedFolder.path))
        #expect(FileManager.default.fileExists(atPath: userFile.path))
    }

    @Test func ownedFileMovedOutIsNotDeleted() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        let owned = try store.newFilesFolder().appending(path: "Photo.png")
        try Data([1]).write(to: owned)
        store.add([.file(owned, owned: true)], duplicates: .ask)
        let movedTo = fixture.root.appending(path: "Docs/Photo.png")
        try FileManager.default.moveItem(at: owned, to: movedTo)

        store.clear()
        #expect(FileManager.default.fileExists(atPath: movedTo.path))
    }

    @Test func discardingHeldItemsDeletesTheirFiles() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        let folder = try store.newFilesFolder()
        let owned = folder.appending(path: "Mail.pdf")
        try Data([1]).write(to: owned)
        store.discard([.file(owned, owned: true)])
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func pruneFollowsRenamesAndDropsDeletedFiles() async throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        let renamed = try fixture.file("before.txt")
        let deleted = try fixture.file("gone.txt")
        store.add([.file(renamed, owned: false), .file(deleted, owned: false), .text("note")], duplicates: .ask)

        let after = renamed.deletingLastPathComponent().appending(path: "after.txt")
        try FileManager.default.moveItem(at: renamed, to: after)
        try FileManager.default.removeItem(at: deleted)
        await store.prune(maxAge: nil)

        #expect(store.items.map(\.displayName) == ["after.txt", "note"])
    }

    @Test func autoClearRemovesOldItems() async throws {
        let fixture = try ShelfFixture()
        let old = fixture.makeStore()
        old.add([.text("old")], duplicates: .ask)
        fixture.clock += 2 * 86_400
        let store = fixture.makeStore()
        store.add([.text("fresh")], duplicates: .ask)

        await store.prune(maxAge: 86_400)
        #expect(store.items.map(\.displayName) == ["fresh"])
    }

    @Test func notifiesOnChange() throws {
        let fixture = try ShelfFixture()
        let store = fixture.makeStore()
        var changes = 0
        store.onChange = { changes += 1 }
        store.add([.text("a")], duplicates: .ask)
        store.clear()
        #expect(changes == 2)
    }
}
