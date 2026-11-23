import Foundation
import SwiftUI

/// What the header says for a moment after pinning or unpinning, with what Undo puts back.
struct ShelfPinNote: Equatable {
    let id = UUID()
    let pinned: Bool
    let count: Int
    /// Each changed item's pin before the change, and the Shelf's order then.
    let previousPins: [UUID: Bool]
    let previousOrder: [UUID]

    /// "Pinned", "Unpinned 3"…
    var title: String {
        switch (pinned, count) {
        case (true, 1): String(localized: "Pinned", comment: "Shelf header after pinning one item")
        case (false, 1): String(localized: "Unpinned", comment: "Shelf header after unpinning one item")
        case (true, _): String(localized: "Pinned \(count)", comment: "Shelf header after pinning several items")
        case (false, _): String(localized: "Unpinned \(count)", comment: "Shelf header after unpinning several items")
        }
    }
}

/// Pinning (issue #109): pinned items sit at the front and are never cleared automatically.
extension ShelfModule {
    /// The menu, the P key and the tall notch's pin button: pins the items unless all of them are
    /// pinned already, in which case it unpins them.
    func togglePin(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        setPinned(items, !items.allSatisfy(\.isPinned))
    }

    func setPinned(_ items: [ShelfItem], _ pinned: Bool) {
        let changing = items.filter { $0.isPinned != pinned }
        guard !changing.isEmpty else { return }
        let note = ShelfPinNote(
            pinned: pinned,
            count: changing.count,
            previousPins: Dictionary(uniqueKeysWithValues: changing.map { ($0.id, $0.isPinned) }),
            previousOrder: store.items.map(\.id)
        )
        confirmingClear = false
        store.setPinned(changing.map(\.id), pinned)
        AccessibilityNotification.Announcement(announcement(for: note, name: changing.first?.displayName)).post()
        // The note shows on the tiles; the tall notch already shows the pin button change.
        guard detailID == nil else { return }
        pinNote = note
        notch?.userInteracted()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.pinNote?.id == note.id { self?.pinNote = nil }
        }
    }

    /// Undo in the header: the pins and the order go back to how they were.
    func undoPin() {
        guard let note = pinNote else { return }
        pinNote = nil
        store.restorePins(note.previousPins, order: note.previousOrder)
        AccessibilityNotification.Announcement(String(localized: "Undone", comment: "VoiceOver, after undoing a pin on the Shelf")).post()
    }

    private func announcement(for note: ShelfPinNote, name: String?) -> String {
        if note.count == 1, let name {
            return note.pinned
                ? String(localized: "\(name) pinned. It stays on the Shelf until you unpin it.", comment: "VoiceOver; a Shelf item's name")
                : String(localized: "\(name) unpinned", comment: "VoiceOver; a Shelf item's name")
        }
        return note.title
    }

    /// The items Clear all removes: all of them, or the ones that aren't pinned.
    var clearableCount: Int {
        settings.clearAllKeepsPinned ? store.items.count - store.pinnedCount : store.items.count
    }

    /// "Pin", "Unpin 3 Items"… for the right-click menu and VoiceOver.
    static func pinTitle(for items: [ShelfItem]) -> String {
        let unpins = items.allSatisfy(\.isPinned)
        if items.count > 1 {
            return unpins
                ? String(localized: "Unpin \(items.count) Items", comment: "Context menu; several shelf items")
                : String(localized: "Pin \(items.count) Items", comment: "Context menu; several shelf items")
        }
        return unpins ? String(localized: "Unpin") : String(localized: "Pin")
    }

    /// How long an item stays, for the tall notch: kept while pinned, or when auto-clear removes it.
    /// Nil when nothing clears it.
    func keepText(for item: ShelfItem, now: Date = Date()) -> String? {
        if item.isPinned {
            return String(localized: "Pinned · kept until you unpin it", comment: "Shelf item's detail")
        }
        guard let maxAge = settings.autoClear.maxAge else { return nil }
        let left = item.addedAt.addingTimeInterval(maxAge).timeIntervalSince(now)
        let days = Int((left / 86_400).rounded(.up))
        if days <= 1 { return String(localized: "Cleared within a day · pin it to keep it", comment: "Shelf item's detail") }
        return String(localized: "Cleared in \(days) days · pin it to keep it", comment: "Shelf item's detail; days left")
    }
}

/// The small pin on a pinned tile's top-left corner (the checkmark uses the top-right while choosing).
struct ShelfPinBadge: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.black)
            .rotationEffect(.degrees(45))
            .frame(width: 16, height: 16)
            .background(.white, in: Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// The header's right half for a moment after pinning: "Pinned · Won't be cleared" and Undo.
struct ShelfPinNoteView: View {
    let module: ShelfModule
    let note: ShelfPinNote

    var body: some View {
        HStack(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                if note.pinned {
                    Text("\(note.title) · Won't be cleared", comment: "Shelf header after pinning; \"Pinned\" or \"Pinned 3\"")
                }
                Text(note.title)
                Color.clear.frame(width: 0)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
            ShelfPillButton(title: String(localized: "Undo")) { module.undoPin() }
                .accessibilityHint(Text(note.pinned ? "Unpins what you just pinned." : "Pins it again."))
        }
        .accessibilityElement(children: .contain)
    }
}
