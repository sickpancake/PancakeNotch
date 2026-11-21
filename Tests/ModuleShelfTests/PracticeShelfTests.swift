import AppKit
import Foundation
import NotchCore
import Testing
@testable import ModuleShelf

/// The Shelf tells the app window's lessons what the user did.
@MainActor
struct ShelfEventTests {
    func makeModule(_ fixture: ShelfFixture) -> (ShelfModule, NotchViewModel, EventLog) {
        let settings = ShelfSettings(defaults: UserDefaults(suiteName: "ShelfEventTests-\(UUID().uuidString)")!)
        let module = ShelfModule(store: fixture.makeStore(), settings: settings)
        let notch = NotchViewModel(
            layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))),
            state: .expanded,
            pointerLocation: { CGPoint(x: 756, y: 300) }
        )
        notch.module = module
        let log = EventLog()
        module.onEvent = { log.events.append($0) }
        return (module, notch, log)
    }

    @Test func storeChangesReportTheCount() throws {
        let fixture = try ShelfFixture()
        let (module, _, log) = makeModule(fixture)
        module.offer([.text("a"), .text("b")])
        #expect(log.events == [.itemsChanged(count: 2)])
        module.remove([module.store.items[0].id])
        #expect(log.events.last == .itemsChanged(count: 1))
    }

    @Test func openingAndClosingAnItem() throws {
        let fixture = try ShelfFixture()
        let (module, _, log) = makeModule(fixture)
        module.offer([.text("a"), .text("b")])
        log.events = []
        module.openDetail(module.store.items[0].id)
        #expect(log.events.contains(.detailOpened))
        // Switching straight to another item is neither opening nor closing.
        log.events = []
        module.detailID = module.store.items[1].id
        #expect(!log.events.contains(.detailOpened) && !log.events.contains(.detailClosed))
        module.closeDetail()
        #expect(log.events.last == .detailClosed)
        #expect(log.events.filter { $0 == .detailClosed }.count == 1)
    }

    @Test func selectionReportsOnlyCountChanges() throws {
        let fixture = try ShelfFixture()
        let (module, _, log) = makeModule(fixture)
        module.offer([.text("a"), .text("b"), .text("c")])
        let ids = module.store.items.map(\.id)
        log.events = []
        module.click(ids[0], modifiers: [])
        module.click(ids[1], modifiers: []) // still one selected: no event
        module.click(ids[2], modifiers: .command)
        module.selection = []
        #expect(log.events == [.selectionChanged(count: 1), .selectionChanged(count: 2), .selectionChanged(count: 0)])
    }

    @Test func menuOpenAndClose() throws {
        let fixture = try ShelfFixture()
        let (module, _, log) = makeModule(fixture)
        module.setMenuOpen(true)
        module.setMenuOpen(true)
        module.setMenuOpen(false)
        #expect(log.events == [.menuOpened, .menuClosed])
    }

    @Test func dragOutEndedSaysWhetherItWasTaken() throws {
        let fixture = try ShelfFixture()
        let (module, _, log) = makeModule(fixture)
        module.offer([.text("a")])
        let id = try #require(module.store.items.first?.id)
        log.events = []
        module.setDraggingOut(true)
        #expect(module.isDraggingOutItems)
        module.dragOutEnded([id], operation: [])
        #expect(!module.isDraggingOutItems)
        module.setDraggingOut(true)
        module.dragOutEnded([id], operation: .copy)
        #expect(log.events == [.dragOutEnded(accepted: false), .dragOutEnded(accepted: true)])
        #expect(module.store.items.count == 1)
    }

    @Test func clearAllReportsOnlyWhenConfirmed() throws {
        let fixture = try ShelfFixture()
        let (module, _, log) = makeModule(fixture)
        module.offer([.text("a")])
        log.events = []
        module.clearAll()
        #expect(!log.events.contains(.cleared))
        module.clearAll()
        #expect(log.events.contains(.cleared))
        #expect(module.store.items.isEmpty)
    }

    @Test func recognisesItsOwnDragSources() throws {
        let fixture = try ShelfFixture()
        let (module, _, _) = makeModule(fixture)
        #expect(ShelfModule.isOwnDragSource(ShelfTileNSView(module: module, itemID: nil)))
        #expect(ShelfModule.isOwnDragSource(ShelfTileNSView(module: module, itemID: UUID())))
        #expect(!ShelfModule.isOwnDragSource(NSView()))
        #expect(!ShelfModule.isOwnDragSource(nil))
    }
}

@MainActor
final class EventLog {
    var events: [ShelfEvent] = []
}

/// The app window's throwaway Shelf.
@MainActor
struct PracticeShelfTests {
    @Test func seededHasFourExampleItemsWithRealFiles() throws {
        let practice = PracticeShelf(seeded: true)
        defer { practice.close() }
        let items = practice.module.store.items
        #expect(items.count == 4)
        #expect(items.map(\.isFile) == [true, true, false, false])
        #expect(items[2].kind == .text("Pick up the cake at 5"))
        #expect(items[3].kind == .link(URL(string: "https://github.com")!))
        for item in items where item.isFile {
            let url = try #require(item.fileURL)
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(url.path.hasPrefix(practice.folder.resolvingSymlinksInPath().path))
            #expect(!url.path.hasPrefix(practice.module.store.directory.resolvingSymlinksInPath().path))
        }
        #expect(items[0].fileURL?.lastPathComponent == "Report.pdf")
        #expect(items[1].fileURL?.lastPathComponent == "Holiday.jpg")
        #expect(NSImage(contentsOf: try #require(items[1].fileURL))?.size == CGSize(width: 600, height: 400))
        #expect(CGPDFDocument(try #require(items[0].fileURL) as CFURL)?.numberOfPages == 1)
    }

    @Test func practiceSettings() {
        let practice = PracticeShelf(seeded: false)
        defer { practice.close() }
        let settings = practice.module.settings
        #expect(settings.dragOutMode == .copy)
        #expect(!settings.removeAfterDragOut)
        #expect(settings.duplicatePolicy == .addAgain)
        #expect(settings.autoClear == .never)
        #expect(!settings.showsAirDropZone)
        #expect(settings.showsInEars)
    }

    @Test func emptyStartsEmptyAndOffersPracticeFiles() {
        let practice = PracticeShelf(seeded: false)
        defer { practice.close() }
        #expect(practice.module.store.items.isEmpty)
        let files = practice.practiceFiles()
        #expect(files.count == 3)
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        // Asking again gives the same files, and recreates one that went missing.
        try? FileManager.default.removeItem(at: files[0])
        #expect(practice.practiceFiles() == files)
        #expect(FileManager.default.fileExists(atPath: files[0].path))
    }

    @Test func closeRemovesEverythingAndCanBeCalledTwice() {
        let practice = PracticeShelf(seeded: true)
        _ = practice.practiceFiles()
        #expect(FileManager.default.fileExists(atPath: practice.folder.path))
        practice.close()
        #expect(!FileManager.default.fileExists(atPath: practice.folder.path))
        practice.close()
        #expect(practice.practiceFiles().isEmpty)
    }

    @Test func removeLeftoversClearsOnlyStrayPracticeFolders() throws {
        let fixture = try ShelfFixture()
        let stray = fixture.root.appending(path: "PancakeNotch-practice-\(UUID().uuidString)")
        let other = fixture.root.appending(path: "PancakeNotch-\(UUID().uuidString)")
        for folder in [stray, other] {
            try FileManager.default.createDirectory(at: folder.appending(path: "Shelf"), withIntermediateDirectories: true)
        }
        PracticeShelf.removeLeftovers(in: fixture.root)
        #expect(!FileManager.default.fileExists(atPath: stray.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    /// Works in its own folder: cleaning the real temporary folder would delete the practice files
    /// of a PancakeNotch that's running while the tests do.
    @Test func removeLeftoversKeepsOpenPracticeShelves() throws {
        let fixture = try ShelfFixture()
        let practice = PracticeShelf(seeded: true)
        defer { practice.close() }
        let open = fixture.root.appending(path: practice.folder.lastPathComponent)
        try FileManager.default.createDirectory(at: open, withIntermediateDirectories: true)
        PracticeShelf.removeLeftovers(in: fixture.root)
        #expect(FileManager.default.fileExists(atPath: open.path))
    }
}
