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
                    let shown = module.shownNotes
                    let selected = module.selectedNote(in: shown)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 6) {
                            if module.showsSearchField {
                                NotesSearchBar(module: module)
                                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                            }
                            NotesList(module: module, notes: shown, selectedID: selected?.id)
                        }
                        .frame(width: layout.listWidth)
                        .clipped()
                        if let note = selected {
                            NotesEditor(module: module, note: note)
                                .id(note.id)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                        } else if module.isFiltering {
                            NotesNoMatch(module: module)
                                .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.2), value: module.showsSearchField)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, NotesLayout.sidePadding)
            .padding(.top, 6)
            .padding(.bottom, NotesLayout.bottomPadding)
            .frame(maxHeight: .infinity)
        }
        .frame(width: layout.body.width, height: layout.body.height, alignment: .top)
        .background(Color.black.opacity(0.001).onTapGesture { module.pageClicked() })
        .onAppear { module.pageShown() }
        .onDisappear { module.pageHidden() }
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
                    Text(countText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .monospacedDigit()
                        .lineLimit(1)
                        .motionContentTransition(.numericText())
                        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.2), value: countText)
                }
                if module.settings.searchField == .whenSearching, !module.store.notes.isEmpty, !module.showsSearchField {
                    NotchRoundButton(symbol: "magnifyingglass", label: String(localized: "Search Notes"), size: 24) {
                        module.startSearching()
                    }
                    .help(Text("Search (⌘F)"))
                    .transition(.opacity)
                }
                NotchRoundButton(symbol: "square.and.pencil", label: String(localized: "New Note", comment: "Notes"), size: 24) {
                    module.newNote()
                }
                .disabled(module.store.isFull)
                .opacity(module.store.isFull ? 0.4 : 1)
                .help(module.store.isFull ? Text("Notes is full. Delete a note to add one.") : Text("New Note (⌘N)"))
            }
            .notchBandRightSide(width: layout.bandSideWidth)
            .animation(.easeInOut(duration: 0.2), value: module.showsSearchField)
        }
    }

    /// "8 notes", or "2 of 8 notes" while a search narrows the list.
    private var countText: String {
        let total = module.store.notes.count
        guard module.isFiltering else { return NotesText.count(total) }
        return NotesText.matches(module.shownNotes.count, of: total)
    }
}

/// The search field above the list: a magnifying glass, the words, and Clear (or a ⌘F hint).
private struct NotesSearchBar: View {
    let module: NotesModule

    var body: some View {
        NotchSearchBox(
            text: Binding(get: { module.query }, set: { module.setQuery($0) }),
            isActive: module.isSearching,
            focusRequest: module.searchFocusRequest,
            placeholder: NotesSearchWording.placeholder,
            label: NotesSearchWording.label,
            help: NotesSearchWording.help(module.settings.searchScope),
            hint: "⌘F",
            clearHelp: String(localized: "Clear Search (Esc)"),
            isSnapshot: module.isSnapshot,
            start: { module.startSearching() },
            clear: { module.clearSearch() }
        )
    }
}

/// A search that finds nothing: says so where the note would be, with a way back to every note.
private struct NotesNoMatch: View {
    let module: NotesModule

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
            Text("No notes match")
                .font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            NotchPill(title: String(localized: "Clear Search"), symbol: "xmark") {
                module.clearSearch()
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        let words = module.query.trimmingCharacters(in: .whitespaces)
        return switch module.settings.searchScope {
        case .titleAndText: String(localized: "None of your notes has “\(words)”.", comment: "Notes: a search found nothing")
        case .titlesOnly: String(localized: "No note's title has “\(words)”.", comment: "Notes: a titles-only search found nothing")
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
    /// The notes to list (all, or a search's matches).
    let notes: [Note]
    let selectedID: Note.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: module.store.lastDeleted?.id)
        .animation(.easeInOut(duration: 0.2), value: notes.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(module.isFiltering ? Text("Matching notes") : Text("Notes list"))
    }

    private var rows: some View {
        let search = module.search
        return ForEach(notes) { note in
            NotesRow(module: module, note: note, isSelected: note.id == selectedID, search: search)
        }
    }
}

private struct NotesRow: View {
    let module: NotesModule
    let note: Note
    let isSelected: Bool
    /// The search, so the words it found are highlighted (empty when not searching).
    let search: NotesSearch
    @State private var isHovered = false

    var body: some View {
        Button { module.select(note.id) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(NotesText.highlighted(NotesText.title(note), search: search))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(note.isEmpty ? 0.5 : 1))
                        .lineLimit(1)
                    Text(previewText)
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

    /// The text after the title, starting near the first match while searching, or when it was edited.
    private var previewText: AttributedString {
        guard !note.preview.isEmpty else { return AttributedString(NotesText.when(note.modified, now: module.store.now)) }
        guard search.scope == .titleAndText else { return AttributedString(note.preview) }
        return NotesText.highlighted(search.snippet(of: note.preview), search: search)
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
    private struct CountRevision: Equatable {
        let edit: UInt
        let selection: NSRange
    }

    let module: NotesModule
    let note: Note
    @State private var draft: String
    @State private var editRevision: UInt = 0
    @State private var selection = NSRange()
    @State private var measuredCounts: NotesEditorCounts?

    init(module: NotesModule, note: Note) {
        self.module = module
        self.note = note
        _draft = State(initialValue: note.text)
    }

    var body: some View {
        let isEditing = module.isEditing && module.selectedNote?.id == note.id
        let showsCounts = isEditing && module.settings.showsTextCounts
        let revision = showsCounts && !draft.isEmpty ? CountRevision(edit: editRevision, selection: selection) : nil
        let input = NotesEditorCountInput(text: draft, selection: selection)
        let summary = countSummary(showsCounts: showsCounts)
        let editorLabel = summary.map {
            String(localized: "Note text, \($0)", comment: "Accessibility label with the note editor's text counts")
        } ?? String(localized: "Note text")
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
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
                    Text(draft.isEmpty ? AttributedString(String(localized: "Write something…")) : NotesText.highlighted(draft, search: module.search))
                        .foregroundStyle(.white.opacity(draft.isEmpty ? 0.4 : 1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 5)
                } else {
                    NotesTextView(
                        initialText: { draft },
                        selection: $selection,
                        accessibilityLabel: editorLabel,
                        isFocused: isEditing,
                        shouldFocus: { module.isEditing && module.selectedNote?.id == note.id },
                        onFocus: { if module.selectedNote?.id == note.id { module.startEditing() } },
                        onEdit: { text in
                            draft = text
                            editRevision &+= 1
                            // Save right away: a burst's last characters must not depend on a
                            // later view update running the store write (issue #134).
                            module.edit(note.id, text: text)
                        },
                        search: module.isFiltering ? module.search : nil
                    )
                        .overlay(alignment: .topLeading) {
                            if draft.isEmpty {
                                Text("Write something…")
                                    .foregroundStyle(.white.opacity(0.4))
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                }
            }
            .font(.system(size: 13))
            .tint(.white)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .strokeBorder(.white.opacity(isEditing ? 0.3 : 0.12), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.15), value: isEditing)
            footer(summary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: revision) {
            guard revision != nil, let counts = await input.measureAfterPause(), !Task.isCancelled else { return }
            measuredCounts = counts
        }
    }

    private func countSummary(showsCounts: Bool) -> String? {
        guard showsCounts else { return nil }
        if draft.isEmpty { return NotesEditorCounts.empty.summary }
        guard let measuredCounts, measuredCounts.isSelection == (selection.length > 0) else { return nil }
        return measuredCounts.summary
    }

    private func footer(_ summary: String?) -> some View {
        let edited = NotesText.edited(note, now: module.store.now)
        return HStack(spacing: 6) {
            if let summary {
                Text(summary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.8)
                    .help(Text(summary))
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            Text(edited)
                .layoutPriority(1)
                .help(Text(edited))
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.55))
        .lineLimit(1)
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
