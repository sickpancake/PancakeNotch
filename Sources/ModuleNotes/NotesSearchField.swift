import AppKit
import NotesCore
import SwiftUI

/// The words typed in the search field. An AppKit field rather than a SwiftUI `TextField` for the same
/// reasons as the note's text view: its focus follows the module (⌘F, Esc, Return hand the keyboard
/// between the field and the note), and it takes no drags, so text dropped on it becomes a note.
struct NotesSearchField: NSViewRepresentable {
    @Binding var text: String
    /// Whether the field should hold keyboard focus.
    let isFocused: Bool
    /// What the search looks through, for VoiceOver's help.
    let scope: NotesSearchScope
    /// Goes up on every request to type in the field, so a click retries focus even while already searching.
    let focusRequest: Int
    /// Called when the field takes keyboard focus (a click in it).
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = Self.makeField(text: text)
        field.onFocus = { context.coordinator.parent.onFocus() }
        field.delegate = context.coordinator
        return field
    }

    /// The field, styled for the notch, with its VoiceOver label, taking no drags.
    static func makeField(text: String) -> NotesSearchTextField {
        let field = NotesSearchTextField()
        field.stringValue = text
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = .white
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderAttributedString = NSAttributedString(
            string: String(localized: "Search", comment: "Notes: placeholder in the search field"),
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.4), .font: NSFont.systemFont(ofSize: 12)]
        )
        field.setAccessibilityLabel(String(localized: "Search notes"))
        field.setAccessibilityHelp(String(localized: "Type words from a note's title or text. Down and Up move through the matches, Return opens one, Esc clears the search."))
        field.unregisterDraggedTypes()
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        // Leave the field editor alone while it's typing the same words (it would lose the caret).
        if field.stringValue != text { field.stringValue = text }
        let help = scope == .titlesOnly
            ? String(localized: "Type words from a note's title. Down and Up move through the matches, Return opens one, Esc clears the search.")
            : String(localized: "Type words from a note's title or text. Down and Up move through the matches, Return opens one, Esc clears the search.")
        if field.accessibilityHelp() != help { field.setAccessibilityHelp(help) }
        let window = field.window
        let hasFocus = field.currentEditor() != nil && window?.firstResponder === field.currentEditor()
        let retry = focusRequest != context.coordinator.focusRequest
        context.coordinator.focusRequest = focusRequest
        if isFocused, !hasFocus || retry {
            // The notch window takes key focus a moment after the field appears: focus once it is in.
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window,
                      field.currentEditor() == nil || window.firstResponder !== field.currentEditor() else { return }
                window.makeFirstResponder(field)
                // Put the caret after the words, rather than selecting them all.
                if let editor = field.currentEditor() {
                    editor.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
                }
            }
        } else if !isFocused, hasFocus {
            window?.makeFirstResponder(nil)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NotesSearchField
        var focusRequest = 0

        init(_ parent: NotesSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }
    }
}

final class NotesSearchTextField: NSTextField {
    var onFocus: (() -> Void)?

    override class var cellClass: AnyClass? {
        get { SearchFieldCell.self }
        set {}
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus?() }
        return became
    }
}

/// Gives the field its own field editor, one that takes no drags (the window's shared one would take
/// dropped text and type it into the search).
private final class SearchFieldCell: NSTextFieldCell {
    private var editor: NoDropFieldEditor?

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        if let editor { return editor }
        let editor = NoDropFieldEditor()
        editor.isFieldEditor = true
        editor.insertionPointColor = .white
        editor.selectedTextAttributes = [.backgroundColor: NSColor.white.withAlphaComponent(0.25)]
        self.editor = editor
        return editor
    }
}

private final class NoDropFieldEditor: NSTextView {
    override func updateDragTypeRegistration() {
        unregisterDraggedTypes()
    }
}
