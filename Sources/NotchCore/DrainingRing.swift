import AppKit
import SwiftUI

/// What a draining ring shows (the Timer's, Keep Awake's): a still ring (paused, or between states), or one
/// that drains to nothing at an end date. Pure, so it can be checked without drawing anything.
public enum RingPlan: Equatable, Sendable {
    /// A ring holding at this fraction (1 = full).
    case still(Double)
    /// A ring draining until `end`; `total` is the time a full ring stands for.
    case drain(end: Date, total: TimeInterval)

    /// How full the ring is at `now`.
    public func fraction(at now: Date) -> Double {
        switch self {
        case .still(let fraction): return min(1, max(0, fraction))
        case .drain(let end, let total): return min(1, max(0, end.timeIntervalSince(now) / total))
        }
    }

    /// Seconds until a draining ring is empty (0 when it's still, or already empty).
    public func secondsLeft(at now: Date) -> TimeInterval {
        if case .drain(let end, _) = self { return max(0, end.timeIntervalSince(now)) }
        return 0
    }
}

/// The steps of a draining ring's animation. The ring moves a pixel at a time and not more often than 60
/// times a second, so the screen is redrawn only when something visibly moves: a three-second timer moves
/// smoothly, and an hour-long one redraws a few times a minute, not 60 times a second (AGENTS.md rule 2).
public enum RingSteps {
    /// - Parameters:
    ///   - fraction: how full the ring is now.
    ///   - seconds: time until it's empty.
    ///   - travelPixels: how many device pixels the end of the arc travels from `fraction` to empty.
    /// - Returns: the arc's end value at each step, and the moment each step starts (0…1 of `seconds`).
    ///   The ring holds each value until the next, so there is one more moment than there are values.
    public static func make(fraction: Double, seconds: TimeInterval, travelPixels: Double) -> (values: [Double], times: [Double]) {
        let count = max(1, min(Int((seconds * 60).rounded(.down)), Int(travelPixels.rounded(.up))))
        let values = (0..<count).map { fraction * (1 - Double($0) / Double(count)) }
        let times = (0...count).map { Double($0) / Double(count) }
        return (values, times)
    }
}

/// A ring that drains to empty at its plan's end. White on a faint track: monochrome like everything else
/// (ADR-0029). It moves smoothly all the way, not once a second, and is drawn by Core Animation on the
/// render server, so the app does no work while it moves. A still plan holds it at the exact fraction.
public struct DrainingRing: View {
    let plan: RingPlan
    /// Changes after a wake or a clock change: the ring starts again from the new time.
    let epoch: Int
    let lineWidth: CGFloat
    /// Off-screen pictures: Core Animation layers don't render there, so a plain ring for those.
    let isSnapshot: Bool
    let now: () -> Date

    public init(plan: RingPlan, epoch: Int, lineWidth: CGFloat = 2, isSnapshot: Bool = false, now: @escaping () -> Date) {
        self.plan = plan
        self.epoch = epoch
        self.lineWidth = lineWidth
        self.isSnapshot = isSnapshot
        self.now = now
    }

    public var body: some View {
        Group {
            if isSnapshot {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0, to: plan.fraction(at: now()))
                        .stroke(.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            } else {
                DrainingRingLayers(plan: plan, epoch: epoch, lineWidth: lineWidth, now: now)
            }
        }
        .accessibilityHidden(true)
    }
}

struct DrainingRingLayers: NSViewRepresentable {
    let plan: RingPlan
    let epoch: Int
    let lineWidth: CGFloat
    let now: () -> Date

    func makeNSView(context: Context) -> RingView { RingView() }

    func updateNSView(_ view: RingView, context: Context) {
        view.apply(plan: plan, epoch: epoch, lineWidth: lineWidth, now: now)
    }
}

/// The ring's layers. The arc's end is animated on the render server from where it is now to empty over
/// the time left; any change of plan, a wake or clock change, or coming back on screen starts it again
/// from the real time.
final class RingView: NSView {
    private let track = CAShapeLayer()
    let arc = CAShapeLayer()
    private var plan = RingPlan.still(0)
    private var epoch = 0
    private var lineWidth: CGFloat = 2
    private var now: () -> Date = Date.init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(track)
        layer?.addSublayer(arc)
        for shape in [track, arc] {
            shape.fillColor = nil
            shape.lineCap = .round
        }
        track.strokeColor = NSColor.white.withAlphaComponent(0.25).cgColor
        arc.strokeColor = NSColor.white.cgColor
        arc.strokeStart = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(plan: RingPlan, epoch: Int, lineWidth: CGFloat, now: @escaping () -> Date) {
        self.now = now
        guard plan != self.plan || epoch != self.epoch || lineWidth != self.lineWidth else { return }
        self.plan = plan
        self.epoch = epoch
        if lineWidth != self.lineWidth {
            self.lineWidth = lineWidth
            needsLayout = true
        }
        resync()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [track, arc] {
            shape.frame = bounds
            shape.lineWidth = lineWidth
            shape.path = Self.circle(in: bounds)
        }
        CATransaction.commit()
        resync()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Layers coming back to a window can lose their animation: start from the real time again.
        resync()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        resync()
    }

    /// A circle that starts at 12 o'clock and goes clockwise; the line is centred on the edge, as a
    /// stroked circle is, so it reaches half a line width outside the view.
    private static func circle(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .pi / 2,
            endAngle: .pi / 2 - 2 * .pi,
            clockwise: true
        )
        return path
    }

    /// Puts the arc where the plan says it is at this moment and, when it drains, sets it going.
    private func resync() {
        let moment = now()
        let fraction = plan.fraction(at: moment)
        let seconds = plan.secondsLeft(at: moment)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.removeAnimation(forKey: "drain")
        // The resting value is where it ends up: empty for a draining ring.
        let draining = seconds > 0 && fraction > 0
        arc.strokeEnd = draining ? 0 : fraction
        CATransaction.commit()
        guard draining, bounds.width > 0 else { return }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let radius = min(bounds.width, bounds.height) / 2
        let steps = RingSteps.make(fraction: fraction, seconds: seconds, travelPixels: 2 * .pi * radius * scale * fraction)
        let animation = CAKeyframeAnimation(keyPath: "strokeEnd")
        animation.values = steps.values
        animation.keyTimes = steps.times.map { NSNumber(value: $0) }
        animation.calculationMode = .discrete
        animation.duration = seconds
        arc.add(animation, forKey: "drain")
    }
}
