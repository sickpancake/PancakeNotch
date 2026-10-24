import AgentsCore
import SwiftUI

/// The right column: the range switch, then the tokens, what they're worth and the top models.
struct AIUsageTotals: View {
    let center: UsageCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RangeSwitch(center: center)
                .padding(.bottom, 2)
            if let progress = center.firstReadProgress {
                Text("Reading your history… \(Int(progress * 100))%")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 6)
            } else {
                numbers(center.totals)
            }
        }
    }

    @ViewBuilder
    private func numbers(_ totals: UsageTotals) -> some View {
        Text("\(AIUsageText.tokens(totals.tokens)) tokens")
            .font(.system(size: 22, weight: .semibold))
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: totals.tokens)
        Text(AIUsageText.money(totals.cost, label: center.moneyLabel, paysPerToken: center.paysPerToken))
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
        VStack(alignment: .leading, spacing: 1) {
            ForEach(totals.models.prefix(3)) { model in
                Text(AIUsageText.share(model, of: totals.tokens))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(.top, 2)
        if totals.unpricedTokens > 0 {
            Text("Some models have no known price")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
    }
}

/// Today · 7 days · 30 days.
private struct RangeSwitch: View {
    let center: UsageCenter

    var body: some View {
        HStack(spacing: 2) {
            ForEach(UsageRange.allCases) { range in
                RangeSegment(range: range, isSelected: center.range == range) { center.choose(range) }
            }
        }
        .padding(2)
        .background(.white.opacity(0.08), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Range"))
    }
}

private struct RangeSegment: View {
    let range: UsageRange
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(range.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(isSelected ? 1 : isHovered ? 0.85 : 0.6))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 20)
                .background(.white.opacity(isSelected ? 0.18 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
