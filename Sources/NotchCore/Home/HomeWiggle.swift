import SwiftUI

/// Drawing-time motion independent of hover animations. A paused schedule does no work when off.
public struct HomeWiggle: ViewModifier {
    public let isOn: Bool
    public let seed: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isOn: Bool, seed: Int) { self.isOn = isOn; self.seed = seed }

    public func body(content: Content) -> some View {
        let active = isOn && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { tick in
            let phase = Double(seed.magnitude % 19)
            let angle = active ? sin(tick.date.timeIntervalSinceReferenceDate * (20 + phase / 10) + phase) * 0.9 : 0
            content.rotationEffect(.degrees(angle))
                .animation(active || reduceMotion ? nil : .easeOut(duration: 0.15), value: active)
                .transaction { if active { $0.animation = nil } }
        }
    }
}
