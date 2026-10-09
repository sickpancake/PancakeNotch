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
            guard state > restingState else { return }
            schedule(after: behavior.closeDelay) { $0.close() }
        }
    }

    /// A click opens the notch, or shrinks the open panel to the compact version (ADR-0011).
    public func tap() {
        guard state == .expanded else {
            open()
            return
        }
        hoverTask?.cancel()
        collapsedByClick = true
        transition(to: .compact)
        // The click was usually on the panel body, below the compact notch: let it linger, then rest.
        if !layout.windowFrame(for: .compact).contains(pointerLocation()) {
            schedule(after: collapseLinger) { $0.close() }
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
        transitionID += 1
        let id = transitionID
        fitWindow?(max(state, newState))
        withAnimation(Self.animation(opening: opening)) {
            state = newState
        } completion: { [weak self] in
            // Shrink only after the latest animation, so an earlier one can't clip a newer one.
            guard let self, self.transitionID == id else { return }
            self.fitWindow?(self.state)
        }
        if opening { onOpen?() }
    }

    /// Returns to the resting state without animating (e.g. the display went away).
    public func reset() {
        hoverTask?.cancel()
        transitionID += 1
        collapsedByClick = false
        state = restingState
        fitWindow?(state)
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
