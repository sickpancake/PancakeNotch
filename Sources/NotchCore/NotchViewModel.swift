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

    @ObservationIgnored private let openDelay: Duration
    @ObservationIgnored private let closeDelay: Duration
    @ObservationIgnored private var hoverTask: Task<Void, Never>?

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
        withAnimation(Self.animation(opening: opening)) {
            state = newState
        }
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
