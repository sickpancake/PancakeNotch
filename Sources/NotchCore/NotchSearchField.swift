import AppKit
import SwiftUI

/// The notch's search box: a magnifying glass, the field, and a clear button once something is typed. Notes
/// and the Library both use it, so searching looks and works the same in both (ADR-0045).
public struct NotchSearchBox: View {
    @Binding var text: String
    /// The field has the keyboard (or should): the box's edge brightens.
    let isActive: Bool
    let focusRequest: Int
    let placeholder: String
    let label: String
    let help: String
    /// Shown at the end while nothing is typed and the field doesn't have the keyboard ("⌘F").
    let hint: String?
    let clearHelp: String
    /// Off-screen snapshots draw the words instead of the AppKit field.
    let isSnapshot: Bool
    /// A click in the box, or the field taking the keyboard: start typing.
    let start: () -> Void
    let clear: () -> Void

    public init(text: Binding<String>, isActive: Bool, focusRequest: Int, placeholder: String, label: String,
                help: String, hint: String? = nil, clearHelp: String, isSnapshot: Bool = false,
                start: @escaping () -> Void, clear: @escaping () -> Void) {
        _text = text
        self.isActive = isActive
        self.focusRequest = focusRequest
        self.placeholder = placeholder
        self.label = label
        self.help = help
        self.hint = hint
        self.clearHelp = clearHelp
        self.isSnapshot = isSnapshot
        self.start = start
        self.clear = clear
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(isActive ? 0.8 : 0.45))
                .accessibilityHidden(true)
            Group {
                if isSnapshot {
                    Text(text.isEmpty ? placeholder : text)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(text.isEmpty ? 0.4 : 1))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    NotchSearchField(text: $text, isFocused: isActive, focusRequest: focusRequest,
                                     placeholder: placeholder, label: label, help: help, onFocus: start)
                }
            }
            .frame(maxWidth: .infinity)
            if !text.isEmpty {
                Button {
                    clear()
                    start()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help(Text(clearHelp))
                .accessibilityLabel(Text("Clear Search"))
                .transition(.opacity)
            } else if !isActive, let hint {
                Text(hint)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06))
                .strokeBorder(.white.opacity(isActive ? 0.3 : 0.12), lineWidth: 1)
        )
        // A click on the magnifying glass or the padding starts typing too, not only on the words.
        .contentShape(.rect(cornerRadius: 8))
        .onTapGesture { start() }
        .animation(.easeOut(duration: 0.15), value: text.isEmpty)
        .animation(.easeOut(duration: 0.15), value: isActive)
    }
}

/// The words typed in a search. An AppKit field rather than a SwiftUI `TextField`: its focus follows the
/// model (a click, ⌘F, Esc and Return hand the keyboard around), and it takes no drags, so text dropped on
/// it goes where the drop means (a new note) rather than into the search.
public struct NotchSearchField: NSViewRepresentable {
    @Binding var text: String
    /// Whether the field should hold keyboard focus.
    let isFocused: Bool
    /// Goes up on every request to type in the field, so a click retries focus even while already typing.
    let focusRequest: Int
    let placeholder: String
    let label: String
    let help: String
    /// Called when the field takes keyboard focus (a click in it).
    let onFocus: () -> Void

    public init(text: Binding<String>, isFocused: Bool, focusRequest: Int, placeholder: String, label: String,
                help: String, onFocus: @escaping () -> Void) {
        _text = text
        self.isFocused = isFocused
        self.focusRequest = focusRequest
        self.placeholder = placeholder
        self.label = label
        self.help = help
        self.onFocus = onFocus
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NotchSearchTextField {
        let field = Self.makeField(text: text, placeholder: placeholder, label: label, help: help)
        field.onFocus = { context.coordinator.parent.onFocus() }
        field.delegate = context.coordinator
        return field
    }

    /// The field, styled for the notch, with its VoiceOver label, taking no drags.
    public static func makeField(text: String, placeholder: String, label: String, help: String) -> NotchSearchTextField {
        let field = NotchSearchTextField()
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
            string: placeholder,
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.4), .font: NSFont.systemFont(ofSize: 12)]
        )
        field.setAccessibilityLabel(label)
        field.setAccessibilityHelp(help)
        field.unregisterDraggedTypes()
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    public func updateNSView(_ field: NotchSearchTextField, context: Context) {
        context.coordinator.parent = self
        // Leave the field editor alone while it's typing the same words (it would lose the caret).
        if field.stringValue != text { field.stringValue = text }
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

    public final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NotchSearchField
        var focusRequest = 0

        init(_ parent: NotchSearchField) { self.parent = parent }

        public func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }
    }
}

public final class NotchSearchTextField: NSTextField {
    var onFocus: (() -> Void)?

    override public class var cellClass: AnyClass? {
        get { SearchFieldCell.self }
        set {}
    }

    override public func becomeFirstResponder() -> Bool {
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
