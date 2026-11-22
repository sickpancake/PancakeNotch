import NotchCore
import NotesCore
import SwiftUI

/// Where things sit in the open Notes panel (origin top-left, y down): a band beside the hardware notch
/// with the count and New Note, then the list and the editor under it.
struct NotesLayout: Equatable {
    static let sidePadding: CGFloat = 20
    static let bottomPadding: CGFloat = 14

    let body: CGSize
    let bandHeight: CGFloat
    let notchWidth: CGFloat

    init(_ layout: NotchLayout) {
        body = layout.bodySize(for: .expanded)
        bandHeight = layout.geometry.notchRect.height
        notchWidth = layout.geometry.notchRect.width
    }

    var bandSideWidth: CGFloat { max(0, (body.width - notchWidth) / 2 - Self.sidePadding) }
    var listWidth: CGFloat { min(220, (body.width - 2 * Self.sidePadding) * 0.38) }
}

/// The open Notes page: the notes on the left, the one you picked on the right, ready to type in.
struct NotesView: View {
    let module: NotesModule
    let layout: NotesLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            band
                .frame(height: layout.bandHeight)
                .padding(.horizontal, NotesLayout.sidePadding)
            Group {
                if module.store.notes.isEmpty {
                    NotesEmpty(module: module)
                        .transition(.opacity)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        NotesList(module: module)
                            .frame(width: layout.listWidth)
                        if let note = module.selectedNote {
                            NotesEditor(module: module, note: note)
                                .id(note.id)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, NotesLayout.sidePadding)
            .padding(.top, 6)
            .padding(.bottom, NotesLayout.bottomPadding)
            .frame(maxHeight: .infinity)
        }
        .frame(width: layout.body.width, height: layout.body.height, alignment: .top)
        .overlay { NotesDropTarget(isTargeted: module.isDropTargeted).padding(8) }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.2), value: module.store.notes.isEmpty)
        .animation(.easeInOut(duration: 0.15), value: module.isDropTargeted)
        .animation(.easeInOut(duration: 0.15), value: module.selectedNote?.id)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Notes"))
    }

    /// Beside the notch: nothing on the left (the module tabs live there), the count and New Note on the right.
    private var band: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Color.clear.frame(width: layout.notchWidth)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if !module.store.notes.isEmpty {
                    Text(NotesText.count(module.store.notes.count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .contentTransition(.numericText())
                }
                NotchRoundButton(symbol: "square.and.pencil", label: String(localized: "New Note", comment: "Notes"), size: 24) {
                    module.newNote()
                }
                .disabled(module.store.isFull)
                .opacity(module.store.isFull ? 0.4 : 1)
                .help(module.store.isFull ? Text("Notes is full. Delete a note to add one.") : Text("New Note (⌘N)"))
            }
            .frame(width: layout.bandSideWidth)
        }
    }
}

/// No notes yet: what Notes is for, and how to start one.
private struct NotesEmpty: View {
    let module: NotesModule

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
            Text("No notes yet")
                .font(.system(size: 13, weight: .semibold))
            Text("Write something down for later, or drop text or a text file here.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            NotchPill(title: String(localized: "New Note", comment: "Notes"), symbol: "square.and.pencil", prominent: true) {
                module.newNote()
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// The notes, pinned first, with an Undo row after a delete.
private struct NotesList: View {
    let module: NotesModule

    var body: some View {
        VStack(spacing: 4) {
            // Off-screen pictures don't draw scroll views.
            if module.isSnapshot {
                VStack(spacing: 2) { rows }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) { rows }
                }
                .scrollIndicators(.never)
            }
            if module.store.lastDeleted != nil {
                NotesUndoRow(module: module)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: module.store.lastDeleted?.id)
        .animation(.easeInOut(duration: 0.2), value: module.notes.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Notes list"))
    }

    private var rows: some View {
        ForEach(module.notes) { note in
            NotesRow(module: module, note: note, isSelected: note.id == module.selectedNote?.id)
        }
    }
}

private struct NotesRow: View {
    let module: NotesModule
    let note: Note
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        Button { module.select(note.id) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(NotesText.title(note))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(note.isEmpty ? 0.5 : 1))
                        .lineLimit(1)
                    Text(note.preview.isEmpty ? NotesText.when(note.modified, now: module.store.now) : note.preview)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.white.opacity(isSelected ? 0.14 : isHovered ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(note.isPinned ? String(localized: "Unpin") : String(localized: "Pin")) { module.togglePin(note.id) }
            Button(String(localized: "Copy Text")) { module.copy(note.id) }
            Divider()
            Button(String(localized: "Delete"), role: .destructive) { module.delete(note.id) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NotesText.spoken(note)))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: note.isPinned ? Text("Unpin") : Text("Pin")) { module.togglePin(note.id) }
        .accessibilityAction(named: Text("Delete")) { module.delete(note.id) }
    }
}

private struct NotesUndoRow: View {
    let module: NotesModule

    var body: some View {
        HStack(spacing: 6) {
            Text("Note deleted")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 0)
            Button(String(localized: "Undo", comment: "Notes: bring back the deleted note")) { module.undoDelete() }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .accessibilityLabel(Text("Undo delete"))
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(.white.opacity(0.07), in: Capsule())
    }
}

/// The note you picked: its text, editable, with Pin, Copy and Delete above it.
private struct NotesEditor: View {
    let module: NotesModule
    let note: Note
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(module: NotesModule, note: Note) {
        self.module = module
        self.note = note
        _draft = State(initialValue: note.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(NotesText.edited(note, now: module.store.now))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 0)
                NotchRoundButton(symbol: note.isPinned ? "pin.slash" : "pin",
                                 label: note.isPinned ? String(localized: "Unpin") : String(localized: "Pin"), size: 22) {
                    module.togglePin(note.id)
                }
                .help(note.isPinned ? Text("Unpin") : Text("Pin to the top"))
                NotchRoundButton(symbol: "doc.on.doc", label: String(localized: "Copy Text"), size: 22) {
                    module.copy(note.id)
                }
                .help(Text("Copy the note's text"))
                .disabled(note.isEmpty)
                NotchRoundButton(symbol: "trash", label: String(localized: "Delete"), size: 22) {
                    module.delete(note.id)
                }
                .help(Text("Delete (⌘⌫)"))
            }
            Group {
                if module.isSnapshot {
                    Text(draft.isEmpty ? String(localized: "Write something…") : draft)
                        .foregroundStyle(.white.opacity(draft.isEmpty ? 0.4 : 1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 5)
                } else {
                    TextEditor(text: $draft)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .focused($isFocused)
                        .onChange(of: draft) { module.edit(note.id, text: draft) }
                        .onChange(of: isFocused) { if isFocused { module.startEditing() } }
                        .onChange(of: module.isEditing) { isFocused = module.isEditing }
                        .onAppear { if module.isEditing { isFocused = true } }
                        .overlay(alignment: .topLeading) {
                            if draft.isEmpty {
                                Text("Write something…")
                                    .foregroundStyle(.white.opacity(0.4))
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel(Text("Note text"))
                }
            }
            .font(.system(size: 13))
            .tint(.white)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .strokeBorder(.white.opacity(module.isEditing ? 0.3 : 0.12), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.15), value: module.isEditing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The dashed outline while text is dragged over the page.
private struct NotesDropTarget: View {
    let isTargeted: Bool

    var body: some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    Label(String(localized: "Drop to make a note"), systemImage: "note.text.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
