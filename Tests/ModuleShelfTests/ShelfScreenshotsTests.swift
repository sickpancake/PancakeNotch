import AppKit
import Foundation
import NotchCore
import Testing
@testable import ModuleShelf

/// A folder of pretend screenshots: files carrying macOS's "this is a screenshot" mark, like the ones
/// the Screenshot app saves.
final class ScreenshotFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "Screenshots-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    /// Writes a file; `marked` gives it the screenshot mark, `created` backdates it.
    @discardableResult
    func add(_ name: String, marked: Bool = true, created: Date? = nil, in subfolder: String? = nil) throws -> URL {
        var folder = url
        if let subfolder {
            folder = url.appending(path: subfolder, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let file = folder.appending(path: name)
        try Data("png".utf8).write(to: file)
        if marked { try Self.mark(file) }
        if let created { try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: file.path) }
        return file
    }

    static func mark(_ file: URL) throws {
        let value = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let result = value.withUnsafeBytes { bytes in
            setxattr(file.path, ScreenshotLocation.screenCaptureAttribute, bytes.baseAddress, bytes.count, 0, 0)
        }
        #expect(result == 0)
    }
}

struct ScreenshotLocationTests {
    let home = "/Users/someone"

    func resolve(_ location: String?, target: String? = nil, existing: Set<String> = []) -> ScreenshotLocation {
        ScreenshotLocation.resolve(location: location, target: target, home: home) { existing.contains($0) }
    }

    /// Like macOS: no "Save to" setting means the Desktop.
    @Test func defaultsToTheDesktop() {
        let location = resolve(nil)
        #expect(location.folder.path == "/Users/someone/Desktop")
        #expect(location.savesFiles)
        #expect(resolve("").folder.path == "/Users/someone/Desktop")
    }

    /// The Screenshot app saves "~/Pictures/Captures" with a tilde.
    @Test func expandsTheHomeFolder() {
        let location = resolve("~/Pictures/Captures", existing: ["/Users/someone/Pictures/Captures"])
        #expect(location.folder.path == "/Users/someone/Pictures/Captures")
        #expect(resolve("~", existing: [home]).folder.path == home)
    }

    @Test func acceptsFullPathsAndFileURLs() {
        let existing: Set<String> = ["/Volumes/Work/Shots"]
        #expect(resolve("/Volumes/Work/Shots/", existing: existing).folder.path == "/Volumes/Work/Shots")
        #expect(resolve("file:///Volumes/Work/Shots/", existing: existing).folder.path == "/Volumes/Work/Shots")
    }

    /// A folder that was deleted or renamed: macOS falls back to the Desktop, and so do we.
    @Test func aMissingFolderMeansTheDesktop() {
        #expect(resolve("~/Gone").folder.path == "/Users/someone/Desktop")
        #expect(resolve("relative/path", existing: ["relative/path"]).folder.path == "/Users/someone/Desktop")
    }

    /// Screenshots sent to the clipboard (or Preview, Mail…) leave no file to catch.
    @Test func knowsWhenScreenshotsArentFiles() {
        #expect(!resolve(nil, target: "clipboard").savesFiles)
        #expect(!resolve(nil, target: "preview").savesFiles)
        #expect(resolve(nil, target: "file").savesFiles)
    }

    /// Only new, visible files with the screenshot mark, directly in the folder, oldest first.
    @Test func findsOnlyNewScreenshots() throws {
        let folder = try ScreenshotFolder()
        let now = Date()
        let second = try folder.add("Screenshot 2.png", created: now.addingTimeInterval(-5))
        let first = try folder.add("Screenshot 1.png", created: now.addingTimeInterval(-20))
        let plain = try folder.add("Photo.png", marked: false)
        let hidden = try folder.add(".Screenshot 3.png")
        let old = try folder.add("Screenshot old.png", created: now.addingTimeInterval(-3600))
        let nested = try folder.add("Screenshot 4.png", in: "Sub")
        let paths = [second, first, plain, hidden, old, nested, second].map(\.path) + [folder.url.path + "/Missing.png"]
        let found = ScreenshotLocation.newScreenshots(in: paths, folders: [folder.url.path], now: now)
        #expect(found.map(\.lastPathComponent) == ["Screenshot 1.png", "Screenshot 2.png"])
    }

    /// FSEvents reports the real path (/private/var/… for the temporary folder).
    @Test func matchesTheRealPath() throws {
        let folder = try ScreenshotFolder()
        let file = try folder.add("Screenshot.png")
        let real = ScreenshotLocation.realPath(folder.url.path)
        let reported = real + "/" + file.lastPathComponent
        let found = ScreenshotLocation.newScreenshots(in: [reported], folders: [folder.url.path, real], now: Date())
        #expect(found.count == 1)
    }
}

@MainActor
struct ShelfScreenshotsTests {
    func makeModule(_ fixture: ShelfFixture) -> (ShelfModule, NotchViewModel) {
        let defaults = UserDefaults(suiteName: "ShelfScreenshotsTests-\(UUID().uuidString)")!
        let module = ShelfModule(store: fixture.makeStore(), settings: ShelfSettings(defaults: defaults))
        let notch = NotchViewModel(
            layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))),
            pointerLocation: { CGPoint(x: 756, y: 300) }
        )
        notch.module = module
        return (module, notch)
    }

    @Test func isOffUntilSwitchedOn() {
        let defaults = UserDefaults(suiteName: "ShelfScreenshotsTests-\(UUID().uuidString)")!
        #expect(!ShelfSettings(defaults: defaults).catchesScreenshots)
        ShelfSettings(defaults: defaults).catchesScreenshots = true
        #expect(ShelfSettings(defaults: defaults).catchesScreenshots)
    }

    /// A new screenshot goes to the front, and the strip under the closed notch says so.
    @Test func addsToTheFrontWithAPeek() throws {
        let fixture = try ShelfFixture()
        let folder = try ScreenshotFolder()
        let (module, notch) = makeModule(fixture)
        module.offer([.text("Older")])
        let shot = try folder.add("Screenshot.png")
        #expect(module.catchScreenshot(shot))
        #expect(module.store.items.count == 2)
        #expect(module.store.items.first?.path == shot.resolvingSymlinksInPath().path)
        #expect(module.store.items.first?.isOwnedFile == false)
        #expect(module.peekNote == .screenshotAdded)
        #expect(notch.peekModuleID == module.moduleID)
        #expect(module.prompt == nil)
    }

    /// Never a card from a screenshot by itself: one already there is left alone, even with "Ask".
    @Test func ignoresOneAlreadyThere() throws {
        let fixture = try ShelfFixture()
        let folder = try ScreenshotFolder()
        let (module, _) = makeModule(fixture)
        let shot = try folder.add("Screenshot.png")
        module.offer([.file(shot, owned: false), .text("Newer")])
        #expect(module.settings.duplicatePolicy == .ask)
        #expect(module.catchScreenshot(shot))
        #expect(module.store.items.count == 2)
        #expect(module.prompt == nil)
    }

    /// With 20 items nothing is removed to make room: the strip says it wasn't added.
    @Test func saysSoWhenTheShelfIsFull() throws {
        let fixture = try ShelfFixture()
        let folder = try ScreenshotFolder()
        let (module, notch) = makeModule(fixture)
        module.offer(try fixture.files(ShelfStore.capacity))
        #expect(module.store.isFull)
        #expect(module.catchScreenshot(try folder.add("Screenshot.png")))
        #expect(module.store.items.count == ShelfStore.capacity)
        #expect(module.peekNote == .screenshotNoRoom)
        #expect(notch.peekModuleID == module.moduleID)
        #expect(module.prompt == nil)
    }

    /// With the notch open the new tile shows by itself: no strip.
    @Test func noPeekWhileTheNotchIsOpen() throws {
        let fixture = try ShelfFixture()
        let folder = try ScreenshotFolder()
        let (module, notch) = makeModule(fixture)
        notch.open()
        #expect(module.catchScreenshot(try folder.add("Screenshot.png")))
        #expect(module.store.items.count == 1)
        #expect(module.peekNote == nil)
        #expect(notch.peekModuleID == nil)
    }

    /// A file that can't be kept (macOS refused access) adds nothing and reports it.
    @Test func reportsAFileItCouldNotKeep() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        #expect(!module.catchScreenshot(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/Screenshot.png")))
        #expect(module.store.items.isEmpty)
        #expect(notch.peekModuleID == nil)
    }

    /// The whole path with real FSEvents: on, a new screenshot lands; off, the folder isn't watched.
    @Test(.timeLimit(.minutes(1))) func catchesFromTheWatchedFolder() async throws {
        let fixture = try ShelfFixture()
        let folder = try ScreenshotFolder()
        let (module, _) = makeModule(fixture)
        let location = ScreenshotLocation(folder: folder.url, savesFiles: true)
        let catcher = ShelfScreenshots(settings: module.settings, readLocation: { location }, preferencesFile: nil)
        catcher.follow(module)
        #expect(catcher.location == nil)

        module.settings.catchesScreenshots = true
        try await waitUntil { catcher.location == location && catcher.access == .allowed }
        try folder.add("Screenshot A.png")
        try folder.add("Picture.png", marked: false)
        try await waitUntil { module.store.items.count == 1 }
        #expect(module.store.items.first?.displayName == "Screenshot A.png")

        module.settings.catchesScreenshots = false
        try await waitUntil { catcher.access == .unknown }
        try folder.add("Screenshot B.png")
        try await Task.sleep(for: .seconds(2))
        #expect(module.store.items.count == 1)

        // Switched on again: the next one is caught, the one taken while it was off isn't.
        module.settings.catchesScreenshots = true
        try await waitUntil { catcher.access == .allowed }
        try folder.add("Screenshot C.png")
        try await waitUntil { module.store.items.count == 2 }
        #expect(module.store.items.first?.displayName == "Screenshot C.png")
    }

    /// The same file reported again (macOS adds its details in steps) is offered once, even after
    /// it was removed from the Shelf.
    @Test func offersEachScreenshotOnce() async throws {
        let fixture = try ShelfFixture()
        let folder = try ScreenshotFolder()
        let (module, _) = makeModule(fixture)
        let location = ScreenshotLocation(folder: folder.url, savesFiles: true)
        let catcher = ShelfScreenshots(settings: module.settings, readLocation: { location }, preferencesFile: nil)
        module.settings.catchesScreenshots = true
        catcher.follow(module)
        let shot = try folder.add("Screenshot.png")
        catcher.arrived([shot])
        #expect(module.store.items.count == 1)
        module.store.clear()
        catcher.arrived([shot])
        #expect(module.store.items.isEmpty)
    }

    /// Without the Shelf (switched off) nothing is caught.
    @Test func needsTheShelf() throws {
        let fixture = try ShelfFixture()
        let folder = try ScreenshotFolder()
        let (module, _) = makeModule(fixture)
        let location = ScreenshotLocation(folder: folder.url, savesFiles: true)
        let catcher = ShelfScreenshots(settings: module.settings, readLocation: { location }, preferencesFile: nil)
        module.settings.catchesScreenshots = true
        catcher.follow(nil)
        catcher.arrived([try folder.add("Screenshot.png")])
        #expect(module.store.items.isEmpty)
        #expect(catcher.location == nil)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out waiting")
    }
}
