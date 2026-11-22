import Foundation
import Observation
import os

/// What happened to a note, for Learn and the statistics.
public enum NotesEvent: Equatable, Sendable {
    case created(Note.Source)
    case edited
    case pinned
    case unpinned
    case deleted
    case restored
}

/// The user's notes, saved as JSON in `~/Library/Application Support/PancakeNotch/Notes`. Practice
/// copies keep theirs in memory only.
@MainActor
@Observable
public final class NotesStore {
    /// The most notes kept; adding one more is refused so nothing is dropped silently.
    public static let capacity = 500

    public private(set) var notes: [Note] = []
    /// The note deleted last, until Undo brings it back or another note is deleted.
    public private(set) var lastDeleted: Note?

    /// `~/Library/Application Support/PancakeNotch/Notes`, or in testing builds `PANCAKENOTCH_NOTES_DIR`.
    public static var defaultDirectory: URL {
        #if PANCAKENOTCH_INTERNAL_TESTING
        if let path = ProcessInfo.processInfo.environment["PANCAKENOTCH_NOTES_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "PancakeNotch/Notes", directoryHint: .isDirectory)
    }

    /// Where the notes are saved; nil keeps them in memory (practice, snapshots).
    public let directory: URL?
    @ObservationIgnored public var onEvent: ((NotesEvent) -> Void)?
    /// Also told after every change: each Notes module showing this store.
    @ObservationIgnored private var observers: [ObjectIdentifier: () -> Void] = [:]
    @ObservationIgnored private let clock: @Sendable () -> Date
    /// The saved file couldn't be read: it's kept aside rather than overwritten.
    @ObservationIgnored private var keepsUnreadable = false
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "notes")

    private var fileURL: URL? { directory?.appending(path: "notes.json") }

    public init(directory: URL? = NotesStore.defaultDirectory, notes: [Note] = [], now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory
        self.clock = now
        self.notes = notes
        guard let fileURL, notes.isEmpty else { return }
        do {
            self.notes = try JSONDecoder().decode([Note].self, from: Data(contentsOf: fileURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        } catch {
            logger.error("Notes couldn't be read: \(error.localizedDescription, privacy: .public)")
            keepsUnreadable = true
        }
    }

    /// An in-memory store with a few notes, for practice copies and snapshots.
    public static func practice(now: Date = Date()) -> NotesStore {
        let day: TimeInterval = 86_400
        let notes = [
            Note(text: String(localized: "Groceries\nEggs, flour, maple syrup, blueberries"),
                 created: now - 2 * day, modified: now - 3600, isPinned: true),
            Note(text: String(localized: "Ideas for the weekend\nTry the new pancake place, call Sam"),
                 created: now - day, modified: now - 5 * 3600),
            Note(text: String(localized: "Meeting notes.txt\nShip the beta on Friday. Ask about the icons."),
                 created: now - 3 * day, modified: now - 3 * day, source: .shelf(fileName: "Meeting notes.txt"))
        ]
        return NotesStore(directory: nil, notes: notes, now: { now })
    }

    /// The store's clock (fixed in practice copies and snapshots).
    public var now: Date { clock() }

    public var isFull: Bool { notes.count >= Self.capacity }
    public var pinnedCount: Int { notes.lazy.filter(\.isPinned).count }

    public func note(_ id: Note.ID) -> Note? {
        notes.first { $0.id == id }
    }

    /// The notes in the chosen order, pinned ones first.
    public func sorted(_ sort: NotesSort) -> [Note] {
        notes.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            switch sort {
            case .recentlyEdited: return a.modified > b.modified
            case .newestFirst: return a.created > b.created
            case .oldestFirst: return a.created < b.created
            }
        }
    }

    /// Adds a note. Empty text makes an empty note only when typed (you're about to write in it).
    @discardableResult
    public func add(_ text: String = "", source: Note.Source = .typed) -> Note? {
        guard !isFull else { return nil }
        let cleaned = text.replacingOccurrences(of: "\r\n", with: "\n")
        if source != .typed, cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        let note = Note(text: cleaned, created: clock(), source: source)
        notes.append(note)
        changed()
        onEvent?(.created(source))
        return note
    }

    /// Adds several notes made from dropped text, as many as fit. Returns how many were added.
    @discardableResult
    public func add(_ texts: [(text: String, source: Note.Source)]) -> Int {
        texts.reduce(0) { count, item in add(item.text, source: item.source) == nil ? count : count + 1 }
    }

    public func update(_ id: Note.ID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].modified = clock()
        changed()
        onEvent?(.edited)
    }

    public func togglePin(_ id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
        changed()
        onEvent?(notes[index].isPinned ? .pinned : .unpinned)
    }

    public func delete(_ id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes.remove(at: index)
        // An empty note leaves nothing to undo.
        lastDeleted = note.isEmpty ? lastDeleted : note
        changed()
        onEvent?(.deleted)
    }

    /// Brings back the note deleted last.
    public func undoDelete() {
        guard let note = lastDeleted, !isFull else { return }
        lastDeleted = nil
        notes.append(note)
        changed()
        onEvent?(.restored)
    }

    /// Forgets the deleted note (the Undo offer ends).
    public func clearUndo() {
        lastDeleted = nil
    }

    /// Removes notes left empty (a new note closed without writing in it).
    public func removeEmpty(except keep: Note.ID? = nil) {
        let before = notes.count
        notes.removeAll { $0.isEmpty && $0.id != keep }
        if notes.count != before { changed() }
    }

    public func observe(_ owner: AnyObject, _ handler: @escaping () -> Void) {
        observers[ObjectIdentifier(owner)] = handler
    }

    public func stopObserving(_ owner: AnyObject) {
        observers[ObjectIdentifier(owner)] = nil
    }

    private func changed() {
        save()
        for handler in observers.values { handler() }
    }

    private func save() {
        guard let directory, let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if keepsUnreadable {
                let aside = directory.appending(path: "notes-unreadable-\(Int(clock().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: fileURL, to: aside)
                keepsUnreadable = false
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(notes).write(to: fileURL, options: [.atomic])
        } catch {
            logger.error("Notes couldn't be saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
