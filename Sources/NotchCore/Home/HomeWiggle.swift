import SwiftUI

/// Home's phone-style wiggle while editing (the app window's editor and edit mode in the notch), as plain
/// maths on the clock, so it can't be stopped or frozen by other animations (hover, popovers) and can be
/// tested.
///
/// The angle is a sine of the time. How much of it shows (`amplitude`) eases between 0 and 1 over
/// `rampDuration` whenever wiggling is switched on or off, so widgets settle level instead of stopping
/// mid-tilt. Once the amplitude is back at 0 nothing needs to tick any more.
public struct WiggleMotion: Equatable, Sendable {
    /// The tilt at full strength, either way.
    public static let maxDegrees = 0.9
    /// How long it takes to start or settle.
    public static let rampDuration: TimeInterval = 0.25

    /// The amplitude when it last changed course.
    public private(set) var level = 0.0
    /// 1 while wiggling, 0 while settling or still.
    public private(set) var target = 0.0
    public private(set) var since = Date.distantPast

    public init() {}

    /// How much of the wiggle shows at `date`, from 0 to 1.
    public func amplitude(at date: Date) -> Double {
        let progress = min(1, max(0, date.timeIntervalSince(since) / Self.rampDuration))
        let eased = progress * progress * (3 - 2 * progress)
        return level + (target - level) * eased
    }

    /// Wiggling is off and the widget is level again, so the timeline can stop.
    public func isLevel(at date: Date) -> Bool { target == 0 && amplitude(at: date) == 0 }

    /// The same motion, now heading for wiggling (`true`) or level (`false`) from wherever it is.
    public func retargeted(wiggling: Bool, at date: Date) -> Self {
        var next = self
        next.level = amplitude(at: date)
        next.target = wiggling ? 1 : 0
        next.since = date
        return next
    }

    /// The tilt in degrees at `date`: each widget out of step with the next by its `seed`.
    public func degrees(at date: Date, seed: Int) -> Double {
        let amplitude = amplitude(at: date)
        guard amplitude > 0 else { return 0 }
        let period = 2 * (0.13 + Double(abs(seed) % 4) * 0.012)
        let phase = Double(abs(seed) % 7) * 0.9
        let turn = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return sin(2 * .pi * turn + phase) * Self.maxDegrees * amplitude
    }

    /// Always the same number for a widget, so it wiggles the same way each time.
    public static func seed(for kind: HomeWidgetKind) -> Int {
        kind.rawValue.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    }
}

/// The wiggle: a small tilt back and forth. It's driven by a `TimelineView` that runs only while the
/// wiggle is on or settling, then pauses, so nothing ticks otherwise. The content keeps its identity
/// either way (its hover, focus and open size list are untouched), and the tilt never animates through
/// another animation's transaction. None with Reduce Motion.
public struct HomeWiggle: ViewModifier {
    let isOn: Bool
    let seed: Int
    @State private var motion = WiggleMotion()
    @State private var isResting = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isOn: Bool, seed: Int) {
        self.isOn = isOn
        self.seed = seed
    }

    public func body(content: Content) -> some View {
        let wiggling = isOn && !reduceMotion
        TimelineView(.animation(paused: isResting)) { timeline in
            content.animation(nil) { $0.rotationEffect(.degrees(motion.degrees(at: timeline.date, seed: seed))) }
        }
        .task(id: wiggling) {
            let now = Date.now
            motion = motion.retargeted(wiggling: wiggling, at: now)
            guard wiggling || !motion.isLevel(at: now) else { isResting = true; return }
            isResting = false
            guard !wiggling else { return }
            // Settling: tick until it's level, then stop. One sleeping task, no timer.
            try? await Task.sleep(for: .seconds(WiggleMotion.rampDuration + 0.05))
            guard !Task.isCancelled else { return }
            isResting = true
        }
    }
}
