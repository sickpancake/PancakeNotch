import AgentsCore
import SwiftUI

/// What to offer when AI tools are on this Mac: Agents, and AI Usage if a tool with usage is among them.
/// Nil when there's nothing to offer (nothing found, already on, or "Not now" was chosen).
@MainActor
struct AgentsOffer {
    let found: [AgentTool]
    /// The modules a click switches on, in the order they're named.
    let modules: [String]

    init?(found: [AgentTool], settings: AgentsSettings) {
        var modules: [String] = []
        if !settings.agentsEnabled { modules.append("agents") }
        if !settings.usageEnabled, found.contains(where: \.hasUsage) { modules.append("aiUsage") }
        guard !settings.offerDismissed, !found.isEmpty, !modules.isEmpty else { return nil }
        self.found = found
        self.modules = modules
    }
}

/// "We found Claude Code and Codex on this Mac", with one click to switch on Agents and AI Usage.
/// On Home and at the top of Modules.
struct AgentsOfferCard: View {
    let context: AppContext
    let offer: AgentsOffer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let names = offer.found.map(\.name).formatted(.list(type: .and))
        let turnOn = offer.modules.map { AppContext.moduleInfo($0).title }.formatted(.list(type: .and))
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppPalette.primaryText)
                .frame(width: 42, height: 42)
                .background(AppPalette.selection, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("We found \(names) on this Mac")
                        .font(.app(size: 15, weight: .bold))
                    Text(detail)
                        .font(.app(size: 12.5))
                        .foregroundStyle(AppPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: 8) {
                    Button(String(localized: "Turn on \(turnOn)")) {
                        withAnimation(animation) {
                            for moduleID in offer.modules { context.setEnabled(moduleID, true) }
                        }
                    }
                    .buttonStyle(ProminentPillButtonStyle())
                    Button(String(localized: "Not Now")) {
                        withAnimation(animation) { context.agentsSettings.offerDismissed = true }
                    }
                    .accessibilityHint(Text("Hides this. You can still switch them on in Modules."))
                }
                .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.cardInset)
        .padding(.vertical, 16)
        .glassPanel()
    }

    private var detail: String {
        let agents = String(localized: "Agents shows what your AI agents are doing, and lets you answer them from the notch.")
        let usage = String(localized: "AI Usage shows your plan limits and how many tokens you use.")
        return offer.modules.map { $0 == "agents" ? agents : usage }.joined(separator: " ")
    }

    private var animation: Animation {
        .easeInOut(duration: reduceMotion ? 0.15 : 0.25)
    }
}
