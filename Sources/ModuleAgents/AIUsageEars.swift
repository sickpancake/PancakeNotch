import AgentsCore
import SwiftUI

/// A still ring that shows how much of a limit is left, colored by it (nothing moves).
struct LimitRing: View {
    /// 0…1.
    let left: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, left)))
                .stroke(StatusColors.color(left: left * 100), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The compact ear: a ring and the percent left of the followed limit (Settings).
struct AIUsageEar: View {
    let module: AIUsageModule

    var body: some View {
        if let near = module.center.earReading {
            let left = near.limit.leftPercent()
            HStack(spacing: 2) {
                LimitRing(left: left / 100, size: 10)
                Text("\(AIUsageText.percent(left))%")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(AIUsageText.spoken(near, now: .now)))
        } else {
            // The short shrink after a click while there's nothing to show.
            Image(systemName: module.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
        }
    }
}

/// The strip under the compact notch when an account runs low: who, which limit (when there's room),
/// how much is left and when it resets.
struct AIUsagePeek: View {
    let near: NearLimit

    var body: some View {
        let text = AIUsageText.peek(near, now: .now)
        ViewThatFits(in: .horizontal) {
            strip(subject: text.subject, detail: "\(near.limit.label) · \(text.detail)")
            // Short of room: no limit name, and a long name gives way.
            strip(subject: text.subject, detail: text.detail, subjectTruncates: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(text.subject), \(near.limit.label): \(text.detail)"))
    }

    private func strip(subject: String, detail: String, subjectTruncates: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: near.account.tool.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(subject)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .truncationMode(.tail)
                .fixedSize(horizontal: !subjectTruncates, vertical: false)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize()
                .layoutPriority(1)
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
    }
}
