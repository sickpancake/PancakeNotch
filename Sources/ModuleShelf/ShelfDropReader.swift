import AppKit
import UniformTypeIdentifiers

/// What a drop contained: content that's ready now, and promised files still to be received
/// (Photos, Mail attachments, Safari images).
@MainActor
struct ShelfDrop {
    var inputs: [ShelfInput] = []
    var promises: [NSFilePromiseReceiver] = []

    var isEmpty: Bool { inputs.isEmpty && promises.isEmpty }
}

/// Turns a drag pasteboard into Shelf content, one pasteboard item at a time:
/// real file → promised file → image data → link → text.
@MainActor
enum ShelfDropReader {
    /// Longer text is kept as a `.txt` file instead of inside the item list.
    static let textLimit = 100_000
    static let dataLimit = 4 * 1024 * 1024
    static let dropLimit = 8 * 1024 * 1024

    private static let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)
    private static let imageTypes: [(NSPasteboard.PasteboardType, String)] = [(.png, "png"), (.tiff, "tiff")]

    /// Whether the pasteboard holds anything the Shelf can take (checked while dragging, before reading).
    static func canRead(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else { return false }
        let accepted: Set<NSPasteboard.PasteboardType> = [.fileURL, .URL, .string, .png, .tiff]
        return types.contains { accepted.contains($0) || promiseTypes.contains($0.rawValue) }
    }

    /// Reads the drop. Image data and long text are written straight to disk (never decoded) via `newFolder`.
    static func read(_ pasteboard: NSPasteboard, newFolder: () throws -> URL) -> ShelfDrop {
        var drop = ShelfDrop()
        // One receiver per promised pasteboard item, in item order.
        var receivers = ((pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]) ?? [])
            .makeIterator()

        var remaining = dropLimit
        for item in (pasteboard.pasteboardItems ?? []).prefix(100) {
            let types = item.types
            let promise = types.contains { promiseTypes.contains($0.rawValue) } ? receivers.next() : nil

            // A real file wins over a promised copy: the Shelf keeps a reference, not a duplicate.
            if let string = string(item, type: .fileURL, remaining: &remaining), let url = URL(string: string), url.isFileURL {
                drop.inputs.append(.file(url.standardizedFileURL, owned: false))
            } else if let promise {
                drop.promises.append(promise)
            } else if let (data, ext) = imageData(item, remaining: &remaining) {
                if let url = try? write(data, name: String(localized: "Image") + "." + ext, newFolder: newFolder) {
                    drop.inputs.append(.file(url, owned: true))
                }
            } else if let string = string(item, type: .URL, remaining: &remaining), let url = webURL(string) {
                drop.inputs.append(.link(url))
            } else if let text = string(item, type: .string, remaining: &remaining), let input = textInput(text, newFolder: newFolder) {
                drop.inputs.append(input)
            }
        }
        return drop
    }

    private static func imageData(_ item: NSPasteboardItem, remaining: inout Int) -> (Data, String)? {
        for (type, ext) in imageTypes {
            if let data = data(item, type: type, remaining: &remaining) { return (data, ext) }
        }
        return nil
    }

    /// AppKit has no public size-only read. Check the returned bytes before decoding or copying,
    /// and bound the whole drop so many items cannot accumulate in memory.
    private static func data(_ item: NSPasteboardItem, type: NSPasteboard.PasteboardType, remaining: inout Int) -> Data? {
        autoreleasepool {
            guard remaining > 0, let data = item.data(forType: type), data.count <= min(dataLimit, remaining) else { return nil }
            remaining -= data.count
            return data
        }
    }

    private static func string(_ item: NSPasteboardItem, type: NSPasteboard.PasteboardType, remaining: inout Int) -> String? {
        guard let data = data(item, type: type, remaining: &remaining) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Plain text, a single link typed as text, or a `.txt` file when it's long.
    static func textInput(_ text: String, newFolder: () throws -> URL) -> ShelfInput? {
        guard text.utf8.count <= dataLimit else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains(where: \.isWhitespace), let url = webURL(trimmed) { return .link(url) }
        if trimmed.utf8.count > textLimit,
           let url = try? write(Data(trimmed.utf8), name: String(localized: "Text") + ".txt", newFolder: newFolder) {
            return .file(url, owned: true)
        }
        return .text(trimmed)
    }

    /// Only web and mail links become link items; anything else stays text.
    static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return nil }
        if scheme != "mailto", url.host() == nil { return nil }
        return url
    }

    private static func write(_ data: Data, name: String, newFolder: () throws -> URL) throws -> URL {
        let url = try newFolder().appending(path: name)
        try data.write(to: url)
        return url
    }

    /// Receives promised files on a background queue and reports each one (or `nil` on failure).
    /// `nonisolated` so the callback isn't tied to the main actor: AppKit calls it on `queue`.
    nonisolated static func receive(
        _ receiver: NSFilePromiseReceiver,
        into folder: URL,
        queue: OperationQueue,
        arrived: @escaping @Sendable (URL?) -> Void
    ) {
        receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) { url, error in
            guard error == nil else { arrived(nil); return }
            do {
                try quarantineIfNeeded(url)
                arrived(url)
            } catch { arrived(nil) }
        }
    }

    /// Promises can come from a browser or mail client. Preserve their existing provenance;
    /// otherwise mark the new file as quarantined before offering or sharing it.
    nonisolated static func quarantineIfNeeded(_ url: URL) throws {
        var file = url
        let existing = try file.resourceValues(forKeys: [.quarantinePropertiesKey])
        guard existing.quarantineProperties == nil else { return }
        var values = URLResourceValues()
        values.quarantineProperties = [
            "LSQuarantineAgentName": "PancakeNotch",
            "LSQuarantineType": "LSQuarantineTypeOtherDownload",
            "LSQuarantineTimeStamp": Date(),
        ]
        try file.setResourceValues(values)
    }

    /// How many files the promises will deliver (at least one each).
    static func expectedFileCount(_ promises: [NSFilePromiseReceiver]) -> Int {
        promises.reduce(0) { $0 + max(1, $1.fileNames.count) }
    }
}
