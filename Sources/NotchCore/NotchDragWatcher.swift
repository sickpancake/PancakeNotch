import AppKit
import os

/// Notices a file drag heading for the notch while it's still a little way below the top edge.
///
/// macOS starts Mission Control when a drag lingers in the menu bar, which is exactly where the notch
/// is. So, like other notch shelves, we open as soon as a content drag enters the area the open notch
/// would cover; the drop then lands well below the edge (ADR-0011). On macOS 27, where file drags
/// start Mission Control too, a module can also ask to keep the pointer just below the menu bar while
/// it's over that area (`MissionControlDragGuard`).
///
/// Event-driven: mouse monitors only (no permission needed for mouse events), and the drag pasteboard
/// is read only once per press, plus while a drag is inside the area.
@MainActor
final class NotchDragWatcher {
    /// The area that opens the notch, in screen coordinates.
    var zone: () -> CGRect = { .zero }
    /// Whether a drag carrying this pasteboard should open the notch.
    var accepts: (NSPasteboard) -> Bool = { _ in false }
    /// The screen y a drag carrying this pasteboard must stay below while it's in the area, or `nil`
    /// to let it reach the top. Asked once per drag, when it's accepted.
    var floor: (NSPasteboard) -> CGFloat? = { _ in nil }
    /// Whether the notch is open now.
    var isOpen: () -> Bool = { false }
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
    /// The content drag's floor (see `floor`), set when it's accepted.
    private var floorY: CGFloat?
    /// The notch is open because of this drag.
    private var didOpen = false
    /// The last time this drag asked the notch to open.
    private var lastApproach = Date.distantPast
    /// The last time this press was checked for a drag out of the Dock.
    private var lastDockCheck = Date.distantPast

    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "notch")

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        drags = DragPasteboardTracker(settledCount: DragPasteboard.changeCount)
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
                let count = DragPasteboard.changeCount
                if event.type == .leftMouseDown { self.drags.ownPressed(count: count) } else { self.drags.settled(count: count) }
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

    /// A drag this app took part in ended without a release the monitors see: a drop on the notch, or
    /// a drag out of the Shelf. What's on the drag pasteboard now is that drag's, not a new one.
    func dragSettled() {
        guard isRunning else { return }
        drags.settled(count: DragPasteboard.changeCount)
    }

    private func pressed() {
        drags.pressed(count: DragPasteboard.changeCount)
        press = .unknown
        didOpen = false
        lastDockCheck = .distantPast
    }

    private func dragged() {
        guard press != .other else { return }
        var location = NSEvent.mouseLocation
        let zone = zone()
        let isNear = NotchLayout.area(zone, contains: location)
        if press == .unknown {
            guard isNear else { return }
            var pasteboard = NSPasteboard(name: .drag)
            if !drags.isNewDrag(count: DragPasteboard.changeCount) {
                // The Dock drags with a pasteboard of its own, so its drags leave the shared one alone.
                // Checked at most a few times a second while such a drag stays near.
                guard Date().timeIntervalSince(lastDockCheck) > 0.2 else { return }
                lastDockCheck = Date()
                guard DockDrag.isActive else { return }
                pasteboard = DockDrag.pasteboard
            }
            press = accepts(pasteboard) ? .content : .other
            if press == .content {
                self.pasteboard = pasteboard
                floorY = floor(pasteboard)
            } else {
                logger.info("Drag near the notch not taken: \(pasteboard.types?.map(\.rawValue) ?? [], privacy: .public)")
            }
        }
        guard press == .content, let pasteboard else { return }
        if isNear, let floorY, let point = MissionControlDragGuard.floorPoint(for: location, zone: zone, floorY: floorY) {
            MissionControlDragGuard.movePointer(to: point)
            location = point
        }
        if isNear != didOpen {
            // Entered or left the area: AppKit's own drag events only start once the pointer is over the window.
            didOpen = isNear
            if isNear { approach(pasteboard) } else { onLeave() }
        } else if isNear, !isOpen(), Date().timeIntervalSince(lastApproach) > 0.3 {
            // It couldn't open (Mission Control was up): try again while the drag stays near.
            approach(pasteboard)
        }
        if isNear { onMove(pasteboard, location) }
    }

    private func approach(_ pasteboard: NSPasteboard) {
        lastApproach = Date()
        onApproach(pasteboard)
    }

    private func released() {
        drags.settled(count: DragPasteboard.changeCount)
        press = .other
        pasteboard = nil
        guard didOpen else { return }
        didOpen = false
        onLeave()
    }
}

/// The drag pasteboard's change count, fresh from the pasteboard server.
///
/// On macOS 27 a running app's `NSPasteboard(name: .drag)` keeps its old count and contents during
/// another app's drag (Finder's), so a new drag looked like a window move. Syncing through the
/// Pasteboard Manager first brings both up to date (measured 2026-10-25).
@MainActor
enum DragPasteboard {
    private static let reference: Pasteboard? = {
        var reference: Pasteboard?
        guard PasteboardCreate(NSPasteboard.Name.drag.rawValue as CFString, &reference) == noErr else { return nil }
        return reference
    }()

    static var changeCount: Int {
        if let reference { _ = PasteboardSynchronize(reference) }
        return NSPasteboard(name: .drag).changeCount
    }
}

/// A drag out of the Dock (a stack, a folder or the Dock itself). Its pasteboard is the Dock's own and
/// can't be read from here, so the shared drag pasteboard never changes; but while it lasts the Dock
/// covers the screen with a window at `overlayLayer` (measured on macOS 27.0.1, 2026-10-25; a window move
/// shows none). Everything in the Dock is a file, so such a drag stands in as one.
@MainActor
enum DockDrag {
    static let overlayLayer = 500

    /// Whether the Dock is dragging something now. One window-list read (no permission needed).
    static var isActive: Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier,
              let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return false }
        return list.contains { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == dock
                && (info[kCGWindowLayer as String] as? Int).map { $0 >= overlayLayer } == true
        }
    }

    /// Stands in for the Dock's pasteboard when asking modules about the drag: it only says "files".
    /// The drop itself still reads the real pasteboard, which AppKit hands to the notch window.
    static let pasteboard: NSPasteboard = {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.declareTypes([.fileURL], owner: nil)
        return pasteboard
    }()
}

/// Tells a drag of content apart from a window move or a text selection, which don't write to the
/// drag pasteboard: the pasteboard's change count went up since the last press ended.
///
/// Comparing with the count at the press alone isn't enough: Finder can write its drag as the button
/// goes down, before the press reaches this app, so its drags looked like window moves.
struct DragPasteboardTracker {
    /// The count once the last press ended (or, for a press in this app's own windows whose release
    /// may go unseen, when it began).
    private var settledCount: Int
    /// The count when the current press reached this app.
    private var pressCount = 0

    init(settledCount: Int = 0) {
        self.settledCount = settledCount
    }

    mutating func pressed(count: Int) {
        pressCount = count
    }

    /// A press in this app's own windows. If it starts a drag out of the app, its release goes unseen;
    /// `settled(count:)` must then be called when that drag ends.
    mutating func ownPressed(count: Int) {
        settledCount = count
    }

    mutating func settled(count: Int) {
        settledCount = count
    }

    /// Whether the current press is dragging something, given the pasteboard's count now.
    func isNewDrag(count: Int) -> Bool {
        count != pressCount || count != settledCount
    }
}

/// Keeps a file drag out of the menu bar above the notch, where macOS 27 starts Mission Control
/// (ADR-0011). While a content drag is over the open notch's area, the pointer stops a little below the
/// menu bar, like a floor; it needs no permission and ends with the drag. Other apps that solved this
/// (Dropzone 5, Droppy) do the same, and also only on macOS 27.
public enum MissionControlDragGuard {
    /// How far below the menu bar the pointer stops.
    static let margin: CGFloat = 6

    /// Whether this macOS starts Mission Control for file drags in the menu bar.
    public static let isNeeded = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
    )

    /// The screen y the pointer stays below, for a menu bar `stripHeight` tall at the top of `screenFrame`.
    static func floorY(screenFrame: CGRect, stripHeight: CGFloat) -> CGFloat {
        screenFrame.maxY - stripHeight - margin
    }

    /// Where to move a pointer at `location` (screen coordinates, y up), or `nil` to leave it.
    static func floorPoint(for location: CGPoint, zone: CGRect, floorY: CGFloat) -> CGPoint? {
        guard location.y > floorY, location.x >= zone.minX, location.x < zone.maxX else { return nil }
        return CGPoint(x: location.x, y: floorY)
    }

    /// Moves the pointer without breaking the drag. Quartz measures from the top of the main display.
    @MainActor
    static func movePointer(to point: CGPoint) {
        guard let mainHeight = NSScreen.screens.first?.frame.maxY else { return }
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: mainHeight - point.y))
        // A warp freezes the pointer for a moment; reconnecting the mouse lifts that at once.
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
