import NotchCore
import NotesCore
import SwiftUI

extension NotesModule {
    public func homeWidget(_ kind: HomeWidgetKind, size: HomeWidgetSize, context: HomeWidgetContext) -> AnyView? {
        guard kind == .notes else { return nil }
        return AnyView(NotesWidget(module: self, size: size, now: context.fixedNow ?? store.now))
    }

    public func openedFromHome(_ kind: HomeWidgetKind) {
        guard kind == .notes, settings.opensNewNote || store.notes.isEmpty else { return }
        newNote()
    }
}

/// Small: how many notes. Medium: the top note. Large: the first few notes, pinned first.
struct NotesWidget: View {
    let module: NotesModule
    let size: HomeWidgetSize
    let now: Date

    var body: some View {
        let notes = module.notes.filter { !$0.isEmpty }
        switch size {
        case .small:
            HomeSmallFace(caption: Self.caption(module.store)) {
                Image(systemName: "note.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            } value: {
                Text(notes.count, format: .number)
                    .font(.system(size: 17, weight: .semibold))
                    .motionContentTransition(.numericText())
            }
            .animation(.easeInOut(duration: 0.2), value: notes.count)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(NotesText.count(notes.count)))
        case .medium:
            VStack(alignment: .leading, spacing: 6) {
                HomeWidgetHeader(symbol: "note.text", title: module.title) {
                    newButton
                }
                if let note = notes.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(note.preview.isEmpty ? NotesText.when(note.modified, now: now) : note.preview)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(NotesText.spoken(note)))
                } else {
                    HomeWidgetEmptyLine(String(localized: "No notes yet"))
                }
            }
        case .large:
            VStack(alignment: .leading, spacing: 6) {
                HomeWidgetHeader(symbol: "note.text", title: module.title) {
                    newButton
                }
                if notes.isEmpty {
                    HomeWidgetEmptyLine(String(localized: "No notes yet. Click + to write one."))
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(notes.prefix(4)) { note in
                            HStack(spacing: 5) {
                                Image(systemName: note.isPinned ? "pin.fill" : "circle.fill")
                                    .font(.system(size: note.isPinned ? 8 : 4, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(width: 10)
                                    .accessibilityHidden(true)
                                Text(note.title)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(NotesText.when(note.modified, now: now))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .lineLimit(1)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(NotesText.spoken(note)))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: notes.map(\.id))
        }
    }

    private var newButton: some View {
        NotchRoundButton(symbol: "plus", label: String(localized: "New Note", comment: "Notes"), size: 18) {
            module.notch?.select(module.moduleID)
            module.newNote()
        }
        .disabled(module.store.isFull)
    }

    @MainActor
    static func caption(_ store: NotesStore) -> String? {
        store.pinnedCount > 0 ? String(localized: "\(store.pinnedCount) pinned", comment: "Notes widget") : nil
    }
}
