import AppKit
import Quartz
import SwiftUI

/// Invisible AppKit layer over a tile (or the drag-all handle, `itemID == nil`) that handles clicks,
/// the right-click menu, Quick Look and dragging items out. SwiftUI draws the tile underneath.
///
/// Clicks: one click shows the item in the tall notch, a double-click copies it, ⌘/⇧-click selects.
struct ShelfTileInteraction: NSViewRepresentable {
    let module: ShelfModule
    let itemID: UUID?

    func makeNSView(context: Context) -> ShelfTileNSView {
        ShelfTileNSView(module: module, itemID: itemID)
    }

    func updateNSView(_ view: ShelfTileNSView, context: Context) {
        view.module = module
        view.itemID = itemID
    }
}

final class ShelfTileNSView: NSView, NSDraggingSource {
    var module: ShelfModule
    var itemID: UUID?
    private var mouseDownEvent: NSEvent?
    private var draggedIDs: [UUID] = []
    /// A plain click on an already-selected tile only narrows the selection on mouse-up,
    /// so dragging a multi-selection doesn't drop it.
    private var narrowSelectionOnMouseUp = false
    /// A plain single click shows the item once the button comes up without a drag.
    private var expandOnMouseUp = false

    init(module: ShelfModule, itemID: UUID?) {
        self.module = module
        self.itemID = itemID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // The notch panel is rarely key: the first click must still act.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        narrowSelectionOnMouseUp = false
        expandOnMouseUp = false
        module.cancelPendingExpand()
        module.requestFocus()
        window?.makeFirstResponder(self)
        guard let itemID else { return }
        let modifiers = event.modifierFlags.intersection([.command, .shift])
        if event.clickCount >= 2, !module.isChoosing, modifiers.isEmpty {
            module.copy(module.targets(for: itemID))
        } else if !modifiers.isEmpty || module.isChoosing {
            module.click(itemID, modifiers: modifiers)
        } else if module.selection.contains(itemID), module.selection.count > 1 {
            narrowSelectionOnMouseUp = true
            expandOnMouseUp = true
        } else {
            module.click(itemID, modifiers: [])
            expandOnMouseUp = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if narrowSelectionOnMouseUp, let itemID { module.click(itemID, modifiers: []) }
        if expandOnMouseUp, let itemID { module.scheduleExpand(itemID) }
        narrowSelectionOnMouseUp = false
        expandOnMouseUp = false
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent else { return }
        let distance = hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y)
        guard distance > 3 else { return }
        mouseDownEvent = nil
        narrowSelectionOnMouseUp = false
        expandOnMouseUp = false
        beginDragOut(with: start)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let itemID else { return }
        module.cancelPendingExpand()
        module.requestFocus()
        window?.makeFirstResponder(self)
        if !module.selection.contains(itemID) { module.click(itemID, modifiers: []) }
        module.showMenu(ShelfMenu.entries(for: module.targets(for: itemID), module: module, anchor: self))
    }

    // MARK: Dragging out

    private func beginDragOut(with event: NSEvent) {
        let payload = module.dragPayload(for: itemID)
        guard !payload.isEmpty else { return }
        draggedIDs = payload.map(\.item.id)
        let size = ShelfThumbnails.pointSize
        let items = payload.enumerated().map { index, entry in
            let dragItem = NSDraggingItem(pasteboardWriter: entry.writer)
            let image = module.thumbnails.images[entry.item.id] ?? Self.placeholder(for: entry.item)
            // Fan multiple items out slightly so the stack reads as several.
            let offset = CGFloat(min(index, 4)) * 4
            let origin = CGPoint(x: bounds.midX - size.width / 2 + offset, y: bounds.midY - size.height / 2 - offset)
            dragItem.setDraggingFrame(CGRect(origin: origin, size: size), contents: image)
            return dragItem
        }
        module.setDraggingOut(true)
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .stack
    }

    private static func placeholder(for item: ShelfItem) -> NSImage {
        let symbol = switch item.kind {
        case .file: "doc"
        case .text: "text.quote"
        case .link: "link"
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        module.dragOperations(outside: context == .outsideApplication)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        module.dragOutEnded(draggedIDs, operation: operation)
        draggedIDs = []
    }

    // MARK: Quick Look (the shared preview panel looks for a controller along the responder chain)

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { module.quickLook.begin(panel) }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { module.quickLook.end(panel) }
    }
}

/// The right-click menu for one or more shelf items (shown by `ShelfMenuPanel`).
@MainActor
enum ShelfMenu {
    static func entries(for items: [ShelfItem], module: ShelfModule, anchor: NSView) -> [ShelfMenuEntry] {
        var entries: [ShelfMenuEntry] = []
        let files = items.filter(\.isFile)
        let single = items.count == 1 ? items.first : nil
        var group = false

        func add(_ title: String, _ symbol: String, destructive: Bool = false, _ action: @escaping @MainActor () -> Void) {
            entries.append(ShelfMenuEntry(title: title, symbol: symbol, isDestructive: destructive, startsGroup: group && !entries.isEmpty, action: action))
            group = false
        }

        if !files.isEmpty {
            add(String(localized: "Open"), "arrow.up.forward.app") { module.open(files) }
            add(String(localized: "Quick Look"), "eye") { module.quickLook(files) }
            add(String(localized: "Show in Finder"), "folder") { module.reveal(files) }
            add(String(localized: "Copy Path"), "link") { module.copyPaths(files) }
        }
        if let single, case .link = single.kind {
            add(String(localized: "Open Link"), "safari") { module.open([single]) }
        }
        if items.contains(where: { !$0.isFile }) {
            add(String(localized: "Copy"), "doc.on.doc") { module.copy(items.filter { !$0.isFile }) }
        }
        group = true
        add(String(localized: "AirDrop"), "dot.radiowaves.left.and.right") { module.airDrop(items) }
        add(String(localized: "Share…"), "square.and.arrow.up") { module.share(items, from: anchor) }
        group = true
        add(items.count > 1
            ? String(localized: "Remove \(items.count) Items", comment: "Context menu; several shelf items")
            : String(localized: "Remove"), "trash", destructive: true) { module.remove(items.map(\.id)) }
        return entries
    }
}
