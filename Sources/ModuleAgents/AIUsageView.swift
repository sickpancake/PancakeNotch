import AgentsCore
import NotchCore
import SwiftUI

/// The open AI Usage panel: the account pill in the band beside the notch, the limits on the left and
/// the range with its totals on the right (ADR-0037). The account menu opens over the right side.
struct AIUsageView: View {
    static let columnGap: CGFloat = 24

    let module: AIUsageModule
    let layout: AgentsLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let center = module.center
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                band(center)
                    .frame(height: layout.bandHeight)
                    .padding(.horizontal, AgentsLayout.sidePadding)
                if center.accounts.isEmpty {
                    PanelNote(symbol: module.symbol, title: "No Claude Code or Codex accounts found",
                              detail: "They show up here once you've used one on this Mac.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, AgentsLayout.bottomPadding)
                } else {
                    columns(center)
                }
            }
            if module.isMenuOpen {
                AccountMenuOverlay(module: module, layout: layout)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: module.isMenuOpen)
        .frame(width: layout.body.width, height: layout.body.height, alignment: .top)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("AI Usage"))
    }

    /// Beside the notch: nothing on the left (the module tabs live there); on the right the account.
    private func band(_ center: UsageCenter) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Color.clear.frame(width: layout.notchWidth)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if !center.accounts.isEmpty { AccountPill(module: module) }
            }
            .frame(width: layout.bandSideWidth)
        }
    }

    private func columns(_ center: UsageCenter) -> some View {
        let limitsWidth = ((layout.body.width - 2 * AgentsLayout.sidePadding - Self.columnGap) * 0.45).rounded()
        return HStack(alignment: .top, spacing: Self.columnGap) {
            AIUsageLimits(module: module)
                .frame(width: limitsWidth, alignment: .topLeading)
            AIUsageTotals(center: center)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, AgentsLayout.sidePadding)
        .padding(.top, 4)
        .padding(.bottom, AgentsLayout.bottomPadding)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
