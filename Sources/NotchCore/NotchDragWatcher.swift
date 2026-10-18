import AppKit
import os

/// Notices a file drag heading for the notch while it's still a little way below the top edge.
///
/// macOS starts Mission Control when a drag touches the top of the screen, which is exactly where the
/// notch is. So, like other notch shelves, we open as soon as a content drag enters the area the open
/// notch would cover; the drop then lands well below the edge (ADR-0011).
///
/// Event-driven: mouse monitors only (no permission needed for mouse events), and the drag pasteboard
/// is read only once per press, plus while a drag is inside the area.
@MainActor
final class NotchDragWatcher {
    /// The area that opens the notch, in screen coordinates.
    var zone: () -> CGRect = { .zero }
    /// Whether a drag carrying this pasteboard should open the notch.
    var accepts: (NSPasteboard) -> Bool = { _ in false }
    /// The drag came near: open the notch.
    var onApproach: (NSPasteboard) -> Void = { _ in }
    /// A drag that opened the notch moved within the area (screen coordinates).
    var onMove: (NSPasteboard, CGPoint) -> Void = { _, _ in }
    /// A drag that opened the notch moved away again, or was released (anywhere).
    var onLeave: () -> Void = {}

    private var monitors: [Any] = []
    private var drags = DragPasteboardTracker()
    /// What the current press is: not yet known, a drag of content we take, or anything else.
    private enum Press { case unknown, content, other }
    private var press = Press.other
    /// The drag pasteboard, kept while a content drag is under way.
    private var pasteboard: NSPasteboard?
    /// The notch is open because of this drag.
    private var didOpen = false

    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "notch")

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        drags = DragPasteboardTracker(settledCount: NSPasteboard(name: .drag).changeCount)
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
        // Presses in this app's own windows (the notch, the app window) never reach the global monitors,
        // but a drag out of the Shelf writes to the drag pasteboard too.
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let count = NSPasteboard(name: .drag).changeCount
                if event.type == .leftMouseDown { self.drags.ownPressed() } else { self.drags.settled(count: count) }
            }
            return event
        }
        if let local { monitors.append(local) }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        press = .other
        pasteboard = nil
        didOpen = false
    }

    private func pressed() {
        drags.pressed(count: NSPasteboard(name: .drag).changeCount)
        press = .unknown
        didOpen = false
    }

    private func dragged() {
        guard press != .other else { return }
        let location = NSEvent.mouseLocation
        let isNear = NotchLayout.area(zone(), contains: location)
        if press == .unknown {
            guard isNear else { return }
            let pasteboard = NSPasteboard(name: .drag)
            guard drags.isNewDrag(count: pasteboard.changeCount) else { return }
            press = accepts(pasteboard) ? .content : .other
            if press == .content {
                self.pasteboard = pasteboard
            } else {
                logger.info("Drag near the notch not taken: \(pasteboard.types?.map(\.rawValue) ?? [], privacy: .public)")
            }
        }
        guard press == .content, let pasteboard else { return }
        if isNear != didOpen {
            // Entered or left the area: AppKit's own drag events only start once the pointer is over the window.
            didOpen = isNear
            isNear ? onApproach(pasteboard) : onLeave()
        }
        if isNear { onMove(pasteboard, location) }
    }

    private func released() {
        drags.settled(count: NSPasteboard(name: .drag).changeCount)
        press = .other
        pasteboard = nil
        guard didOpen else { return }
        didOpen = false
        onLeave()
    }
}

/// Tells a drag of content apart from a window move or a text selection, which don't write to the
/// drag pasteboard: the pasteboard's change count went up since the last press ended.
///
/// Comparing with the count at the press alone isn't enough: Finder can write its drag as the button
/// goes down, before the press reaches this app, so its drags looked like window moves.
struct DragPasteboardTracker {
    /// The count once the last press ended; `nil` after a press in this app's own windows, whose
    /// release (and so whether it started a drag) may go unseen.
    private var settledCount: Int?
    /// The count when the current press reached this app.
    private var pressCount = 0

    init(settledCount: Int? = nil) {
        self.settledCount = settledCount
    }

    mutating func pressed(count: Int) {
        pressCount = count
    }

    mutating func ownPressed() {
        settledCount = nil
    }

    mutating func settled(count: Int) {
        settledCount = count
    }

    /// Whether the current press is dragging something, given the pasteboard's count now.
    func isNewDrag(count: Int) -> Bool {
        if count != pressCount { return true }
        guard let settledCount else { return false }
        return count != settledCount
    }
}
