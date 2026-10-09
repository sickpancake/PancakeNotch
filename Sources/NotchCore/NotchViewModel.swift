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

    @ObservationIgnored private let openDelay: Duration
    @ObservationIgnored private let closeDelay: Duration
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var transitionID = 0

    public init(
        layout: NotchLayout,
        state: NotchState = .closed,
        openDelay: Duration = .milliseconds(150),
        closeDelay: Duration = .milliseconds(300)
    ) {
        self.layout = layout
        self.state = state
        self.openDelay = openDelay
        self.closeDelay = closeDelay
    }

    /// Called when the pointer enters or leaves the notch outline.
    public func hoverChanged(_ isHovering: Bool) {
        hoverTask?.cancel()
        guard !isPinned else { return }
        if isHovering {
            guard state != .expanded else { return }
            hoverTask = Task { [weak self, openDelay] in
                try? await Task.sleep(for: openDelay)
                guard !Task.isCancelled else { return }
                self?.open()
            }
        } else {
            guard state == .expanded else { return }
            hoverTask = Task { [weak self, closeDelay] in
                try? await Task.sleep(for: closeDelay)
                guard !Task.isCancelled else { return }
                self?.close()
            }
        }
    }

    public func open() {
        hoverTask?.cancel()
        transition(to: .expanded)
    }

    public func close() {
        hoverTask?.cancel()
        transition(to: restingState)
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
    }

    /// Returns to the resting state without animating (e.g. the display went away).
    public func reset() {
        hoverTask?.cancel()
        transitionID += 1
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
