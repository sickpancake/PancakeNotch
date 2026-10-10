import AppKit
import Observation
import SwiftUI

/// Owns the notch state and the hover/click rules that move between states (ADR-0011).
@MainActor
@Observable
public final class NotchViewModel {
    public private(set) var state: NotchState
    public var layout: NotchLayout

    /// Where the notch rests when not expanded: `.compact` while a module has live info (M3+).
    public var restingState: NotchState = .closed {
        didSet { if state != .expanded { transition(to: restingState) } }
    }

    /// Keeps the current state regardless of hover (used by `PANCAKENOTCH_DEBUG_STATE`).
    public var isPinned = false

    /// The module shown in the notch (Shelf, later Now Playing). `nil` shows the placeholder and refuses drops.
    public var module: (any NotchModule)? {
        didSet {
            guard module !== oldValue else { return }
            oldValue?.attach(to: nil)
            module?.attach(to: self)
            // Attached while already open (e.g. pinned with PANCAKENOTCH_DEBUG_STATE=expanded).
            if state == .expanded { module?.notchDidOpen() }
        }
    }

    /// Gives the notch keyboard focus, e.g. after a click inside the Shelf. Set by the window controller.
    @ObservationIgnored public var requestKeyFocus: (() -> Void)?
    /// Hands keyboard focus back to the previous app. Called when the notch leaves the expanded state.
    @ObservationIgnored public var releaseKeyFocus: (() -> Void)?

    /// Asks the window to fit a state. Called with the larger state before an animation starts,
    /// and with the final state once it settles.
    @ObservationIgnored public var fitWindow: ((NotchState) -> Void)?

    /// Called each time the notch opens.
    @ObservationIgnored public var onOpen: (() -> Void)?

    /// Hover delays and haptics from Settings.
    @ObservationIgnored public var behavior: NotchBehavior
    /// How long the compact notch stays after a click shrinks it, if the pointer isn't on it.
    @ObservationIgnored private let collapseLinger: Duration
    /// Current pointer position in screen coordinates; injectable for tests.
    @ObservationIgnored private let pointerLocation: @MainActor () -> CGPoint
    /// Set when a click shrinks the panel: hovering the compact notch then doesn't reopen it.
    @ObservationIgnored private var collapsedByClick = false
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var transitionID = 0

    public init(
        layout: NotchLayout,
        state: NotchState = .closed,
        behavior: NotchBehavior = NotchBehavior(),
        collapseLinger: Duration = .seconds(1),
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    ) {
        self.layout = layout
        self.state = state
        self.behavior = behavior
        self.collapseLinger = collapseLinger
        self.pointerLocation = pointerLocation
    }

    /// Called when the pointer enters or leaves the notch outline.
    public func hoverChanged(_ isHovering: Bool) {
        hoverTask?.cancel()
        guard !isPinned else { return }
        if isHovering {
            guard state != .expanded, !collapsedByClick else { return }
            schedule(after: behavior.openDelay) { model in
                model.open()
                if model.behavior.hapticOnOpen {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                }
            }
        } else {
            collapsedByClick = false
            scheduleCloseIfIdle()
        }
    }

    /// A drag from another app entered the notch: open right away, no hover delay (ADR-0011).
    public func dragEntered() {
        guard !isPinned else { return }
        hoverTask?.cancel()
        if state != .expanded { open() }
    }

    /// A file drag elsewhere on screen came near the notch: open before it reaches the top edge, where
    /// macOS would start Mission Control instead (ADR-0011).
    public func dragApproached() {
        dragEntered()
    }

    /// A drag that opened the notch early moved away or was released, maybe somewhere else (or Mission
    /// Control took it). AppKit sends no hover events during a drag, so check where the pointer is now.
    /// Over the notch, the window's own drag events handle the drop (and may not have arrived yet).
    public func approachingDragEnded() {
        guard !layout.outlineFrame(for: state).contains(pointerLocation()) else { return }
        module?.dragEnded()
        scheduleCloseIfIdle()
    }

    /// Grows the open panel to the taller version a module asked for (the Shelf's editor and preview),
    /// or back. The panel goes back to normal on its own when the notch closes.
    public func setTall(_ tall: Bool) {
        guard layout.isTall != tall, !tall || state == .expanded else { return }
        transitionID += 1
        let id = transitionID
        var target = layout
        target.isTall = tall
        withAnimation(Self.animation(opening: tall)) {
            layout = target
        } completion: { [weak self] in
            guard let self, self.transitionID == id else { return }
            self.fitWindow?(self.state)
        }
        // Grow the window now, shrink it once the animation settles.
        if tall { fitWindow?(state) }
    }

    /// The drag left the notch without dropping: close like a hover exit.
    public func dragExited() {
        module?.dragEnded()
        scheduleCloseIfIdle()
    }

    /// A drag over the notch finished (dropped or cancelled). The pointer may have left during it,
    /// and AppKit sends no hover events while dragging, so check where it is now.
    public func dragConcluded() {
        module?.dragEnded()
        closeIfPointerOutside()
    }

    /// The module stopped holding the notch open (menu dismissed, drag-out ended, prompt answered).
    public func holdReleased() {
        closeIfPointerOutside()
    }

    /// A key press while the notch has keyboard focus: the module first, then Escape closes.
    public func handleKey(_ event: NSEvent) -> Bool {
        if module?.handleKey(event) == true { return true }
        if event.keyCode == 53 { // Escape
            close()
            return true
        }
        return false
    }

    /// True while the module needs the notch to stay open.
    var isHeld: Bool { module?.holdsOpen ?? false }

    private func closeIfPointerOutside() {
        guard !layout.outlineFrame(for: state).contains(pointerLocation()) else { return }
        scheduleCloseIfIdle()
    }

    private func scheduleCloseIfIdle() {
        guard !isPinned, state > restingState, !isHeld else { return }
        schedule(after: behavior.closeDelay) { model in
            guard !model.isHeld else { return }
            model.close()
        }
    }

    /// A click opens the notch, or shrinks the open panel to the compact version (ADR-0011).
    public func tap() {
        guard state == .expanded else {
            open()
            return
        }
        guard !isHeld else { return }
        hoverTask?.cancel()
        collapsedByClick = true
        transition(to: .compact)
        // The click was usually on the panel body, below the compact notch: let it linger, then rest.
        if !layout.windowFrame(for: .compact).contains(pointerLocation()) {
            schedule(after: collapseLinger) { model in
                guard !model.isHeld else { return }
                model.close()
            }
        }
    }

    /// Opens or closes the notch, e.g. from the keyboard shortcut.
    public func toggle() {
        state == .expanded ? close() : open()
    }

    public func open() {
        hoverTask?.cancel()
        collapsedByClick = false
        transition(to: .expanded)
    }

    public func close() {
        hoverTask?.cancel()
        collapsedByClick = false
        transition(to: restingState)
    }

    private func schedule(after delay: Duration, _ action: @escaping @MainActor (NotchViewModel) -> Void) {
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }

    /// Moves to `newState` with the matching animation. Opening springs slightly; closing doesn't.
    public func transition(to newState: NotchState) {
        guard newState != state else { return }
        let opening = newState == .expanded
        let closing = state == .expanded
        transitionID += 1
        let id = transitionID
        fitWindow?(max(state, newState))
        withAnimation(Self.animation(opening: opening)) {
            state = newState
            // The tall panel shrinks along with the close.
            if closing { layout.isTall = false }
        } completion: { [weak self] in
            // Shrink only after the latest animation, so an earlier one can't clip a newer one.
            guard let self, self.transitionID == id else { return }
            self.fitWindow?(self.state)
        }
        if opening {
            onOpen?()
            module?.notchDidOpen()
        }
        if closing { leftExpanded() }
    }

    private func leftExpanded() {
        releaseKeyFocus?()
        module?.notchDidClose()
    }

    /// Returns to the resting state without animating (e.g. the display went away).
    public func reset() {
        hoverTask?.cancel()
        transitionID += 1
        collapsedByClick = false
        module?.dragEnded()
        let wasExpanded = state == .expanded
        state = restingState
        layout.isTall = false
        fitWindow?(state)
        if wasExpanded { leftExpanded() }
    }

    static func animation(opening: Bool) -> Animation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .easeInOut(duration: 0.2)
        }
        return opening
            ? .spring(response: 0.42, dampingFraction: 0.8)
            : .spring(response: 0.45, dampingFraction: 1.0)
    }
}
