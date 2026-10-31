import SwiftUI
import TimerCore

/// Which way digits roll: a countdown's new digit comes down from the top, a stopwatch's comes up
/// from below, like a drum turning that way.
enum DrumDirection {
    case down, up
}

/// A time whose digits roll over when they change (ADR-0040): each digit sits on a small horizontal
/// cylinder that turns to the next face (Rolling drum), slides (Simple slide), or just changes (Off).
/// Reduce Motion always cross-fades. Separators (":" ".") stand still.
///
/// Columns are keyed from the right, so "9:59" → "10:00" adds a column on the left without moving the
/// others. The last `steadyDigits` columns change without rolling (a stopwatch's hundredths change
/// faster than any roll could show).
struct DrumText: View {
    let text: String
    let size: CGFloat
    var weight: Font.Weight = .semibold
    let style: TimerDigitAnimation
    var direction: DrumDirection = .down
    var steadyDigits = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let characters = Array(text)
        let columns = characters.enumerated().map { (fromRight: characters.count - 1 - $0.offset, character: $0.element) }
        HStack(spacing: 0) {
            ForEach(columns, id: \.fromRight) { column in
                DrumColumn(
                    character: column.character,
                    depth: size * 0.6,
                    motion: column.fromRight < steadyDigits ? .none : motion,
                    direction: direction
                )
            }
        }
        .font(.system(size: size, weight: weight).monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }

    private var motion: DrumColumn.Motion {
        if reduceMotion { return .fade }
        switch style {
        case .drum: return .drum
        case .slide: return .slide
        case .off: return .none
        }
    }
}

/// One character of a `DrumText`: the old face turns away as the new one turns in.
private struct DrumColumn: View {
    enum Motion { case drum, slide, fade, none }

    let character: Character
    /// How far behind the digit the drum's axis is: about half the digit's height.
    let depth: CGFloat
    let motion: Motion
    let direction: DrumDirection

    var body: some View {
        if motion == .none || !character.isNumber {
            // Changes in place, nothing to animate: a stopwatch's hundredths change 30 times a second.
            // Digits are monospaced, so the width stays put.
            Text(String(character))
        } else {
            ZStack {
                Text(String(character))
                    .id(character)
                    .transition(transition)
            }
            // As wide as a "0", so nothing shifts while two faces overlap.
            .background { Text("0").hidden() }
            .clipped()
            .animation(animation, value: character)
        }
    }

    private var animation: Animation? {
        switch motion {
        // Finite and short: it redraws every frame while it runs, once a second (AGENTS.md rule 2).
        case .drum: .timingCurve(0.2, 0.9, 0.25, 1, duration: 0.3)
        case .slide: .easeOut(duration: 0.22)
        case .fade: .easeInOut(duration: 0.18)
        case .none: nil
        }
    }

    private var transition: AnyTransition {
        // The incoming face starts on the side the drum turns from; the outgoing one leaves the other way.
        let incoming: Double = direction == .down ? -1 : 1
        switch motion {
        case .drum:
            return .asymmetric(
                insertion: .modifier(active: DrumFace(turn: incoming, depth: depth), identity: DrumFace(turn: 0, depth: depth)),
                removal: .modifier(active: DrumFace(turn: -incoming, depth: depth), identity: DrumFace(turn: 0, depth: depth))
            )
        case .slide:
            return .asymmetric(
                insertion: .move(edge: incoming < 0 ? .top : .bottom).combined(with: .opacity),
                removal: .move(edge: incoming < 0 ? .bottom : .top).combined(with: .opacity)
            )
        case .fade:
            return .opacity
        case .none:
            return .identity
        }
    }
}

/// A face on the drum, `turn` quarter turns from the front (-1 above, 1 below). It rotates about an axis
/// `depth` behind the digit, so it moves along the cylinder's curve, fading as it turns edge-on.
private struct DrumFace: ViewModifier {
    let turn: Double
    let depth: CGFloat

    func body(content: Content) -> some View {
        content
            // A positive anchorZ puts the axis behind the digit, so a turning face moves away and
            // shrinks. A negative one swung it toward the viewer, past its column, and clipping cut it up.
            .rotation3DEffect(
                .degrees(turn * 90),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                anchorZ: depth,
                perspective: 0.5
            )
            .opacity(turn == 0 ? 1 : 0)
    }
}
