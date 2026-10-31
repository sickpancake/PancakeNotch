import SwiftUI
import TimerCore

/// Which way digits roll: a countdown's new digit comes down from the top, a stopwatch's comes up
/// from below.
enum DrumDirection {
    case down, up
}

/// A time whose digits roll when they change (ADR-0040), drawn as one text in the notch's own font (SF
/// Pro with even-width digits), so spacing, kerning and size match the rest of PancakeNotch. Roll uses
/// SwiftUI's numeric text transition (each changed digit rolls in the direction the time moves), Fade
/// cross-fades, Just change changes in place. Reduce Motion turns Roll into Fade.
///
/// The last `steadyDigits` characters change without animating (a stopwatch's hundredths change faster
/// than any roll could show): only a change in the rest of the text animates.
struct DrumText: View {
    let text: String
    let size: CGFloat
    var weight: Font.Weight = .semibold
    let style: TimerDigitAnimation
    var direction: DrumDirection = .down
    var steadyDigits = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: size, weight: weight).monospacedDigit())
            .contentTransition(transition)
            // Finite and short: it redraws only while it runs, once a second (AGENTS.md rule 2).
            .animation(animation, value: String(text.dropLast(steadyDigits)))
            .accessibilityLabel(Text(verbatim: text))
    }

    private var rolls: Bool { style == .drum && !reduceMotion }

    private var transition: ContentTransition {
        switch style {
        case .off: .identity
        case .drum where !reduceMotion: .numericText(countsDown: direction == .down)
        default: .opacity
        }
    }

    private var animation: Animation? {
        switch style {
        case .off: nil
        default: rolls ? .snappy(duration: 0.3) : .easeInOut(duration: 0.18)
        }
    }
}
