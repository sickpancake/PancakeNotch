import AppKit
import SwiftUI
import Testing
@testable import ModuleNotes
@testable import NotchCore
@testable import NotesCore

/// Issue #134: text arriving between view updates (a burst from an expander or dictation) must all
/// reach the store — the saved note used to drop the last characters.
@MainActor
struct NotesBurstTypingTests {
    let layout = NotesLayout(NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))))

    /// The editor's text view, walked down from the hosted page.
    private func editorTextView(in hosting: NSView) -> NSTextView? {
        for subview in hosting.subviews {
            if let scroll = subview as? NSScrollView, let text = scroll.documentView as? NSTextView {
                return text
            }
            if let found = editorTextView(in: subview) { return found }
        }
        return nil
    }

    @Test
    func burstTypingSavesEveryCharacter() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "NotesBurstTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = NotesStore(directory: directory)
        let module = NotesModule(store: store, settings: NotesSettings(defaults: UserDefaults(suiteName: "NotesBurstTests") ?? .standard))
        module.usesGlobalFind = false
        module.newNote()
        let noteID = try #require(module.selectedNote?.id)

        let panel = NSPanel(contentRect: CGRect(x: -30_000, y: -30_000, width: 600, height: 400),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: NotesView(module: module, layout: layout))
        panel.contentView = hosting
        panel.orderFrontRegardless()
        defer {
            panel.orderOut(nil)
            panel.contentView = nil
            try? FileManager.default.removeItem(at: directory)
        }
        try await Task.sleep(for: .milliseconds(150))

        let textView = try #require(editorTextView(in: hosting))
        let typed = "Burst typed sentence here"
        // The store must see each character the moment it is typed — the regression this guards
        // against is a save deferred to the next view update, which could never come (issue #134).
        for character in typed {
            textView.insertText(String(character))
        }
        #expect(textView.string == typed)
        #expect(store.note(noteID)?.text == typed)
        let saved = try String(contentsOf: directory.appending(path: "notes.json"), encoding: .utf8)
        #expect(saved.contains(typed))
    }
}
