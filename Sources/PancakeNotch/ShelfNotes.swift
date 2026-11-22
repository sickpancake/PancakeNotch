import Foundation
import ModuleShelf
import NotesCore

/// Text dropped on the Shelf that becomes notes, as Notes' settings say. The rest stays on the Shelf.
@MainActor
enum ShelfNotes {
    static func take(_ inputs: [ShelfInput], into store: NotesStore, settings: NotesSettings) -> [ShelfInput] {
        guard settings.isEnabled, settings.shelfText != .off else { return inputs }
        return inputs.filter { input in
            guard let note = note(for: input, mode: settings.shelfText) else { return true }
            return store.add(note.text, source: .shelf(fileName: note.fileName)) == nil
        }
    }

    /// The note text a dropped item makes, or nil when it stays on the Shelf.
    static func note(for input: ShelfInput, mode: NotesShelfText) -> (text: String, fileName: String?)? {
        switch input {
        case .file(let url, let owned):
            // An owned text file is long dropped text the Shelf wrote down, not a file of yours.
            if owned { return mode == .allText ? NotesImport.text(of: url).map { ($0, nil) } : nil }
            return mode == .off ? nil : NotesImport.text(of: url).map { ($0, url.lastPathComponent) }
        case .text(let text):
            return mode == .allText ? (text, nil) : nil
        case .link:
            return nil
        }
    }
}
