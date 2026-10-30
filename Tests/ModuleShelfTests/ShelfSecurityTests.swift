import AppKit
import ConvertKit
import Testing
@testable import ModuleShelf

@MainActor
struct ShelfSecurityTests {
    @Test func conversionSavesBesideTheRealFile() async throws {
        let fixture = try ShelfFixture()
        let realFolder = fixture.root.appending(path: "private")
        let repo = fixture.root.appending(path: "repo")
        try FileManager.default.createDirectory(at: realFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let real = realFolder.appending(path: "source.jpg")
        try Data("fixture".utf8).write(to: real)
        let link = repo.appending(path: "notes.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let tests = ShelfConvertTests()
        let (module, _) = tests.makeModule(fixture)
        module.startConversion([link])
        try await tests.waitUntil { tests.isChoosing(module) }
        #expect(module.conversion?.sources == [real.resolvingSymlinksInPath()])
        #expect(module.convertDestination(for: link)?.resolvingSymlinksInPath() == realFolder.resolvingSymlinksInPath())
        module.chooseConvertFormat(.png)
        try await tests.waitUntil { tests.done(module) != nil }
        #expect(tests.done(module)?.files.first?.deletingLastPathComponent().resolvingSymlinksInPath() == realFolder.resolvingSymlinksInPath())
        #expect(!FileManager.default.fileExists(atPath: repo.appending(path: "notes.png").path))
        module.startConversion([repo])
        #expect(module.conversion?.phase == .failed(ConvertFailure.unreadable.message))
        // The same folder remains valid Shelf content.
        module.offer([.file(repo, owned: false)])
        #expect(module.store.items.contains { $0.fileURL?.resolvingSymlinksInPath() == repo.resolvingSymlinksInPath() })
    }

    @Test func dragOutResolvesBookmarksAndSkipsDeletedFiles() async throws {
        let fixture = try ShelfFixture()
        let (module, _) = ShelfConvertTests().makeModule(fixture)
        let original = try fixture.file("original.txt")
        module.offer([.file(original, owned: false)])
        let item = try #require(module.store.items.first)
        let moved = original.deletingLastPathComponent().appending(path: "moved.txt")
        try FileManager.default.moveItem(at: original, to: moved)
        // The cached path deliberately remains stale.
        #expect(item.fileURL == original)
        let payload = module.dragPayload(for: item.id)
        let dragged = try #require(payload.first?.writer as? NSURL) as URL
        #expect(try dragged.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier?.isEqual(
            moved.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier) == true)
        try FileManager.default.removeItem(at: moved)
        #expect(module.dragPayload(for: item.id).isEmpty)
    }

    @Test func promisesGainQuarantineAndKeepExistingProvenance() throws {
        let fixture = try ShelfFixture()
        let file = try fixture.file("attachment.txt")
        try ShelfDropReader.quarantineIfNeeded(file)
        let first = try #require(file.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties)
        try ShelfDropReader.quarantineIfNeeded(file)
        let second = try #require(file.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties)
        #expect(NSDictionary(dictionary: first).isEqual(to: second))
    }

    @Test func oversizedPasteboardItemsAreSkipped() throws {
        let fixture = try ShelfFixture()
        let image = NSPasteboardItem()
        image.setData(Data(repeating: 65, count: ShelfDropReader.dataLimit + 1), forType: .png)
        let text = NSPasteboardItem()
        text.setString(String(repeating: "a", count: ShelfDropReader.dataLimit + 1), forType: .string)
        let small = NSPasteboardItem()
        small.setString("keep me", forType: .string)
        let tests = ShelfDropReaderTests()
        let board = tests.pasteboard([image, text, small])
        defer { board.releaseGlobally() }
        let drop = ShelfDropReader.read(board) { try fixture.makeStore().newFilesFolder() }
        #expect(drop.inputs == [.text("keep me")])
    }

    @Test func aBlockedProbeTimesOut() async throws {
        let fixture = try ShelfFixture()
        let executable = try fixture.file("helper")
        try Data("#!/bin/sh\nexec /bin/sleep 30\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let runner = ShelfConvertHelper(executable: executable)
        let start = Date()
        await #expect(throws: ConvertFailure.failed) { try await runner.probe([executable]) }
        #expect(Date().timeIntervalSince(start) < 10)
    }
}
