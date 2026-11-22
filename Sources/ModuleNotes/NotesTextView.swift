import AppKit
import NotesCore
import SwiftUI

/// The note's editable text. A plain `TextEditor` takes drags itself, so a file dropped on it would paste its
/// path into the note instead of reaching the notch and becoming a new note: this text view takes none.
struct NotesTextView: NSViewRepresentable {
    @Binding var text: String
    /// Whether the text view should hold keyboard focus.
    let isFocused: Bool
    /// Called when the text view takes keyboard focus (a click in it).
    let onFocus: () -> Void
    /// The search's words, highlighted in the text, with the first one scrolled into view.
    var search: NotesSearch?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = NoDropTextView()
        textView.onFocus = { context.coordinator.parent.onFocus() }
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.selectedTextAttributes = [.backgroundColor: NSColor.white.withAlphaComponent(0.25)]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel(String(localized: "Note text"))
        textView.updateDragTypeRegistration()
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        if textView.string != text {
            textView.string = text
            coordinator.highlighted = [] // replacing the text dropped its highlights
        }
        let matches = search?.nsRanges(in: textView.string) ?? []
        if matches != coordinator.highlighted {
            Self.highlight(matches, in: textView)
            coordinator.highlighted = matches
        }
        let window = textView.window
        let hasFocus = window?.firstResponder === textView
        if isFocused, !hasFocus {
            // The notch window takes key focus a moment after the editor appears: focus once it is in.
            DispatchQueue.main.async { [weak textView, search] in
                guard let textView, let window = textView.window, window.firstResponder !== textView else { return }
                window.makeFirstResponder(textView)
                // Opened from a search: the caret goes just after the first match, ready to write there.
                if let first = search?.nsRanges(in: textView.string).first {
                    textView.setSelectedRange(NSRange(location: NSMaxRange(first), length: 0))
                    textView.scrollRangeToVisible(first)
                }
            }
        } else if !isFocused, hasFocus {
            window?.makeFirstResponder(nil)
        }
        // A new search (or a note shown from one): bring its first match into view.
        let terms = search?.terms ?? []
        if terms != coordinator.scrolledTerms {
            coordinator.scrolledTerms = terms
            if !isFocused, let first = matches.first {
                DispatchQueue.main.async { [weak textView] in textView?.scrollRangeToVisible(first) }
            }
        }
    }

    /// Marks where the search's words are with a soft white background. Display-only: the note's text
    /// and its undo history are untouched.
    static func highlight(_ ranges: [NSRange], in textView: NSTextView) {
        let color = NSColor.white.withAlphaComponent(0.25)
        let length = (textView.string as NSString).length
        let valid = ranges.filter { NSMaxRange($0) <= length }
        if let layout = textView.textLayoutManager, let content = layout.textContentManager {
            let whole = layout.documentRange
            layout.removeRenderingAttribute(.backgroundColor, for: whole)
            for range in valid {
                guard let start = content.location(whole.location, offsetBy: range.location),
                      let end = content.location(start, offsetBy: range.length),
                      let textRange = NSTextRange(location: start, end: end) else { continue }
                layout.addRenderingAttribute(.backgroundColor, value: color, for: textRange)
            }
        } else if let layout = textView.layoutManager {
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
            for range in valid {
                layout.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextView
        /// What's highlighted now, so unchanged highlights aren't redrawn on every update.
        var highlighted: [NSRange] = []
        /// The search last scrolled to, so it scrolls once per search rather than on every keystroke.
        var scrolledTerms: [String] = []

        init(_ parent: NotesTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string { parent.text = textView.string }
        }
    }
}

private final class NoDropTextView: NSTextView {
    var onFocus: (() -> Void)?

    override func updateDragTypeRegistration() {
        unregisterDraggedTypes()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus?() }
        return became
    }
}
