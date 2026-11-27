import AppKit
import NotchCore
import NotesCore

/// Notes' words for the shared search box (`NotchSearchBox`): the field's placeholder, its VoiceOver label,
/// and help that follows what the search looks through.
enum NotesSearchField {
    static var placeholder: String { String(localized: "Search", comment: "Notes: placeholder in the search field") }
    static var label: String { String(localized: "Search notes") }

    static func help(_ scope: NotesSearchScope) -> String {
        scope == .titlesOnly
            ? String(localized: "Type words from a note's title. Down and Up move through the matches, Return opens one, Esc clears the search.")
            : String(localized: "Type words from a note's title or text. Down and Up move through the matches, Return opens one, Esc clears the search.")
    }

    /// The field Notes shows, as the box makes it.
    @MainActor
    static func makeField(text: String) -> NotchSearchTextField {
        NotchSearchField.makeField(text: text, placeholder: placeholder, label: label, help: help(.titleAndText))
    }
}
