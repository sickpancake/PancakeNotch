import Foundation
import Observation
import os

/// The Shelf's items, newest first, saved to `items.json` in the Shelf folder (ADR-0013).
///
/// Files are kept as bookmarks (references), so they follow moves and renames. Items the Shelf owns
/// (promised files, dropped image data, long text) live in `Files/<id>/` and are deleted with their item.
@MainActor
@Observable
public final class ShelfStore {
    public static let capacity = 20
    /// From this many items the notch shows the Shelf in its compact ear (ADR-0013).
    public static let nearlyFullCount = 15

    public private(set) var items: [ShelfItem] = []

    /// `~/Library/Application Support/PancakeNotch/Shelf`, or `PANCAKENOTCH_SHELF_DIR` (tests, memory checks).
    public static var defaultDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["PANCAKENOTCH_SHELF_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "PancakeNotch/Shelf", directoryHint: .isDirectory)
    }

    public let directory: URL
    /// Where owned files live: one subfolder per item.
    public var filesDirectory: URL { directory.appending(path: "Files", directoryHint: .isDirectory) }
    private var indexURL: URL { directory.appending(path: "items.json") }

    /// Called after every change (the module updates its "Full" ears).
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "shelf")

    /// Loads the saved items. Only reads our own JSON: no bookmark is resolved at launch, so macOS
    /// doesn't ask about Desktop/Documents access and unplugged drives can't stall startup.
    public init(directory: URL = ShelfStore.defaultDirectory, now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory
        self.now = now
        if let data = try? Data(contentsOf: indexURL) {
            do {
                items = try JSONDecoder().decode([ShelfItem].self, from: data)
            } catch {
                logger.error("Shelf index unreadable, starting empty: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    public var isFull: Bool { items.count >= Self.capacity }

    // MARK: Adding

    public enum AddResult: Equatable, Sendable {
        /// Everything that fit was added (or moved to the front).
        case done(added: Int)
        /// Some of the content is already on the shelf and the policy is `.ask`: nothing changed.
        case duplicates(count: Int)
        /// The shelf filled up: `pending` didn't fit and is waiting for room.
        case overflow(added: Int, pending: [ShelfInput])
    }

    /// Adds content in the order given, newest first, following the duplicate policy and the 20-item cap.
    @discardableResult
    public func add(_ inputs: [ShelfInput], duplicates policy: ShelfSettings.DuplicatePolicy) -> AddResult {
        var seen = Set<String>()
        let batch = inputs.filter { seen.insert($0.key).inserted }
        var existing: [String: UUID] = [:]
        for item in items where existing[item.key] == nil { existing[item.key] = item.id }

        let duplicates = batch.filter { existing[$0.key] != nil }
        var fresh = batch
        switch policy {
        case .ask where !duplicates.isEmpty:
            return .duplicates(count: duplicates.count)
        case .ask, .moveToFront:
            fresh = batch.filter { existing[$0.key] == nil }
            let ids = duplicates.compactMap { existing[$0.key] }
            let moved = ids.compactMap { id in items.first { $0.id == id } }
            items.removeAll { ids.contains($0.id) }
            items.insert(contentsOf: moved, at: 0)
        case .addAgain:
            break
        }

        let room = max(0, Self.capacity - items.count)
        let added = fresh.prefix(room).compactMap(makeItem)
        let pending = Array(fresh.dropFirst(room))
        items.insert(contentsOf: added, at: 0)
        save()
        return pending.isEmpty ? .done(added: added.count) : .overflow(added: added.count, pending: pending)
    }

    private func makeItem(_ input: ShelfInput) -> ShelfItem? {
        switch input {
        case .text(let text):
            return ShelfItem(kind: .text(text), addedAt: now())
        case .link(let url):
            return ShelfItem(kind: .link(url), addedAt: now())
        case .file(let url, let owned):
            do {
                let bookmark = try url.bookmarkData()
                return ShelfItem(kind: .file(bookmark: bookmark, owned: owned), path: url.resolvingSymlinksInPath().path, addedAt: now())
            } catch {
                logger.error("Couldn't keep \(url.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .private)")
                if owned { deleteOwnedFile(at: url) }
                return nil
            }
        }
    }

    // MARK: Removing

    public func remove(_ ids: some Collection<UUID>) {
        let ids = Set(ids)
        guard !ids.isEmpty else { return }
        for item in items where ids.contains(item.id) && item.isOwnedFile {
            if let url = item.fileURL { deleteOwnedFile(at: url) }
        }
        items.removeAll { ids.contains($0.id) }
        save()
    }

    public func clear() {
        remove(items.map(\.id))
    }

    /// Content that will never be added (the "Shelf is full" card was closed): delete its owned files.
    public func discard(_ inputs: [ShelfInput]) {
        for case .file(let url, true) in inputs { deleteOwnedFile(at: url) }
    }

    /// Deletes an owned file's folder, but only while it's still inside our `Files` folder:
    /// after a "move" drag-out it belongs to the user.
    private func deleteOwnedFile(at url: URL) {
        let files = filesDirectory.resolvingSymlinksInPath().path + "/"
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(files) else { return }
        let relative = path.dropFirst(files.count)
        guard let folder = relative.split(separator: "/").first else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: files + folder))
    }

    /// Deletes owned files no item points to (e.g. waiting files when the app quit with a card open).
    /// Only looks inside our own `Files` folder, so it's safe at launch.
    public func removeOrphanedFiles() {
        let files = filesDirectory.resolvingSymlinksInPath().path + "/"
        let used = Set(items.compactMap { item -> String? in
            guard item.isOwnedFile, let path = item.path else { return nil }
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard resolved.hasPrefix(files) else { return nil }
            return resolved.dropFirst(files.count).split(separator: "/").first.map(String.init)
        })
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: files)) ?? []
        for folder in folders where !used.contains(folder) {
            try? FileManager.default.removeItem(atPath: files + folder)
        }
    }

    // MARK: Editing

    /// Replaces a text or link item's content (the editor). With `save: false` the change stays in memory
    /// while typing; `saveEdits()` writes it.
    public func update(_ id: UUID, kind: ShelfItem.Kind, save shouldSave: Bool = true) {
        guard let index = items.firstIndex(where: { $0.id == id }), !items[index].isFile,
              items[index].kind != kind else { return }
        items[index].kind = kind
        hasUnsavedEdits = !shouldSave
        if shouldSave { save() }
    }

    /// Writes edits kept in memory by `update(_:kind:save:)`.
    public func saveEdits() {
        guard hasUnsavedEdits else { return }
        hasUnsavedEdits = false
        save()
    }

    @ObservationIgnored private var hasUnsavedEdits = false

    // MARK: Checking

    /// Follows moved and renamed files, removes items whose file is gone, and clears items older than
    /// `maxAge` (auto-clear). Runs when the notch opens; bookmarks are resolved off the main thread.
    public func prune(maxAge: TimeInterval?) async {
        let cutoff = maxAge.map { now().addingTimeInterval(-$0) }
        let expired = items.filter { item in cutoff.map { item.addedAt < $0 } ?? false }.map(\.id)
        let bookmarks: [(UUID, Data)] = items.compactMap { item in
            guard case .file(let bookmark, _) = item.kind else { return nil }
            return (item.id, bookmark)
        }
        let resolved = await Task.detached(priority: .utility) {
            bookmarks.map { ($0.0, ShelfBookmark.resolve($0.1)) }
        }.value

        var missing: [UUID] = []
        var changed = false
        for (id, resolution) in resolved {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            switch resolution {
            case .missing:
                missing.append(id)
            case .unavailable:
                break // On a drive that isn't plugged in: keep it.
            case .found(let path, let refreshed):
                if items[index].path != path {
                    items[index].path = path
                    changed = true
                }
                if let refreshed, case .file(_, let owned) = items[index].kind {
                    items[index].kind = .file(bookmark: refreshed, owned: owned)
                    changed = true
                }
            }
        }
        let gone = Set(missing).union(expired)
        if !gone.isEmpty {
            // Missing files have nothing left to delete; expired owned files do.
            remove(gone)
        } else if changed {
            save()
        }
    }

    /// The item's file right now, following a move if needed.
    public func resolvedURL(for item: ShelfItem) -> URL? {
        guard case .file(let bookmark, _) = item.kind else { return nil }
        if case .found(let path, _) = ShelfBookmark.resolve(bookmark) { return URL(fileURLWithPath: path) }
        return nil
    }

    // MARK: Saving

    private func save() {
        hasUnsavedEdits = false
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: indexURL, options: .atomic)
        } catch {
            logger.error("Couldn't save the Shelf: \(error.localizedDescription, privacy: .private)")
        }
        onChange?()
    }

    /// A new, empty folder inside `Files` for one owned item.
    public func newFilesFolder() throws -> URL {
        let folder = filesDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

/// Resolving bookmarks without touching the main actor.
enum ShelfBookmark {
    enum Resolution: Sendable, Equatable {
        case found(path: String, refreshed: Data?)
        /// The file's drive isn't mounted.
        case unavailable
        case missing
    }

    static func resolve(_ bookmark: Data) -> Resolution {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            let volume = URL.resourceValues(forKeys: [.volumeURLKey], fromBookmarkData: bookmark)?.volume
            if let volume, !FileManager.default.fileExists(atPath: volume.path) { return .unavailable }
            return .missing
        }
        let path = url.path
        // A trashed file still resolves; treat it as deleted.
        guard FileManager.default.fileExists(atPath: path), !path.contains("/.Trash/") else { return .missing }
        return .found(path: path, refreshed: isStale ? try? url.bookmarkData() : nil)
    }
}
