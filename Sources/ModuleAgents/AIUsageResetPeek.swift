import AgentsCore
import SwiftUI

/// The same quiet one-line strip as the near-limit warning, with a once-only refill.
struct AIUsageResetPeek: View {
    let notice: LimitResetNotice
    var snapshot = false

    var body: some View {
        let text = AIUsageText.resetPeek(notice)
        HStack(spacing: 7) {
            ResetRing(leftBefore: notice.lowestLeftBefore / 100, snapshot: snapshot)
            ViewThatFits(in: .horizontal) {
                line(subject: text.subject, detail: text.detail, truncates: false)
                line(subject: text.subject, detail: text.detail, truncates: true)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(text.subject), \(text.detail)"))
    }

    private func line(subject: String, detail: String, truncates: Bool) -> some View {
        HStack(spacing: 6) {
            Text(subject)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .truncationMode(.tail)
                .fixedSize(horizontal: !truncates, vertical: false)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                .fixedSize(horizontal: !truncates, vertical: false)
        }
        .lineLimit(1)
    }
}

private struct ResetRing: View {
    let leftBefore: Double
    let snapshot: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    var body: some View {
        ZStack {
            if reduceMotion {
                LimitRing(left: leftBefore, size: 12).opacity(filled ? 0 : 1)
                LimitRing(left: 1, size: 12).opacity(filled || snapshot ? 1 : 0)
            } else {
                RefillRing(left: filled || snapshot ? 1 : leftBefore)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.9).delay(0.25)) {
                filled = true
            }
        }
    }
}

/// Interpolate the gauge and its color together; no repeating animation or display timer.
private struct RefillRing: View, Animatable {
    nonisolated var left: Double
    nonisolated var animatableData: Double {
        get { left }
        set { left = newValue }
    }

    var body: some View {
        let stops: [(Double, (Double, Double, Double))] = [
            (0, (1, 69.0 / 255, 58.0 / 255)),
            (0.1, (1, 159.0 / 255, 10.0 / 255)),
            (0.2, (1, 214.0 / 255, 10.0 / 255)),
            (0.5, (48.0 / 255, 209.0 / 255, 88.0 / 255)),
            (1, (48.0 / 255, 209.0 / 255, 88.0 / 255))
        ]
        let upper = stops.firstIndex { $0.0 > left } ?? stops.count - 1
        let lower = max(0, upper - 1)
        let a = stops[lower], b = stops[upper]
        let t = min(1, max(0, (left - a.0) / max(0.001, b.0 - a.0)))
        let color = Color(red: a.1.0 + (b.1.0 - a.1.0) * t,
                          green: a.1.1 + (b.1.1 - a.1.1) * t,
                          blue: a.1.2 + (b.1.2 - a.1.2) * t)
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 2)
            Circle().trim(from: 0, to: min(1, max(0.02, left)))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
