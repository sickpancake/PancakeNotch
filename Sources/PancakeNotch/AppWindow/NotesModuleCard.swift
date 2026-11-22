import NotesCore
import SwiftUI

/// Notes on the Modules page: a practice notch with made-up notes, what it does with its switch, and its
/// settings while it's on.
struct NotesModuleCard: View {
    let context: AppContext
    @Binding var showsSettings: Bool
    let learn: () -> Void

    private let points = [
        String(localized: "Write notes right in the notch: the first line is the title, and it saves as you type"),
        String(localized: "Drop text or a .txt file on the Shelf or on Notes to keep it as a note"),
        String(localized: "Pin the notes you need most to the top"),
        String(localized: "Find any note fast: press ⌘F and type a few words"),
        String(localized: "Small, medium and large widgets for Home"),
    ]

    var body: some View {
        ModuleCard(
            context: context,
            moduleID: "notes",
            practice: .notes,
            summary: String(localized: "Jot something down for later without opening another app: a phone number, a to-do, a thought mid-meeting. Your notes stay on this Mac."),
            points: points,
            inactiveHint: String(localized: "Turn on Notes to try it here."),
            activeHint: String(localized: "A practice copy with made-up notes: your real notes aren't touched. Hover the notch and write one."),
            learnHint: String(localized: "Opens a hands-on Notes lesson on the Learn page."),
            showsSettings: $showsSettings,
            learn: learn
        ) {
            NotesSettingsRows(context: context, settings: context.notesSettings)
        }
    }
}

/// Notes' settings, as rows with hairlines between them.
struct NotesSettingsRows: View {
    let context: AppContext
    @Bindable var settings: NotesSettings

    var body: some View {
        HairlineRows {
            SettingsRow(
                title: String(localized: "Text dropped on the Shelf"),
                subtitle: shelfSubtitle
            ) {
                MonochromeSegmented(
                    title: String(localized: "Text dropped on the Shelf"),
                    options: [
                        (NotesShelfText.textFiles, String(localized: "Text files")),
                        (.allText, String(localized: "All text")),
                        (.off, String(localized: "Off")),
                    ],
                    selection: $settings.shelfText
                )
            }
            SettingsRow(
                title: String(localized: "Order"),
                subtitle: String(localized: "How the list is sorted. Pinned notes always come first.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "Order"),
                    options: [
                        (NotesSort.recentlyEdited, String(localized: "Last edited")),
                        (.newestFirst, String(localized: "Newest")),
                        (.oldestFirst, String(localized: "Oldest")),
                    ],
                    selection: $settings.sort
                )
            }
            SettingsRow(
                title: String(localized: "Start a new note when Notes opens"),
                subtitle: String(localized: "Opening Notes goes straight to an empty note, ready to type. Empty notes are removed when the notch closes.")
            ) {
                Toggle(String(localized: "Start a new note when Notes opens"), isOn: $settings.opensNewNote)
                    .labelsHidden()
            }
            SettingsRow(
                title: String(localized: "Search field"),
                subtitle: searchFieldSubtitle
            ) {
                MonochromeSegmented(
                    title: String(localized: "Search field"),
                    options: [
                        (NotesSearchField.always, String(localized: "Always")),
                        (.whenSearching, String(localized: "When searching")),
                    ],
                    selection: $settings.searchField
                )
            }
            SettingsRow(
                title: String(localized: "Search in"),
                subtitle: settings.searchScope == .titleAndText
                    ? String(localized: "Finds notes with every word you type anywhere in them.")
                    : String(localized: "Finds notes with every word you type in their first line.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "Search in"),
                    options: [
                        (NotesSearchScope.titleAndText, String(localized: "Titles and text")),
                        (.titlesOnly, String(localized: "Titles only")),
                    ],
                    selection: $settings.searchScope
                )
            }
            SettingsRow(
                title: String(localized: "Keep the search when the notch closes"),
                subtitle: String(localized: "Notes opens on the same results next time. Off: every note shows again once the notch closes.")
            ) {
                Toggle(String(localized: "Keep the search when the notch closes"), isOn: $settings.keepsSearch)
                    .labelsHidden()
            }
            SettingsRow(
                title: String(localized: "Show text counts"),
                subtitle: String(localized: "See words, characters and list items while editing. Select text to count just the selection.")
            ) {
                Toggle(String(localized: "Show text counts"), isOn: $settings.showsTextCounts)
                    .labelsHidden()
            }
        }
    }

    private var searchFieldSubtitle: String {
        switch settings.searchField {
        case .always: String(localized: "A search field sits above the list. Press ⌘F to type in it.")
        case .whenSearching: String(localized: "More room for notes: press ⌘F or click the magnifying glass to search.")
        }
    }

    private var shelfSubtitle: String {
        let base = switch settings.shelfText {
        case .textFiles: String(localized: "Text files (.txt, .md) dropped on the Shelf become notes. Other text stays on the Shelf.")
        case .allText: String(localized: "Text files and selected text dropped on the Shelf become notes. Links stay on the Shelf.")
        case .off: String(localized: "Everything you drop stays on the Shelf.")
        }
        return context.shelfSettings.isEnabled ? base : base + " " + String(localized: "Needs the Shelf, which is off.")
    }
}
