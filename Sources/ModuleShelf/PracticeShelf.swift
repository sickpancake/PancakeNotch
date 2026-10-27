import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// A throwaway Shelf for the app window: the real Shelf UI on its own temporary folder and settings,
/// so people can try everything without touching their real Shelf.
///
/// Everything lives in `$TMPDIR/PancakeNotch-practice-<UUID>/`: the Shelf's own folder (`Shelf`) and
/// the example files it points to (`Examples`). The settings live in their own `UserDefaults` suite
/// with the same UUID, so `removeLeftovers()` can clear both after a crash.
@MainActor
@Observable
public final class PracticeShelf {
    public let module: ShelfModule

    /// Folder names start with this, followed by the UUID that also names the settings suite.
    nonisolated static let folderPrefix = "PancakeNotch-practice-"
    nonisolated static let suitePrefix = "io.github.sickpancake.PancakeNotch.practice."

    /// Practice folders open in this process: `removeLeftovers()` keeps them.
    private static var openFolders: Set<String> = []

    @ObservationIgnored let folder: URL
    @ObservationIgnored private let suiteName: String
    @ObservationIgnored private var isClosed = false
    private var examplesFolder: URL { folder.appending(path: "Examples", directoryHint: .isDirectory) }

    /// `seeded`: four example items (a PDF, a photo, a note and a link). Otherwise the Shelf starts empty.
    public init(seeded: Bool) {
        let id = UUID().uuidString
        folder = FileManager.default.temporaryDirectory.appending(path: Self.folderPrefix + id, directoryHint: .isDirectory)
        suiteName = Self.suitePrefix + id
        Self.openFolders.insert(folder.lastPathComponent)

        let defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults()
        let settings = ShelfSettings(defaults: defaults)
        settings.dragOutMode = .copy
        settings.removeAfterDragOut = false
        settings.duplicatePolicy = .addAgain
        settings.autoClear = .never
        settings.showsAirDropZone = false

        let store = ShelfStore(directory: folder.appending(path: "Shelf", directoryHint: .isDirectory))
        module = ShelfModule(store: store, settings: settings)
        module.dragsOutWithinApp = true
        // Converting here leaves nothing behind: what it makes goes in the practice folder.
        module.keepsConvertedFiles = true
        if seeded { seed(store) }
    }

    private func seed(_ store: ShelfStore) {
        var inputs: [ShelfInput] = []
        if let report = write(String(localized: "Report.pdf"), PracticeFiles.pdf(pageSize: CGSize(width: 612, height: 792))) {
            inputs.append(.file(report, owned: false))
        }
        if let photo = write(String(localized: "Holiday.jpg"), PracticeFiles.landscapeJPEG()) {
            inputs.append(.file(photo, owned: false))
        }
        inputs.append(.text(String(localized: "Pick up the cake at 5")))
        if let link = URL(string: "https://github.com") { inputs.append(.link(link)) }
        // One batch keeps this order on the Shelf: the report first.
        store.add(inputs, duplicates: .addAgain)
    }

    /// Files the lesson offers to drag onto the notch, created on demand in the practice folder
    /// (and again if one went missing).
    public func practiceFiles() -> [URL] {
        guard !isClosed else { return [] }
        let files: [(name: String, contents: () -> Data?)] = [
            (String(localized: "Notes.txt"), { Data(String(localized: "Drag me onto the notch to keep me on the Shelf.").utf8) }),
            (String(localized: "Photo.jpg"), { PracticeFiles.portraitJPEG() }),
            (String(localized: "Slides.pdf"), { PracticeFiles.pdf(pageSize: CGSize(width: 792, height: 612)) }),
        ]
        return files.compactMap { file in
            let url = examplesFolder.appending(path: file.name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
            return write(file.name, file.contents())
        }
    }

    /// Writes an example file into `Examples`; nil if it couldn't.
    private func write(_ name: String, _ data: Data?) -> URL? {
        guard let data else { return nil }
        let url = examplesFolder.appending(path: name)
        do {
            try FileManager.default.createDirectory(at: examplesFolder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Opens an item's big view, as a click would (snapshots show the tall notch with it).
    public func openItem(at index: Int) {
        guard module.store.items.indices.contains(index) else { return }
        module.activate(module.store.items[index].id)
    }

    /// Deletes the folder and settings. Called when the page goes away; safe to call twice.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        module.onEvent = nil
        // Quick Look doesn't retain its data source: it mustn't outlive this Shelf.
        module.quickLook.closeIfShowing()
        // An open note saves when its view closes: do that first, so the save can't bring the folder back.
        module.clickedOutsidePreview()
        // Stops a conversion still running, so its helper doesn't write into the folder being removed.
        module.endConversion()
        Self.openFolders.remove(folder.lastPathComponent)
        try? FileManager.default.removeItem(at: folder)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    /// Removes practice folders (and their settings) left behind by a crash. Call at launch.
    public static func removeLeftovers() {
        removeLeftovers(in: FileManager.default.temporaryDirectory)
    }

    static func removeLeftovers(in directory: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(folderPrefix) && !openFolders.contains(name) {
            try? FileManager.default.removeItem(at: directory.appending(path: name, directoryHint: .isDirectory))
            let id = name.dropFirst(folderPrefix.count)
            if UUID(uuidString: String(id)) != nil {
                let suite = suitePrefix + id
                UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            }
        }
    }
}

/// Small example files drawn with Core Graphics: no bundled resources.
enum PracticeFiles {
    /// A one-page document: a title line and a few gray text lines, black on white.
    static func pdf(pageSize: CGSize) -> Data? {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        context.beginPDFPage(nil)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(box)

        let margin = pageSize.width * 0.12
        let width = pageSize.width - 2 * margin
        var y = pageSize.height - margin - 22
        // The title.
        context.setFillColor(gray: 0.1, alpha: 1)
        context.fill(CGRect(x: margin, y: y, width: width * 0.55, height: 22))
        y -= 44
        // Paragraphs of "text".
        context.setFillColor(gray: 0.72, alpha: 1)
        for paragraph in 0..<3 {
            for line in 0..<4 {
                let last = line == 3
                let lineWidth = last ? width * (0.45 + 0.12 * CGFloat(paragraph)) : width
                context.fill(CGRect(x: margin, y: y, width: lineWidth, height: 9))
                y -= 18
            }
            y -= 18
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// "Holiday.jpg": a soft landscape (pale sky, sun, layered gray hills), 600×400.
    static func landscapeJPEG() -> Data? {
        jpeg(width: 600, height: 400) { context, size in
            let space = CGColorSpaceCreateDeviceRGB()
            // Sky: a faint cool tint at the top fading to white at the horizon.
            if let sky = CGGradient(colorsSpace: space, colors: [
                CGColor(red: 0.80, green: 0.85, blue: 0.90, alpha: 1),
                CGColor(red: 0.97, green: 0.97, blue: 0.96, alpha: 1),
            ] as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(sky, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: size.height * 0.35), options: [.drawsAfterEndLocation])
            }
            // Sun.
            context.setFillColor(CGColor(red: 1, green: 0.98, blue: 0.93, alpha: 1))
            context.fillEllipse(in: CGRect(x: size.width * 0.66, y: size.height * 0.62, width: 70, height: 70))
            // Hills, back to front, darker as they come closer.
            let hills: [(base: CGFloat, height: CGFloat, phase: CGFloat, gray: CGFloat)] = [
                (0.42, 0.14, 0.0, 0.74),
                (0.30, 0.12, 1.7, 0.58),
                (0.16, 0.10, 3.1, 0.40),
            ]
            for hill in hills {
                context.beginPath()
                context.move(to: .zero)
                for step in 0...60 {
                    let x = size.width * CGFloat(step) / 60
                    let wave = sin(CGFloat(step) / 60 * .pi * 2 + hill.phase) * 0.5 + 0.5
                    context.addLine(to: CGPoint(x: x, y: size.height * (hill.base + hill.height * wave)))
                }
                context.addLine(to: CGPoint(x: size.width, y: 0))
                context.closePath()
                context.setFillColor(gray: hill.gray, alpha: 1)
                context.fillPath()
            }
        }
    }

    /// "Photo.jpg": a calm gray study (a pebble on a gradient), 400×500.
    static func portraitJPEG() -> Data? {
        jpeg(width: 400, height: 500) { context, size in
            let space = CGColorSpaceCreateDeviceGray()
            if let background = CGGradient(colorsSpace: space, colors: [
                CGColor(gray: 0.92, alpha: 1), CGColor(gray: 0.62, alpha: 1),
            ] as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(background, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
            }
            context.setFillColor(gray: 0.55, alpha: 0.35)
            context.fillEllipse(in: CGRect(x: 110, y: 120, width: 190, height: 40))
            context.setFillColor(gray: 0.22, alpha: 1)
            context.fillEllipse(in: CGRect(x: 120, y: 140, width: 160, height: 120))
        }
    }

    private static func jpeg(width: Int, height: Int, draw: (CGContext, CGSize) -> Void) -> Data? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        draw(context, CGSize(width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
