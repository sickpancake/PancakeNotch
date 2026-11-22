import AppKit
import SwiftUI

/// The note's editable text. A plain `TextEditor` takes drags itself, so a file dropped on it would paste its
/// path into the note instead of reaching the notch and becoming a new note: this text view takes none.
struct NotesTextView: NSViewRepresentable {
    @Binding var text: String
    /// Whether the text view should hold keyboard focus.
    let isFocused: Bool
    /// Called when the text view takes keyboard focus (a click in it).
    let onFocus: () -> Void

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
        if textView.string != text { textView.string = text }
        let window = textView.window
        let hasFocus = window?.firstResponder === textView
        if isFocused, !hasFocus {
            // The notch window takes key focus a moment after the editor appears: focus once it is in.
            DispatchQueue.main.async { [weak textView] in
                guard let textView, let window = textView.window, window.firstResponder !== textView else { return }
                window.makeFirstResponder(textView)
            }
        } else if !isFocused, hasFocus {
            window?.makeFirstResponder(nil)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextView

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
