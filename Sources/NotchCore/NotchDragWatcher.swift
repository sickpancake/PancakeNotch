import AppKit

/// Notices a file drag heading for the notch while it's still a little way below the top edge.
///
/// macOS starts Mission Control when a drag touches the top of the screen, which is exactly where the
/// notch is. So, like other notch shelves, we open as soon as a content drag enters the area the open
/// notch would cover; the drop then lands well below the edge (ADR-0011).
///
/// Event-driven: global mouse monitors only (no permission needed for mouse events), and the drag
/// pasteboard is read only once per press, plus while a drag is inside the area.
@MainActor
final class NotchDragWatcher {
    /// The area that opens the notch, in screen coordinates.
    var zone: () -> CGRect = { .zero }
    /// Whether a drag carrying this pasteboard should open the notch.
    var accepts: (NSPasteboard) -> Bool = { _ in false }
    /// The drag came near: open the notch.
    var onApproach: () -> Void = {}
    /// A drag that opened the notch moved within the area (screen coordinates).
    var onMove: (NSPasteboard, CGPoint) -> Void = { _, _ in }
    /// A drag that opened the notch moved away again, or was released (anywhere).
    var onLeave: () -> Void = {}

    private var monitors: [Any] = []
    private var pressChangeCount = 0
    /// What the current press is: not yet known, a drag of content we take, or anything else.
    private enum Press { case unknown, content, other }
    private var press = Press.other
    /// The drag pasteboard, kept while a content drag is under way.
    private var pasteboard: NSPasteboard?
    /// The notch is open because of this drag.
    private var didOpen = false

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        let events: [(NSEvent.EventTypeMask, @MainActor (NotchDragWatcher) -> Void)] = [
            (.leftMouseDown, { $0.pressed() }),
            (.leftMouseDragged, { $0.dragged() }),
            (.leftMouseUp, { $0.released() }),
        ]
        for (mask, handler) in events {
            let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handler(self)
                }
            }
            if let monitor { monitors.append(monitor) }
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        press = .other
        pasteboard = nil
        didOpen = false
    }

    private func pressed() {
        // A new drag writes to the drag pasteboard, bumping its change count; window moves and text
        // selections don't.
        pressChangeCount = NSPasteboard(name: .drag).changeCount
        press = .unknown
        didOpen = false
    }

    private func dragged() {
        guard press != .other else { return }
        let location = NSEvent.mouseLocation
        let isNear = zone().contains(location)
        if press == .unknown {
            guard isNear else { return }
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != pressChangeCount else { return }
            press = accepts(pasteboard) ? .content : .other
            if press == .content { self.pasteboard = pasteboard }
        }
        guard press == .content, let pasteboard else { return }
        if isNear != didOpen {
            // Entered or left the area: AppKit's own drag events only start once the pointer is over the window.
            didOpen = isNear
            isNear ? onApproach() : onLeave()
        }
        if isNear { onMove(pasteboard, location) }
    }

    private func released() {
        press = .other
        pasteboard = nil
        guard didOpen else { return }
        didOpen = false
        onLeave()
    }
}
