import AppKit
import NotchCore
import SwiftUI
import TimerCore

/// Hours, minutes and seconds wheels for a custom time, drawn as drums: the value in front, its
/// neighbours turning away above (one less) and below (one more), like a phone's. Scroll or drag one up
/// to turn it up; click it to type (two digits
/// fill it and move on); the arrow keys turn it too. VoiceOver adjusts each with swipe up/down.
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

private struct TimerWheel: View {
    let module: TimerModule
    let unit: TimerWheelUnit
    let isCompact: Bool
    /// Drag distance not yet turned into a step.
    @State private var dragCarry: CGFloat = 0
    @State private var lastDrag: CGFloat = 0
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: CGFloat { isCompact ? 12 : 14 }

    var body: some View {
        let value = unit.value(of: module.wheelSeconds)
        let typed = module.typedValue(for: unit)
        let isEditing = module.editing == unit
        let width: CGFloat = isCompact ? 34 : 42
        let faceHeight: CGFloat = isCompact ? 26 : 32
        VStack(spacing: 0) {
            neighbour(value - 1, turn: -1)
            ZStack {
                if let typed {
                    Text(typed)
                        .font(.system(size: isCompact ? 20 : 24, weight: .semibold).monospacedDigit())
                } else {
                    DrumText(
                        text: String(format: "%02d", value),
                        size: isCompact ? 20 : 24,
                        weight: .semibold,
                        style: module.settings.digitAnimation,
                        direction: module.wheelDirection
                    )
                }
            }
            .frame(width: width, height: faceHeight)
            .background(.white.opacity(isEditing ? 0.2 : isHovered ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if isEditing {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
                }
            }
            neighbour(value + 1, turn: 1)
            Text(unit.label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 1)
        }
        .contentShape(Rectangle())
        // Off-screen snapshots can't draw AppKit views.
        .overlay { if !module.isSnapshot { ScrollCatcher { delta in module.turn(unit, by: delta) } } }
        .onHover { isHovered = $0 }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { drag in
                    dragCarry += lastDrag - drag.translation.height
                    lastDrag = drag.translation.height
                    let steps = Int(dragCarry / step)
                    if steps != 0 {
                        dragCarry -= CGFloat(steps) * step
                        module.turn(unit, by: steps)
                    }
                }
                .onEnded { _ in
                    dragCarry = 0
                    lastDrag = 0
                }
        )
        .simultaneousGesture(TapGesture().onEnded { module.beginEditing(unit) })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(unit.spokenName))
        .accessibilityValue(Text("\(value)"))
        .accessibilityAdjustableAction { direction in
            module.turn(unit, by: direction == .increment ? 1 : -1)
        }
        .accessibilityHint(Text("Swipe up or down to change. Or click and type."))
    }

    /// The faces above and below, tipped back along the drum.
    private func neighbour(_ raw: Int, turn: Double) -> some View {
        let value = (raw % unit.range + unit.range) % unit.range
        return Text(String(format: "%02d", value))
            .font(.system(size: isCompact ? 11 : 13, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.3))
            .rotation3DEffect(.degrees(reduceMotion ? 0 : turn * 40), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .frame(height: isCompact ? 13 : 16)
            .accessibilityHidden(true)
    }
}

/// Turns vertical scrolls (mouse wheel, two fingers) over a wheel into whole steps: up is more. Takes
/// only scroll events, so clicks and drags still reach the wheel, and sideways swipes still switch modules.
private struct ScrollCatcher: NSViewRepresentable {
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onStep = onStep
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onStep = onStep
    }

    final class CatcherView: NSView {
        var onStep: ((Int) -> Void)?
        private var carry: CGFloat = 0

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
            if event.hasPreciseScrollingDeltas {
                carry += delta
                let steps = Int(carry / 12)
                carry -= CGFloat(steps) * 12
                if steps != 0 { onStep?(steps) }
            } else if delta != 0 {
                onStep?(delta > 0 ? 1 : -1)
            }
            if event.phase == .ended || event.momentumPhase == .ended { carry = 0 }
        }
    }
}
