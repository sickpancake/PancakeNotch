import AppKit
import ConvertKit
import NotchCore
import Testing
@testable import ModuleShelf

/// Convert in the Shelf (ADR-0038), with a stand-in for the helper: the row, saving, stopping, and
/// finishing while the notch is closed.
@MainActor
struct ShelfConvertTests {
    /// Writes "<name>.<ext>" for each source, after `delay`; or fails every file.
    struct FakeRunner: ShelfConvertRunning {
        var delay: Duration = .zero
        var fails = false

        func probe(_ files: [URL]) async throws -> [ConvertFileInfo] {
            files.map { _ in
                ConvertFileInfo(kind: .image, pixelWidth: 1000, pixelHeight: 800, hasAlpha: false, imageType: "public.jpeg", isCMYK: false)
            }
        }

        func convert(_ request: ConvertRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> ConvertMessage {
            progress(0.5)
            try await Task.sleep(for: delay)
            if fails { return ConvertMessage(outputs: [], errors: request.sources.indices.map { ConvertError(source: $0, failure: .unreadable) }) }
            let outputs = try request.sources.enumerated().map { index, path in
                let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                let url = URL(fileURLWithPath: request.outputFolder).appending(path: "\(name).\(request.format.fileExtension)")
                try Data("converted".utf8).write(to: url)
                return ConvertOutput(source: index, path: url.path)
            }
            return ConvertMessage(outputs: outputs, errors: [])
        }
    }

    func makeModule(_ fixture: ShelfFixture, runner: FakeRunner = FakeRunner()) -> (ShelfModule, NotchViewModel) {
        let settings = ShelfSettings(defaults: UserDefaults(suiteName: "ShelfConvertTests-\(UUID().uuidString)")!)
        let module = ShelfModule(store: fixture.makeStore(), settings: settings)
        module.convertRunner = runner
        let notch = NotchViewModel(
            layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))),
            state: .expanded,
            pointerLocation: { CGPoint(x: 756, y: 300) }
        )
        notch.module = module
        return (module, notch)
    }

    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    func isChoosing(_ module: ShelfModule) -> Bool { module.conversion?.phase == .choosing }

    func done(_ module: ShelfModule) -> ShelfConversion.Done? {
        if case .done(let done) = module.conversion?.phase { return done }
        return nil
    }

    @Test func aDropShowsTheRowAndTheResultLandsBesideTheOriginal() async throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        let photo = try fixture.file("Photo.jpg")

        module.startConversion([photo])
        #expect(notch.layout.panelHeight == .medium)
        #expect(module.holdsOpen)
        try await waitUntil { isChoosing(module) }
        let formats = try #require(module.conversion).options.map(\.format)
        #expect(!formats.contains(.jpeg)) // never its own format
        #expect(formats.contains(.png))

        module.chooseConvertFormat(.png)
        try await waitUntil { done(module) != nil }
        let result = try #require(done(module))
        #expect(result.files == [fixture.root.appending(path: "Docs/Photo.png")])
        #expect(!result.keptInShelf)
        #expect(module.store.items.contains { $0.path == result.files.first?.path })

        // Esc goes back to the Shelf at its usual height.
        #expect(module.handleKey(try ShelfDetailTests.key("\u{1b}", code: 53)))
        #expect(module.conversion == nil)
        #expect(notch.layout.panelHeight == .regular)
    }

    @Test func neverOverwritesAndFallsBackToTheShelf() async throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        let photo = try fixture.file("Photo.jpg")
        _ = try fixture.file("Photo.png")

        module.startConversion([photo])
        try await waitUntil { isChoosing(module) }
        module.chooseConvertFormat(.png)
        try await waitUntil { done(module) != nil }
        #expect(done(module)?.files.first?.lastPathComponent == "Photo 2.png")

        // A chosen folder that can't be written to: the Shelf keeps the file.
        module.settings.convertDestination = .folder
        module.settings.convertFolder = URL(fileURLWithPath: "/System/Converted", isDirectory: true)
        module.startConversion([photo])
        try await waitUntil { isChoosing(module) }
        module.chooseConvertFormat(.tiff)
        try await waitUntil { done(module) != nil }
        let kept = try #require(done(module))
        #expect(kept.keptInShelf)
        #expect(kept.files.first?.path.hasPrefix(fixture.shelfDirectory.path) == true)
    }

    @Test func arrowsMoveAlongTheRowAndReturnConverts() async throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.startConversion([try fixture.file("Photo.jpg")])
        try await waitUntil { isChoosing(module) }
        let session = try #require(module.conversion)
        let first = try #require(session.focus)

        #expect(module.handleKey(try ShelfDetailTests.key("\u{F703}", code: 124)))
        let second = try #require(session.focus)
        #expect(second != first)
        #expect(module.handleKey(try ShelfDetailTests.key("\u{F702}", code: 123)))
        #expect(session.focus == first)
        // Typing goes nowhere while the row shows.
        #expect(module.handleKey(try ShelfDetailTests.key("a", code: 0)))

        #expect(module.handleKey(try ShelfDetailTests.key("\r", code: 36)))
        #expect(session.phase == .converting(first))
        try await waitUntil { done(module) != nil }
    }

    @Test func stoppingGoesBackToTheRowWithNothingSaved() async throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture, runner: FakeRunner(delay: .seconds(30)))
        module.startConversion([try fixture.file("Photo.jpg")])
        try await waitUntil { isChoosing(module) }
        module.chooseConvertFormat(.png)
        try await waitUntil { module.conversion?.progress == 0.5 }

        // Esc stops a conversion; it doesn't leave.
        #expect(module.handleKey(try ShelfDetailTests.key("\u{1b}", code: 53)))
        #expect(isChoosing(module))
        try await Task.sleep(for: .milliseconds(50))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appending(path: "Docs/Photo.png").path))
        #expect(module.store.items.isEmpty)
    }

    @Test func closingTheNotchLetsItFinishThenSaysSo() async throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture, runner: FakeRunner(delay: .milliseconds(200)))
        module.startConversion([try fixture.file("Photo.jpg")])
        try await waitUntil { isChoosing(module) }
        module.chooseConvertFormat(.png)

        module.notchDidClose()
        #expect(module.conversion?.isDetached == true)
        #expect(module.visibleConversion == nil)
        #expect(notch.layout.panelHeight == .regular)

        try await waitUntil { module.conversion == nil }
        #expect(module.convertPeekText == ShelfModule.doneText(files: [URL(fileURLWithPath: "/Photo.png")]))
        #expect(!module.convertPeekFailed)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appending(path: "Docs/Photo.png").path))
    }

    @Test func closingTheNotchWhileChoosingJustEnds() async throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.startConversion([try fixture.file("Photo.jpg")])
        try await waitUntil { isChoosing(module) }
        module.notchDidClose()
        #expect(module.conversion == nil)
    }

    @Test func aFailureShowsItsReason() async throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture, runner: FakeRunner(fails: true))
        module.startConversion([try fixture.file("Photo.jpg")])
        try await waitUntil { isChoosing(module) }
        module.chooseConvertFormat(.png)
        try await waitUntil { if case .failed = module.conversion?.phase { true } else { false } }
        #expect(module.conversion?.phase == .failed(ConvertFailure.unreadable.message))
        #expect(module.store.items.isEmpty)
    }

    @Test func convertIsOfferedOnlyForFilesWithAFormat() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.file(try fixture.file("Photo.jpg"), owned: false), .file(try fixture.file("Archive.zip"), owned: false), .text("hi")])
        let items = module.store.items
        let photo = try #require(items.first { $0.displayName == "Photo.jpg" })
        let archive = try #require(items.first { $0.displayName == "Archive.zip" })
        let note = try #require(items.first { !$0.isFile })

        #expect(module.canConvert([photo]))
        #expect(!module.canConvert([archive]))
        #expect(!module.canConvert([note]))
        #expect(!module.canConvert([photo, note]))
        module.settings.convertEnabled = false
        #expect(!module.canConvert([photo]))
    }

    @Test func theDropZoneKnowsWhatCanConvert() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ShelfConvertTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.writeObjects([try fixture.file("Photo.jpg") as NSURL])
        #expect(module.convertZone(for: pasteboard) == .ready)
        pasteboard.clearContents()
        pasteboard.writeObjects([try fixture.file("Archive.zip") as NSURL])
        #expect(module.convertZone(for: pasteboard) == .cantConvert)
        // Text and links aren't files: no Convert zone at all.
        pasteboard.clearContents()
        pasteboard.writeObjects(["hello" as NSString])
        #expect(module.convertZone(for: pasteboard) == nil)
    }

    @Test func aDockDragShowsConvertThenChecksTheFileOnceItCan() throws {
        let fixture = try ShelfFixture()
        // The notch is kept: the drop zones are laid out from it.
        let (module, notch) = makeModule(fixture)
        defer { withExtendedLifetime(notch) {} }
        // The early opening for a Dock drag only knows "files", not which.
        let standIn = NSPasteboard.withUniqueName()
        standIn.declareTypes([.fileURL], owner: nil)
        let real = NSPasteboard.withUniqueName()
        defer {
            standIn.releaseGlobally()
            real.releaseGlobally()
        }
        real.writeObjects([try fixture.file("Archive.zip") as NSURL])

        module.dragApproaching(standIn, at: CGPoint(x: 100, y: 100))
        #expect(module.convertZone == .ready)
        // Over the window, AppKit hands over the real pasteboard: a ZIP has nothing to become.
        module.dragApproaching(real, at: CGPoint(x: 100, y: 100))
        #expect(module.convertZone == .cantConvert)
        // The drag watcher keeps sending the stand-in; what the names said stays.
        module.dragApproaching(standIn, at: CGPoint(x: 100, y: 100))
        #expect(module.convertZone == .cantConvert)
        module.dragEnded()
        #expect(module.convertZone == nil)
    }
}
