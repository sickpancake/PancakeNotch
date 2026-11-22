import AppKit
import NotchCore
import NotesCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Notes in the notch: a list of notes beside an editor. Typing takes the keyboard while the notch is
/// open; dropped text and text files become notes.
@MainActor
@Observable
public final class NotesModule: NotchModule {
    public let store: NotesStore
    public let settings: NotesSettings

    @ObservationIgnored public private(set) weak var notch: NotchViewModel?
    /// The note shown in the editor.
    public internal(set) var selectedID: Note.ID?
    /// The editor has the keyboard: the notch stays open until you click away or press Esc.
    public internal(set) var isEditing = false
    /// Text is being dragged over the page.
    public internal(set) var isDropTargeted = false
    /// The last drop added nothing (empty text, too big a file) or the list is full.
    public internal(set) var dropRefused = false
    @ObservationIgnored public var isSnapshot = false

    public init(store: NotesStore, settings: NotesSettings) {
        self.store = store
        self.settings = settings
    }

    // MARK: NotchModule

    public var moduleID: String { "notes" }
    public var title: String { String(localized: "Notes", comment: "Module name") }
    public var symbol: String { "note.text" }

    public var menuStatus: String? {
        store.notes.isEmpty ? nil : NotesText.count(store.notes.count)
    }

    public var holdsOpen: Bool { isEditing }

    public func attach(to notch: NotchViewModel?) {
        self.notch = notch
        if notch == nil {
            store.stopObserving(self)
        } else {
            store.observe(self) { [weak self] in self?.storeChanged() }
        }
    }

    /// The page came up after a click (a Notes tab, or the notch opened on Notes): take the keyboard so
    /// ⌘N, Return and the arrows work. A hover leaves the keyboard with the app you were typing in.
    func pageShown() {
        guard !isSnapshot, let type = NSApp.currentEvent?.type,
              [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp].contains(type) else { return }
        notch?.requestKeyFocus?()
    }

    /// A click on the page itself.
    func pageClicked() {
        guard !isSnapshot else { return }
        notch?.requestKeyFocus?()
    }

    public func expandedView(layout: NotchLayout) -> AnyView {
        AnyView(NotesView(module: self, layout: NotesLayout(layout)))
    }

    public func notchDidOpen() {
        guard notch?.selectedModule === self, notch?.showsHome != true else { return }
        if settings.opensNewNote, !isSnapshot { newNote() }
    }

    public func notchDidClose() {
        stopEditing()
        store.removeEmpty()
        store.clearUndo()
        dropRefused = false
    }

    public func userSwitchedAway() {
        stopEditing()
        store.removeEmpty()
    }

    public func clickedOutsidePreview() {
        stopEditing()
    }

    public func keyFocusLost() {
        stopEditing()
    }

    public func handleKey(_ event: NSEvent) -> Bool {
        if isEditing {
            if event.keyCode == 53 { // Esc leaves the editor
                stopEditing()
                return true
            }
            // The app usually isn't active, so the Edit menu may not see ⌘Z/⌘C/…: pass them to the editor.
            if let action = Self.editAction(for: event) { return NSApp.sendAction(action, to: nil, from: nil) }
            return false
        }
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 45 where command: // ⌘N
            newNote()
            return true
        case 36, 76: // Return: write in the shown note
            guard selectedNote != nil else { return false }
            startEditing()
            return true
        case 51 where command, 117: // ⌘Delete, Forward Delete
            guard let id = selectedNote?.id else { return false }
            delete(id)
            return true
        case 125, 126: // Down, Up: the next or previous note
            moveSelection(by: event.keyCode == 125 ? 1 : -1)
            return true
        default:
            return false
        }
    }

    // MARK: Drops

    public func canAcceptDrag(_ pasteboard: NSPasteboard) -> Bool {
        !Self.texts(on: pasteboard, includingText: true).isEmpty || Self.hasTextFiles(pasteboard)
    }

    public func dragUpdated(_ info: any NSDraggingInfo, at point: CGPoint) -> NSDragOperation {
        let accepts = canAcceptDrag(info.draggingPasteboard)
        if isDropTargeted != accepts { isDropTargeted = accepts }
        return accepts ? .copy : []
    }

    public func dragEnded() {
        isDropTargeted = false
    }

    public func performDrop(_ info: any NSDraggingInfo, at point: CGPoint) -> Bool {
        isDropTargeted = false
        let texts = Self.texts(on: info.draggingPasteboard, includingText: true)
        let before = store.notes.count
        let added = store.add(texts.map { (text: $0.text, source: $0.fileName.map(Note.Source.file) ?? .dropped) })
        dropRefused = added == 0
        if added > 0 {
            notch?.userInteracted()
            selectedID = store.notes.dropFirst(before).last?.id
        }
        return added > 0
    }

    /// The text a drop carries: plain text files, then plain text (links are left out: they're not notes).
    public static func texts(on pasteboard: NSPasteboard, includingText: Bool) -> [(text: String, fileName: String?)] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let files = urls.compactMap { url in NotesImport.text(of: url).map { (text: $0, fileName: Optional(url.lastPathComponent)) } }
        if !urls.isEmpty { return files }
        guard includingText, let string = pasteboard.string(forType: .string),
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !Self.isLink(string) else { return [] }
        return [(string, nil)]
    }

    private static func hasTextFiles(_ pasteboard: NSPasteboard) -> Bool {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.contains(where: NotesImport.isTextFile)
    }

    static func isLink(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme) && url.host() != nil || scheme == "mailto"
    }

    // MARK: Actions

    public var notes: [Note] { store.sorted(settings.sort) }

    public var selectedNote: Note? {
        selectedID.flatMap(store.note) ?? notes.first
    }

    public func newNote() {
        notch?.userInteracted()
        store.removeEmpty()
        guard let note = store.add() else { return }
        selectedID = note.id
        startEditing()
    }

    public func select(_ id: Note.ID) {
        notch?.userInteracted()
        if selectedID != id { store.removeEmpty(except: id) }
        selectedID = id
    }

    public func startEditing() {
        guard !isSnapshot, selectedNote != nil else { return }
        if selectedID == nil { selectedID = selectedNote?.id }
        isEditing = true
        notch?.requestKeyFocus?()
    }

    public func stopEditing() {
        guard isEditing else { return }
        isEditing = false
        notch?.holdReleased()
    }

    public func edit(_ id: Note.ID, text: String) {
        store.update(id, text: text)
    }

    public func togglePin(_ id: Note.ID) {
        notch?.userInteracted()
        store.togglePin(id)
    }

    public func delete(_ id: Note.ID) {
        notch?.userInteracted()
        let list = notes
        let index = list.firstIndex { $0.id == id }
        store.delete(id)
        if selectedID == id || selectedID == nil {
            let remaining = notes
            selectedID = index.flatMap { remaining.indices.contains($0) ? remaining[$0].id : remaining.last?.id }
        }
        stopEditing()
    }

    public func undoDelete() {
        notch?.userInteracted()
        let id = store.lastDeleted?.id
        store.undoDelete()
        if let id { selectedID = id }
    }

    public func copy(_ id: Note.ID) {
        guard let note = store.note(id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.text, forType: .string)
    }

    private func moveSelection(by step: Int) {
        let list = notes
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selectedNote?.id } ?? 0
        let next = min(max(current + step, 0), list.count - 1)
        select(list[next].id)
    }

    private func storeChanged() {
        if let id = selectedID, store.note(id) == nil { selectedID = nil }
    }

    static func editAction(for event: NSEvent) -> Selector? {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == .command || modifiers == [.command, .shift] else { return nil }
        let shift = modifiers.contains(.shift)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z": return shift ? Selector(("redo:")) : Selector(("undo:"))
        case "x" where !shift: return #selector(NSText.cut(_:))
        case "c" where !shift: return #selector(NSText.copy(_:))
        case "v" where !shift: return #selector(NSText.paste(_:))
        case "a" where !shift: return #selector(NSText.selectAll(_:))
        default: return nil
        }
    }
}

public extension NotesModule {
    /// A Notes with a few made-up notes, kept in memory, with the user's settings.
    public static func practice(now: Date = Date()) -> NotesModule {
        let settings = NotesSettings.user ?? NotesSettings(defaults: UserDefaults(suiteName: "PracticeNotes") ?? .standard)
        return NotesModule(store: .practice(now: now), settings: settings)
    }
}

/// Words about notes, shared by the page, widgets and the app window.
public enum NotesText {
    public static func count(_ count: Int) -> String {
        count == 1 ? String(localized: "1 note", comment: "Notes: one note")
            : String(localized: "\(count) notes", comment: "Notes: how many notes there are")
    }

    /// "Today 9:41", "Yesterday", "Mon", or a date.
    public static func when(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday", comment: "Notes: edited yesterday")
        }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Edited today 9:41", or "Added from Shelf · Plan.txt" for an untouched note from a file.
    public static func edited(_ note: Note, now: Date = Date()) -> String {
        if note.modified == note.created {
            switch note.source {
            case .shelf(let name?):
                return String(localized: "From the Shelf · \(name)", comment: "Notes: a note made from a text file dropped on the Shelf")
            case .file(let name):
                return String(localized: "From \(name)", comment: "Notes: a note made from a text file dropped on Notes")
            default: break
            }
        }
        return String(localized: "Edited \(when(note.modified, now: now))", comment: "Notes: when the note was last changed")
    }

    /// What VoiceOver reads for a note in a list.
    public static func spoken(_ note: Note) -> String {
        let words = [note.isPinned ? String(localized: "Pinned") : nil, title(note), note.preview.isEmpty ? nil : note.preview]
        return words.compactMap { $0 }.joined(separator: ", ")
    }

    public static func title(_ note: Note) -> String {
        note.isEmpty ? String(localized: "New Note", comment: "Notes: a note with no text yet") : note.title
    }
}
