import AppKit
import NotchCore
import SwiftUI
import TimerCore

extension RingPlan {
    /// The timer's ring: draining to its end while it runs, still while paused or idle.
    init(_ timer: CountdownTimer) {
        if let end = timer.end, timer.total > 0 {
            self = .drain(end: end, total: timer.total)
        } else {
            self = .still(timer.fractionLeft(at: .distantPast))
        }
    }
}

/// A ring that drains as the timer runs. White on a faint track: monochrome like everything else
/// (ADR-0029). It moves smoothly all the way, not once a second, and is drawn by Core Animation on the
/// render server, so the app does no work while it moves. Pausing holds it at the exact fraction.
struct TimerRing: View {
    let module: TimerModule
    let size: CGFloat
    var lineWidth: CGFloat = 2

    var body: some View {
        let center = module.center
        let plan = RingPlan(center.timer)
        // Read here so the ring starts again from the new time after a wake or a clock change.
        let epoch = center.clockEpoch
        DrainingRing(plan: plan, epoch: epoch, lineWidth: lineWidth, isSnapshot: module.isSnapshot, now: { center.now })
            .frame(width: size, height: size)
    }
}

