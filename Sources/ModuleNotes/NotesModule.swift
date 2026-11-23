import AppKit
import HotKey
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
    /// What's typed in the search field. Empty shows every note.
    public private(set) var query = ""
    /// The search field has the keyboard: typing goes into it and the notch stays open.
    public internal(set) var isSearching = false
    /// ⌘F or the magnifying glass brought the field out (it only matters when the field shows only while searching).
    public internal(set) var searchRevealed = false
    /// Counts requests to type in the search field, so each click or ⌘F focuses it again.
    public internal(set) var searchFocusRequest = 0
    /// The note opened from a search stays in the list while you change it so it stops matching, until
    /// the search changes.
    public internal(set) var keptID: Note.ID?
    /// Told each time a search finds notes (the Learn lesson).
    @ObservationIgnored public var onFound: (() -> Void)?
    @ObservationIgnored public var isSnapshot = false
    /// Claims ⌘F system-wide while Notes is open, so a hover-opened Notes gets it rather than the app
    /// that still has the keyboard. Off for the Learn practice, whose window has the keyboard already.
    @ObservationIgnored var usesGlobalFind = true
    @ObservationIgnored private var findKey: GlobalHotKey?

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

    public var holdsOpen: Bool { isEditing || isSearching }

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
        if !isSnapshot, usesGlobalFind, let key = HotKey(keyCode: 3, modifiers: .command, keyLabel: "F") {
            if findKey == nil { findKey = GlobalHotKey { [weak self] in self?.findPressed() } }
            try? findKey?.register(key)
        }
        guard !isSnapshot, let type = NSApp.currentEvent?.type,
              [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp].contains(type) else { return }
        notch?.requestKeyFocus?()
    }

    /// The page went away (the notch closed, or another module or Home shows): ⌘F is the other apps' again.
    func pageHidden() {
        findKey?.unregister()
    }

    /// ⌘F: search, from the list or from inside a note; again selects the words typed.
    private func findPressed() {
        if isSearching {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        } else {
            startSearching()
        }
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
        pageHidden()
        stopEditing()
        stopSearching()
        keptID = nil
        if !settings.keepsSearch { endSearch() }
        store.removeEmpty()
        store.clearUndo()
        dropRefused = false
    }

    public func userSwitchedAway() {
        pageHidden()
        stopEditing()
        stopSearching()
        store.removeEmpty()
    }

    public func clickedOutsidePreview() {
        stopEditing()
        stopSearching()
    }

    public func keyFocusLost() {
        stopEditing()
        stopSearching()
    }

    public func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == .command, event.keyCode == 3 { // ⌘F
            findPressed()
            return true
        }
        if isSearching { return handleSearchKey(event) }
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

    /// Keys while the search field has the keyboard. Letters go to the field; the arrows walk the results
    /// and Return opens the shown one, so you never have to reach for the pointer.
    private func handleSearchKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53: // Esc: clear the search, then leave the field
            if query.isEmpty { stopSearching() } else { clearSearch() }
            return true
        case 125 where !command, 126 where !command: // Down, Up: the next or previous match
            moveSelection(by: event.keyCode == 125 ? 1 : -1)
            return true
        case 36, 76: // Return: write in the shown match
            if let id = selectedNote?.id { openFromSearch(id) }
            return true
        case 45 where command: // ⌘N
            newNote()
            return true
        default:
            // The app usually isn't active, so the Edit menu may not see ⌘C/⌘V/…: pass them to the field.
            if let action = Self.editAction(for: event) { return NSApp.sendAction(action, to: nil, from: nil) }
            return false
        }
    }

    // MARK: Search

    /// The typed words, read the way the settings say (titles only, or titles and text).
    public var search: NotesSearch { NotesSearch(query, scope: settings.searchScope) }

    /// Whether the list is narrowed by a search right now.
    public var isFiltering: Bool { !search.isEmpty }

    /// Whether the search field is above the list: always (once there are notes), or while you search.
    public var showsSearchField: Bool {
        guard !store.notes.isEmpty else { return false }
        return settings.searchField == .always || searchRevealed || isSearching || !query.isEmpty
    }

    public func setQuery(_ text: String) {
        guard text != query else { return }
        let before = search
        query = text
        if search != before { keptID = nil }
        notch?.userInteracted()
        if isFiltering, !shownNotes.isEmpty { onFound?() }
    }

    /// ⌘F, the magnifying glass or a click in the field: type in the search field.
    public func startSearching() {
        guard !isSnapshot, !store.notes.isEmpty else { return }
        notch?.userInteracted()
        // Straight from writing to searching: the notch stays held, so no release in between.
        isEditing = false
        searchRevealed = true
        searchFocusRequest &+= 1
        if !isSearching { isSearching = true }
        notch?.requestKeyFocus?()
    }

    /// Lets go of the search field (Esc on an empty search, a click elsewhere). The words stay; a field
    /// that shows only while searching hides again if nothing's typed.
    public func stopSearching() {
        guard isSearching else { return }
        isSearching = false
        if query.isEmpty { searchRevealed = false }
        notch?.holdReleased()
    }

    /// Esc or the clear button: every note shows again, and the field keeps the keyboard.
    public func clearSearch() {
        setQuery("")
    }

    /// Opens a match to write in it. It stays listed even if your changes stop it matching.
    public func openFromSearch(_ id: Note.ID) {
        select(id)
        startEditing()
    }

    /// Forgets the search and hides a field that shows only while searching.
    private func endSearch() {
        if !query.isEmpty { query = "" }
        keptID = nil
        searchRevealed = false
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
            // The new notes may not match the search: show everything so they're there to see.
            if isFiltering { endSearch() }
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

    /// Every note in the chosen order, pinned first (widgets show these).
    public var notes: [Note] { store.sorted(settings.sort) }

    /// The notes in the list: all of them, or the ones that match the search (still pinned first).
    public var shownNotes: [Note] { search.filter(notes, keeping: keptID) }

    /// The note in the editor: the one you picked if it's in the list, else the list's first.
    public var selectedNote: Note? { selectedNote(in: shownNotes) }

    /// `selectedNote` for a list worked out already (saves filtering again for each row).
    public func selectedNote(in list: [Note]) -> Note? {
        if let id = selectedID, let note = list.first(where: { $0.id == id }) { return note }
        return list.first
    }

    public func newNote() {
        notch?.userInteracted()
        store.removeEmpty()
        guard let note = store.add() else { return }
        // A new note matches no search: show every note so it's there to write in.
        endSearch()
        selectedID = note.id
        startEditing()
    }

    public func select(_ id: Note.ID) {
        notch?.userInteracted()
        if selectedID != id { store.removeEmpty(except: id) }
        selectedID = id
        stopEditing()
    }

    public func startEditing() {
        guard !isSnapshot, let note = selectedNote else { return }
        selectedID = note.id
        // Writing in a match keeps it listed even once it no longer matches.
        if isFiltering { keptID = note.id }
        // Straight from searching to writing: the notch stays held, so no release in between.
        isSearching = false
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
        let list = shownNotes
        let index = list.firstIndex { $0.id == id }
        let wasShown = selectedNote?.id == id
        store.delete(id)
        if selectedID == id || selectedID == nil || wasShown {
            let remaining = shownNotes
            selectedID = index.flatMap { remaining.indices.contains($0) ? remaining[$0].id : remaining.last?.id }
        }
        stopEditing()
    }

    public func undoDelete() {
        notch?.userInteracted()
        let id = store.lastDeleted?.id
        store.undoDelete()
        guard let id, let note = store.note(id) else { return }
        selectedID = id
        // A note brought back that doesn't match the search still shows, so you see it come back.
        if !search.matches(note) { keptID = id }
    }

    public func copy(_ id: Note.ID) {
        guard let note = store.note(id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.text, forType: .string)
    }

    private func moveSelection(by step: Int) {
        let list = shownNotes
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selectedNote?.id } ?? 0
        let next = min(max(current + step, 0), list.count - 1)
        select(list[next].id)
    }

    private func storeChanged() {
        if let id = selectedID, store.note(id) == nil { selectedID = nil }
        if let id = keptID, store.note(id) == nil { keptID = nil }
        // The last note went: nothing left to search.
        if store.notes.isEmpty {
            if isSearching {
                isSearching = false
                notch?.holdReleased()
            }
            endSearch()
        }
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
        let module = NotesModule(store: .practice(now: now), settings: settings)
        module.usesGlobalFind = false
        return module
    }
}

/// Words about notes, shared by the page, widgets and the app window.
public enum NotesText {
    public static func count(_ count: Int) -> String {
        count == 1 ? String(localized: "1 note", comment: "Notes: one note")
            : String(localized: "\(count) notes", comment: "Notes: how many notes there are")
    }

    /// "2 of 8 notes": how many notes a search found, out of all of them.
    public static func matches(_ shown: Int, of total: Int) -> String {
        total == 1 ? String(localized: "\(shown) of 1 note", comment: "Notes: search results out of one note")
            : String(localized: "\(shown) of \(total) notes", comment: "Notes: how many notes a search found, out of all")
    }

    /// The text with the search's words marked by a soft white background (and full white, where the
    /// rest is dimmed), like the highlights in the note itself.
    public static func highlighted(_ text: String, search: NotesSearch) -> AttributedString {
        guard !search.isEmpty else { return AttributedString(text) }
        var result = AttributedString()
        for run in search.runs(in: text) {
            var part = AttributedString(String(run.text))
            if run.isMatch {
                part.backgroundColor = .white.opacity(0.25)
                part.foregroundColor = .white
            }
            result += part
        }
        return result
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
