import AppKit

/// Turns a two-finger trackpad scroll into at most one "next / previous module" per gesture
/// (ADR-0011). Only sideways movement counts; momentum after lifting the fingers is ignored, and
/// mouse wheels (no gesture phases) never switch.
struct NotchSwipeTracker {
    enum Phase {
        case began, changed, ended, other

        init(_ event: NSEvent) {
            // Momentum scrolling comes after the fingers lift: never a new swipe.
            guard event.momentumPhase.isEmpty else {
                self = .other
                return
            }
            switch event.phase {
            case .began, .mayBegin: self = .began
            case .changed: self = .changed
            case .ended, .cancelled: self = .ended
            default: self = .other
            }
        }
    }

    /// How far the fingers travel sideways before it counts.
    static let threshold: CGFloat = 36

    private var travelX: CGFloat = 0
    private var travelY: CGFloat = 0
    /// This gesture already switched (or must be left alone): wait for the next one.
    private var isSpent = false

    /// Returns `true` (forward) or `false` (back) once the gesture has gone far enough sideways.
    /// `deltaX` follows the fingers: positive when they move right.
    mutating func handle(phase: Phase, deltaX: CGFloat, deltaY: CGFloat, isPrecise: Bool) -> Bool? {
        switch phase {
        case .began:
            reset()
            accumulate(deltaX, deltaY)
        case .changed:
            accumulate(deltaX, deltaY)
        case .ended:
            reset()
            return nil
        case .other:
            return nil
        }
        guard isPrecise, !isSpent, abs(travelX) >= Self.threshold, abs(travelX) > 2 * abs(travelY) else { return nil }
        isSpent = true
        // The content follows the fingers: moving them left brings in the next module from the right.
        return travelX < 0
    }

    /// Leaves the rest of the current gesture alone (it scrolls something inside a module).
    mutating func ignoreCurrentGesture() {
        isSpent = true
    }

    mutating func reset() {
        travelX = 0
        travelY = 0
        isSpent = false
    }

    private mutating func accumulate(_ deltaX: CGFloat, _ deltaY: CGFloat) {
        travelX += deltaX
        travelY += deltaY
    }
}
