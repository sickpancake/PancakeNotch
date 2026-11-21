import AppKit
import ConvertKit
import NotchCore
import UniformTypeIdentifiers

/// Demo Shelf states for the off-screen snapshot (`PANCAKENOTCH_SNAPSHOT`). Everything lives in a
/// temporary folder; the user's real Shelf is never touched.
@MainActor
public enum ShelfSnapshot {
    /// A Shelf with `count` empty example files in a temporary folder (removed when the store is),
    /// e.g. a nearly full one next to Now Playing.
    public static func module(itemCount count: Int) -> ShelfModule {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PancakeNotch-shelf-snapshot-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder.appending(path: "Docs"), withIntermediateDirectories: true)
        let store = ShelfStore(directory: folder.appending(path: "Shelf"))
        let inputs = (0..<count).map { index -> ShelfInput in
            let url = folder.appending(path: "Docs/File \(index + 1).pdf")
            FileManager.default.createFile(atPath: url.path, contents: Data())
            return .file(url, owned: false)
        }
        store.add(inputs, duplicates: .addAgain)
        let settings = ShelfSettings(defaults: UserDefaults(suiteName: "io.github.sickpancake.PancakeNotch.snapshots.shelf") ?? .standard)
        let module = ShelfModule(store: store, settings: settings)
        module.isSnapshot = true
        return module
    }

    public static func models(layout: NotchLayout) -> [NotchViewModel] {
        let root = FileManager.default.temporaryDirectory.appending(path: "PancakeNotch-shelf-snapshot-\(UUID().uuidString)")
        var rows: [NotchViewModel] = []

        func row(_ state: NotchState = .expanded, files: [String] = [], extra: [ShelfInput] = [], setUp: (ShelfModule) -> Void = { _ in }) {
            let folder = root.appending(path: "\(rows.count)")
            try? FileManager.default.createDirectory(at: folder.appending(path: "Docs"), withIntermediateDirectories: true)
            let store = ShelfStore(directory: folder.appending(path: "Shelf"))
            let inputs = files.map { name -> ShelfInput in
                let url = folder.appending(path: "Docs/\(name)")
                FileManager.default.createFile(atPath: url.path, contents: Data())
                return .file(url, owned: false)
            }
            store.add(inputs + extra, duplicates: .addAgain)
            let settings = ShelfSettings(defaults: UserDefaults(suiteName: "io.github.sickpancake.PancakeNotch.snapshots.shelf") ?? .standard)
            let module = ShelfModule(store: store, settings: settings)
            module.isSnapshot = true
            module.thumbnails.preload(Dictionary(uniqueKeysWithValues: store.items.compactMap { item in
                item.fileURL.map { (item.id, NSWorkspace.shared.icon(for: UTType(filenameExtension: $0.pathExtension) ?? .data)) }
            }))
            let model = NotchViewModel(layout: layout, state: state)
            model.module = module
            setUp(module)
            rows.append(model)
        }

        let files = ["Quarterly Report.pdf", "Holiday.jpg", "Archive.zip", "Slides.key", "Notes.md", "Song.mp3", "Budget.numbers"]
        let extras: [ShelfInput] = [.text("Pick up the cake at 5, and don't forget the candles"), .link(URL(string: "https://github.com/sickpancake")!)]

        row()
        row(files: Array(files.prefix(4)), extra: extras) { module in
            module.selection = Set(module.store.items.prefix(2).map(\.id))
        }
        row { module in
            module.dropZone = .airDrop
            module.dragCanAirDrop = true
        }
        row(files: ["Report.pdf"]) { module in
            module.prompt = .duplicates(inputs: [], count: 1)
        }
        let full = (1...20).map { "File \($0).pdf" }
        row(files: full) { module in
            module.prompt = .full(pending: [.text("a"), .text("b")])
        }
        row(files: full) { module in
            module.prompt = .choosing(pending: [.text("a")])
            module.selection = Set(module.store.items.prefix(3).map(\.id))
        }
        row(.compact, files: full)
        row(.compact, files: Array(full.prefix(16)))
        row(.compact, files: Array(full.prefix(3)))
        row(.compact)
        row(files: files, extra: extras) { module in
            module.confirmingClear = true
            module.copiedID = module.store.items.first(where: { !$0.isFile })?.id
        }

        // The tall notch: text editor, link editor, file preview.
        let note = "Pick up the cake at 5, and don't forget the candles.\n\nAlso: call the bakery about the gluten-free one, and check if the shop on the corner still sells the sparkly number candles."
        for input: ShelfInput in [.text(note), .link(URL(string: "https://github.com/sickpancake/PancakeNotch")!)] {
            row(extra: [input]) { module in
                module.detailID = module.store.items.first?.id
            }
        }
        row(files: ["Quarterly Report.pdf"]) { module in
            module.detailID = module.store.items.first?.id
            module.largePreview.preload(NSWorkspace.shared.icon(for: .pdf))
        }

        // Convert (ADR-0038): the drop zone (and dimmed for files with no other format), then the row of
        // formats in the medium panel, converting, done, failed, and the strip when it ends out of sight.
        for zone in [ShelfModule.ConvertZone.ready, .cantConvert] {
            row { module in
                module.dropZone = zone == .ready ? .convert : .shelf
                module.convertZone = zone
                module.dragCanAirDrop = true
            }
        }
        func convert(_ module: ShelfModule, _ names: [String], _ options: [ConvertOption], _ phase: ShelfConversion.Phase, progress: Double = 0) {
            let session = ShelfConversion(sources: names.map { root.appending(path: "Docs/\($0)") }, phase: phase)
            session.options = options
            session.focus = options.first(where: \.isAvailable)?.format
            session.progress = progress
            module.conversion = session
            module.notch?.setPanelHeight(.medium)
        }
        let photo: [ConvertOption] = [
            ConvertOption(format: .jpeg), ConvertOption(format: .png, note: .tooBig), ConvertOption(format: .tiff, note: .tooBig),
            ConvertOption(format: .pdf),
        ]
        row(files: files) { module in
            convert(module, ["Holiday.heic"], photo, .choosing)
        }
        row(files: files) { module in
            convert(module, ["Holiday.heic", "Receipt.jpg", "Ticket.pdf"], [ConvertOption(format: .combinedPDF)], .choosing)
        }
        row(files: files) { module in
            let clip: [ConvertOption] = [ConvertOption(format: .mp4), ConvertOption(format: .audioOnly), ConvertOption(format: .gif, note: .tooLong)]
            convert(module, ["Birthday.mov"], clip, .converting(.mp4), progress: 0.42)
        }
        row(files: ["Holiday.jpg"]) { module in
            let made = module.store.items.compactMap(\.fileURL)
            convert(module, ["Holiday.heic"], photo, .done(ShelfConversion.Done(format: .jpeg, files: made, failed: 0, keptInShelf: false)))
        }
        row { module in
            convert(module, ["Holiday.heic"], photo, .failed(ConvertFailure.failed.message))
        }
        row(.compact, files: Array(full.prefix(3))) { module in
            module.convertPeekText = ShelfModule.doneText(files: [URL(fileURLWithPath: "/Report.pdf")])
            module.notch?.peekForSnapshot(module)
        }

        // The app window's preview: example items, open and shrunk.
        for state in [NotchState.expanded, .compact] {
            let model = NotchViewModel(layout: layout, state: state)
            model.module = ShelfPreviewModule()
            rows.append(model)
        }

        try? FileManager.default.removeItem(at: root)
        return rows
    }
}
