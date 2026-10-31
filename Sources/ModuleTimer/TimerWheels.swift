import AppKit
import NotchCore
import SwiftUI
import TimerCore

/// Hours, minutes and seconds wheels for a custom time, drawn as drums like a phone's: the numbers sit
/// on a turning drum behind a fixed band, follow the fingers or the pointer, and settle on one number
/// when let go. Scroll or drag one up to turn it up; click it to type (two digits fill it and move on);
/// the arrow keys turn it too. VoiceOver adjusts each with swipe up/down.
struct TimerWheels: View {
    let module: TimerModule
    let isCompact: Bool

    var body: some View {
        HStack(spacing: isCompact ? 2 : 4) {
            ForEach(TimerWheelUnit.allCases) { unit in
                if unit != .hours {
                    Text(":")
                        .font(.system(size: isCompact ? 18 : 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .offset(y: -6)
                        .accessibilityHidden(true)
                }
                TimerWheel(module: module, unit: unit, isCompact: isCompact)
            }
        }
    }
}

/// How far a wheel's numbers sit from rest, and where they're heading. The wheel's value changes by a
/// step each time the numbers pass halfway to the next one, so the number in the band is always the
/// value; `offset` is only the part of a step still in motion.
struct WheelMotion: Equatable {
    /// Rows from rest: +0.3 is a third of the way to the next number up (the numbers moved up).
    private(set) var offset: CGFloat = 0
    /// Rows still to travel before coming to rest on a number (after a flick, a release, a click).
    private(set) var remaining: CGFloat = 0

    var isMoving: Bool { remaining != 0 }

    /// The fingers or the pointer moved the numbers by `rows`. Returns the whole steps passed.
    mutating func follow(_ rows: CGFloat) -> Int {
        remaining = 0
        return move(by: rows)
    }

    /// Let go: travel on `extra` rows (a flick), then rest on the nearest number.
    mutating func release(adding extra: CGFloat = 0) {
        remaining = (offset + extra).rounded() - offset
    }

    /// A click of a mouse wheel, or more clicks while the last still slides: one more number each.
    mutating func nudge(_ steps: Int) {
        remaining = (offset + remaining).rounded() + CGFloat(steps) - offset
    }

    /// One frame of travel, `seconds` after the last. Returns the whole steps passed.
    mutating func advance(by seconds: TimeInterval) -> Int {
        guard remaining != 0 else { return 0 }
        // Eases out: covers most of what's left in a few frames, then lands.
        var distance = remaining * CGFloat(1 - exp(-seconds / 0.075))
        if abs(remaining - distance) < 0.002 { distance = remaining }
        remaining -= distance
        let steps = move(by: distance)
        if remaining == 0 { offset = 0 }
        return steps
    }

    /// `remaining` is measured from the offset, so passing a step leaves it as it is.
    private mutating func move(by rows: CGFloat) -> Int {
        offset += rows
        let steps = Int(offset.rounded())
        offset -= CGFloat(steps)
        return steps
    }
}

private struct TimerWheel: View {
    let module: TimerModule
    let unit: TimerWheelUnit
    let isCompact: Bool
    @State private var motion = WheelMotion()
    @State private var lastDrag: CGFloat = 0
    /// The press moved far enough to be a drag, not a click.
    @State private var isDragging = false
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var faceHeight: CGFloat { isCompact ? 26 : 32 }
    private var neighbourHeight: CGFloat { isCompact ? 13 : 16 }
    /// From one number to the next on the drum.
    private var rowHeight: CGFloat { (faceHeight + neighbourHeight) / 2 }
    private var width: CGFloat { isCompact ? 34 : 42 }

    var body: some View {
        let shown = module.shownValue(for: unit)
        let typed = module.typedValue(for: unit)
        let isEditing = module.editing == unit
        VStack(spacing: 0) {
            // Ticks only while the numbers coast (AGENTS.md rule 2).
            TimelineView(.animation(minimumInterval: nil, paused: !motion.isMoving || !module.pageTicks)) { context in
                drum(shown: shown, typed: typed, isEditing: isEditing)
                    .onChange(of: context.date) { old, new in
                        // At most a frame's worth, so the first tick after a pause doesn't jump.
                        turn(by: { $0.advance(by: min(new.timeIntervalSince(old), 1.0 / 30)) })
                    }
            }
            Text(unit.label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 1)
        }
        .contentShape(Rectangle())
        // Off-screen snapshots can't draw AppKit views.
        .overlay {
            if !module.isSnapshot {
                ScrollCatcher(
                    onScroll: { points in turn { $0.follow(points / rowHeight) } },
                    onRest: { settle() },
                    onClick: { steps in module.turn(unit, by: 0); motion.nudge(steps); finishIfReduced() }
                )
            }
        }
        .onHover { isHovered = $0 }
        .onChange(of: module.editing) { _, new in
            if new == unit { motion = WheelMotion() }
        }
        .onChange(of: module.pageTicks) { _, visible in
            if !visible { motion = WheelMotion() }
        }
        // One gesture for both, so a drag never also counts as a click: a press that stays within 4 pt
        // is a click (type into the wheel), one that moves further turns it.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if !isDragging, abs(drag.translation.height) < 4, abs(drag.translation.width) < 4 { return }
                    isDragging = true
                    // Up is more: the numbers follow the pointer up.
                    let rows = (lastDrag - drag.translation.height) / rowHeight
                    lastDrag = drag.translation.height
                    turn { $0.follow(rows) }
                }
                .onEnded { drag in
                    defer {
                        isDragging = false
                        lastDrag = 0
                    }
                    guard isDragging else { return beginEditing() }
                    let fling = (drag.translation.height - drag.predictedEndTranslation.height) / rowHeight
                    settle(adding: max(-12, min(12, fling)))
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(unit.spokenName))
        .accessibilityValue(Text("\(shown)"))
        .accessibilityAdjustableAction { direction in
            module.turn(unit, by: direction == .increment ? 1 : -1)
        }
        .accessibilityAction { beginEditing() }
        .accessibilityHint(Text("Swipe up or down to change. Or press to type."))
    }

    /// The numbers on the drum: the value in the band, two on each side to turn in. Each is drawn at
    /// its place on the drum, smaller, fainter and tipped back the further it is from the band.
    private func drum(shown: Int, typed: String?, isEditing: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(isEditing ? 0.2 : isHovered ? 0.12 : 0.07))
                .frame(width: width, height: faceHeight)
            if isEditing {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
                    .frame(width: width, height: faceHeight)
            }
            ForEach(-2...2, id: \.self) { slot in
                number(slot == 0 ? (typed ?? Self.text(shown)) : Self.text(unit.wrapped(shown + slot)),
                       at: CGFloat(slot) - motion.offset)
            }
        }
        .frame(width: width, height: faceHeight + 2 * neighbourHeight)
        .clipped()
        .accessibilityHidden(true)
    }

    private func number(_ text: String, at position: CGFloat) -> some View {
        let distance = min(abs(position), 2)
        let faceSize: CGFloat = isCompact ? 20 : 24
        let smallScale = (isCompact ? 11 : 13) / faceSize
        let scale = 1 - min(distance, 1) * (1 - smallScale)
        // 1 in the band, 0.3 for a neighbour (as before), gone two rows out.
        let opacity = distance <= 1 ? 1 - 0.7 * distance : 0.3 * (2 - distance)
        return Text(text)
            .font(.system(size: faceSize, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .fixedSize()
            .scaleEffect(scale)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(position) * 32), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .opacity(opacity)
            .offset(y: position * rowHeight)
    }

    private static func text(_ value: Int) -> String {
        String(format: "%02d", value)
    }

    private func beginEditing() {
        motion = WheelMotion()
        module.beginEditing(unit)
    }

    /// Moves the drum and turns the wheel by the steps it passed.
    private func turn(by change: (inout WheelMotion) -> Int) {
        let steps = change(&motion)
        module.turn(unit, by: steps)
    }

    private func settle(adding extra: CGFloat = 0) {
        motion.release(adding: extra)
        finishIfReduced()
    }

    /// Reduce Motion: no coasting, the number lands at once.
    private func finishIfReduced() {
        guard reduceMotion else { return }
        turn { $0.advance(by: .infinity) }
    }
}

/// Turns vertical scrolls over a wheel into drum movement: trackpad scrolls follow the fingers and settle
/// when they stop; a mouse wheel's clicks turn one number each. Takes only scroll events, so clicks and
/// drags still reach the wheel, and sideways swipes still switch modules.
private struct ScrollCatcher: NSViewRepresentable {
    /// Points the fingers moved, up positive.
    let onScroll: (CGFloat) -> Void
    /// The fingers (and the momentum after them) stopped.
    let onRest: () -> Void
    /// Mouse-wheel clicks, up positive.
    let onClick: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        update(view)
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        update(view)
    }

    private func update(_ view: CatcherView) {
        view.onScroll = onScroll
        view.onRest = onRest
        view.onClick = onClick
    }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        var onRest: (() -> Void)?
        var onClick: ((Int) -> Void)?
        private var restTask: Task<Void, Never>?

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else {
                super.scrollWheel(with: event)
                return
            }
            // Follow the fingers whatever the "natural scrolling" setting: fingers up turns the wheel up.
            let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            guard event.hasPreciseScrollingDeltas else {
                if delta != 0 { onClick?(delta > 0 ? 1 : -1) }
                return
            }
            if delta != 0 { onScroll?(delta) }
            // Settles once no scroll (fingers or momentum) has come for a moment: between the fingers
            // lifting and the momentum starting there's no event to say which comes next.
            restTask?.cancel()
            restTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(70))
                guard !Task.isCancelled else { return }
                self?.onRest?()
            }
        }

        override func removeFromSuperview() {
            restTask?.cancel()
            super.removeFromSuperview()
        }
    }
}
