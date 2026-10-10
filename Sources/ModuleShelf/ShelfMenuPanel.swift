import AppKit
import SwiftUI

/// One row of a `ShelfMenuPanel`.
struct ShelfMenuEntry: Identifiable {
    let id = UUID()
    var title: String
    var symbol: String?
    var isDestructive = false
    /// A thin line above this row, grouping it with the ones below.
    var startsGroup = false
    let action: @MainActor () -> Void
}

/// The Shelf's own right-click menu: a small black pop-up at the pointer, styled like the notch
/// (ADR-0029), instead of the system menu. Also used for the "Open with" app list.
///
/// It never takes keyboard focus: the notch keeps it and forwards ↑ ↓ Return Esc via `handleKey`.
/// A click anywhere else closes it (and still reaches what was clicked).
@MainActor
final class ShelfMenuPanel {
    private let panel: Panel
    private let model: Model
    private var monitors: [Any] = []
    private var appSwitchObserver: (any NSObjectProtocol)?
    private let onClose: () -> Void
    private(set) var isOpen = true

    /// Shows a menu with its top-left corner at `point` (screen coordinates), kept on `screen`.
    init(entries: [ShelfMenuEntry], at point: CGPoint, onClose: @escaping () -> Void) {
        self.onClose = onClose
        model = Model(entries: entries)
        panel = Panel()
        let hosting = FirstClickHostingView(rootView: ShelfMenuView(model: model))
        hosting.sizingOptions = []
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.setFrame(Self.frame(size: size, at: point), display: false)
        model.choose = { [weak self] entry in self?.choose(entry) }
        panel.orderFrontRegardless()

        // Clicks outside close the menu: in other apps (global) and in our other windows (local).
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel { self.close() }
            }
            return event
        }) { monitors.append(local) }
        // Switching apps (⌘Tab) closes it too, like a system menu.
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        NSAccessibility.post(element: hosting, notification: .created)
    }

    /// Keeps the menu fully on screen: below-right of the pointer, flipped when there's no room.
    private static func frame(size: CGSize, at point: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let bounds = screen?.frame ?? CGRect(origin: .zero, size: CGSize(width: 10_000, height: 10_000))
        var origin = CGPoint(x: point.x + 2, y: point.y - size.height - 2)
        if origin.x + size.width > bounds.maxX - 4 { origin.x = point.x - size.width - 2 }
        if origin.y < bounds.minY + 4 { origin.y = point.y + 2 }
        origin.x = max(bounds.minX + 4, origin.x)
        return CGRect(origin: origin, size: size)
    }

    /// ↑ ↓ move the highlight, Return chooses, Esc closes. Returns whether the key was used.
    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125: model.moveHighlight(by: 1)
        case 126: model.moveHighlight(by: -1)
        case 36, 76, 49: // Return, Enter, Space
            if let entry = model.highlighted { choose(entry) }
        case 53: close()
        default: return false
        }
        return true
    }

    private func choose(_ entry: ShelfMenuEntry) {
        close()
        // After the menu is gone, like a system menu.
        Task { @MainActor in entry.action() }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        appSwitchObserver = nil
        panel.orderOut(nil)
        onClose()
    }

    // MARK: Model

    @MainActor
    @Observable
    final class Model {
        let entries: [ShelfMenuEntry]
        var highlightedID: UUID?
        @ObservationIgnored var choose: (ShelfMenuEntry) -> Void = { _ in }

        init(entries: [ShelfMenuEntry]) {
            self.entries = entries
        }

        var highlighted: ShelfMenuEntry? { entries.first { $0.id == highlightedID } }

        func moveHighlight(by step: Int) {
            guard !entries.isEmpty else { return }
            let current = entries.firstIndex { $0.id == highlightedID }
            let next = current.map { ($0 + step + entries.count) % entries.count } ?? (step > 0 ? 0 : entries.count - 1)
            highlightedID = entries[next].id
        }
    }

    /// Borderless, transparent, never key: above the notch, on every Space.
    private final class Panel: NSPanel {
        init() {
            super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            isFloatingPanel = true
            level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
            collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
            isOpaque = false
            backgroundColor = .clear
            hasShadow = true
            isReleasedWhenClosed = false
            hidesOnDeactivate = false
            animationBehavior = .none
            appearance = NSAppearance(named: .darkAqua)
        }

        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    /// The panel is never key, so the first click must already act.
    private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

/// The menu's look: black rounded card, white SF Symbols and labels, gray highlight (ADR-0029).
struct ShelfMenuView: View {
    let model: ShelfMenuPanel.Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.entries) { entry in
                if entry.startsGroup {
                    Rectangle()
                        .fill(.white.opacity(0.12))
                        .frame(height: 1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .accessibilityHidden(true)
                }
                row(entry)
            }
        }
        .padding(5)
        .frame(minWidth: 180, alignment: .leading)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.black)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(Text("Shelf menu"))
    }

    private func row(_ entry: ShelfMenuEntry) -> some View {
        let isHighlighted = model.highlightedID == entry.id
        return HStack(spacing: 8) {
            Group {
                if let symbol = entry.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Color.clear
                }
            }
            .frame(width: 16)
            .accessibilityHidden(true)
            Text(entry.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(entry.isDestructive && !isHighlighted ? 0.75 : 1))
        .padding(.horizontal, 8)
        .frame(height: 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(isHighlighted ? 0.18 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                model.highlightedID = entry.id
            } else if model.highlightedID == entry.id {
                model.highlightedID = nil
            }
        }
        .onTapGesture { model.choose(entry) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(entry.title))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.choose(entry) }
    }
}
