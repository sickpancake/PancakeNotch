import AppKit
import SwiftUI
import TimerCore

/// Which way digits roll: a countdown's new digit comes down from the top, a stopwatch's comes up
/// from below.
enum DrumDirection {
    case down, up
}

/// Which characters of a time roll when it changes: the ones that differ, in the part that isn't steady.
/// Nothing rolls when the text changes length (10:00 → 9:59): every character would differ then, so it
/// just changes.
struct DrumRoll: Equatable {
    /// Positions (from the left) of the characters that change.
    let changed: [Int]

    init?(from old: String, to new: String, steadyDigits: Int) {
        let before = Array(old), after = Array(new)
        guard before.count == after.count, !after.isEmpty else { return nil }
        let rolling = max(0, after.count - steadyDigits)
        let differing = (0..<rolling).filter { before[$0] != after[$0] }
        guard !differing.isEmpty else { return nil }
        changed = differing
    }
}

/// Where each character of a time sits, measured with the same font the text is drawn in (SF Pro with
/// even-width digits), so a rolling digit has a window exactly as wide as its slot.
enum DrumMetrics {
    static func nsFont(size: CGFloat, weight: Font.Weight) -> NSFont {
        let nsWeight: NSFont.Weight = switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .semibold
        }
        return .monospacedDigitSystemFont(ofSize: size, weight: nsWeight)
    }

    /// The left edge of each character, then the right edge of the last: `text.count + 1` numbers.
    static func edges(of text: String, size: CGFloat, weight: Font.Weight) -> [CGFloat] {
        let font = nsFont(size: size, weight: weight)
        var edges: [CGFloat] = [0]
        var prefix = ""
        for character in text {
            prefix.append(character)
            edges.append(NSAttributedString(string: prefix, attributes: [.font: font]).size().width)
        }
        return edges
    }

    static func width(of text: String, size: CGFloat, weight: Font.Weight) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: nsFont(size: size, weight: weight)]).size().width
    }
}

/// A time whose digits roll when they change (ADR-0040), drawn as one text in the notch's own font (SF
/// Pro with even-width digits), so spacing, kerning and size match the rest of PancakeNotch.
///
/// Roll: only the characters that change roll, each in its own window (the old one leaves as the new one
/// arrives, all on the same short curve), and the rest of the text stays exactly where it is. The layers
/// are the same single text drawn again, so nothing is re-spaced. Fade cross-fades the text, Just change
/// changes in place. Reduce Motion turns Roll into Fade.
///
/// The last `steadyDigits` characters change without animating (a stopwatch's hundredths change faster
/// than any roll could show): only a change in the rest of the text animates.
///
/// While nothing changes it's one plain text and nothing redraws. A roll redraws every frame for its
/// third of a second and then stops (AGENTS.md rule 2).
struct DrumText: View {
    let text: String
    let size: CGFloat
    var weight: Font.Weight = .semibold
    let style: TimerDigitAnimation
    var direction: DrumDirection = .down
    var steadyDigits = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tracker = DrumTracker()
    /// Counts finished rolls, so the view redraws once more when one ends and goes back to plain text.
    @State private var settled = 0

    static let duration: TimeInterval = 0.3

    var body: some View {
        let _ = settled
        Group {
            switch style {
            case .off:
                plain
            case .slide:
                fade
            case .drum where reduceMotion:
                fade
            case .drum:
                rolling
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }

    private var font: Font { .system(size: size, weight: weight).monospacedDigit() }

    private var plain: some View {
        Text(verbatim: text).font(font).fixedSize()
    }

    /// Cross-fades when the changing part of the text changes. Finite and short (AGENTS.md rule 2).
    private var fade: some View {
        plain
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.18), value: String(text.dropLast(steadyDigits)))
    }

    @ViewBuilder
    private var rolling: some View {
        let roll = tracker.observe(text, steadyDigits: steadyDigits, size: size, weight: weight, now: Date())
        let active = roll != nil && Date().timeIntervalSince(tracker.startedAt) < Self.duration
        TimelineView(.animation(paused: !active)) { context in
            if let roll, active {
                let progress = min(1, max(0, context.date.timeIntervalSince(tracker.startedAt) / Self.duration))
                DrumRollLayers(
                    text: text,
                    from: tracker.oldText(steadyDigits: steadyDigits, now: text),
                    roll: roll,
                    edges: tracker.edges,
                    progress: progress,
                    size: size,
                    weight: weight,
                    direction: direction
                )
            } else {
                plain
            }
        }
        .task(id: tracker.generation) {
            guard roll != nil else { return }
            try? await Task.sleep(for: .seconds(Self.duration + 0.04))
            if !Task.isCancelled { settled += 1 }
        }
    }
}

/// What a `DrumText` remembers between redraws: the text it last drew and the roll that came with the last
/// change. A plain object, changed while the view is drawn but never read by anything that watches it.
@MainActor
final class DrumTracker {
    private var shown: String?
    private var oldLead: [Character] = []
    private(set) var roll: DrumRoll?
    private(set) var edges: [CGFloat] = []
    private(set) var startedAt = Date.distantPast
    /// Goes up with each new roll.
    private(set) var generation = 0

    /// Notes what's being drawn now. Returns the roll to show, if one is under way.
    func observe(_ text: String, steadyDigits: Int, size: CGFloat, weight: Font.Weight, now: Date) -> DrumRoll? {
        guard let previous = shown else {
            shown = text
            return nil
        }
        guard previous != text else { return roll }
        shown = text
        if let next = DrumRoll(from: previous, to: text, steadyDigits: steadyDigits) {
            roll = next
            oldLead = Array(previous.prefix(max(0, previous.count - steadyDigits)))
            edges = DrumMetrics.edges(of: text, size: size, weight: weight)
            startedAt = now
            generation += 1
        } else if previous.count != text.count {
            // A different length: nothing lines up, so no roll.
            roll = nil
        }
        // Otherwise only the steady digits changed: a roll under way carries on.
        return roll
    }

    /// What the rolling characters were: the old leading part with today's steady tail.
    func oldText(steadyDigits: Int, now text: String) -> String {
        String(oldLead) + String(text.suffix(steadyDigits))
    }
}

/// One frame of a roll: the unchanged characters stay, and each changed one has its old face leaving and
/// its new face arriving, in a window as wide as its slot. `progress` is 0 (all old) to 1 (all new).
struct DrumRollLayers: View {
    let text: String
    let from: String
    let roll: DrumRoll
    /// The left edge of each character of `text`, then the last one's right edge.
    let edges: [CGFloat]
    let progress: Double
    let size: CGFloat
    let weight: Font.Weight
    let direction: DrumDirection

    var body: some View {
        // Starts fast and settles. The old face is gone before the new one is clear, so two faces are never
        // both solid.
        let eased = 1 - pow(1 - progress, 3)
        let travel = size * 0.45 * (direction == .down ? 1 : -1)
        ZStack(alignment: .topLeading) {
            glyphs(text).mask { window(for: unchanged) }
            ForEach(roll.changed, id: \.self) { index in
                glyphs(from)
                    .mask { window(for: [index]) }
                    .offset(y: travel * eased)
                    .opacity(max(0, 1 - eased * 2.6))
                glyphs(text)
                    .mask { window(for: [index]) }
                    .offset(y: -travel * (1 - eased))
                    .opacity(min(1, max(0, (eased - 0.3) * 2.6)))
            }
        }
    }

    private var unchanged: [Int] {
        (0..<max(0, edges.count - 1)).filter { !roll.changed.contains($0) }
    }

    private func glyphs(_ string: String) -> some View {
        Text(verbatim: string)
            .font(.system(size: size, weight: weight).monospacedDigit())
            .fixedSize()
    }

    /// Opens a window over these slots only, tall enough that a digit moving through never meets an edge.
    private func window(for slots: [Int]) -> some View {
        Path { path in
            for slot in slots where slot + 1 < edges.count {
                let left = edges[slot] - 0.5, right = edges[slot + 1] + 0.5
                path.addRect(CGRect(x: left, y: -size * 2, width: right - left, height: size * 6))
            }
        }
        .fill(.white)
    }
}
