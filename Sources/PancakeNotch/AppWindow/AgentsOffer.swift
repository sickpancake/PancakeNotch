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

/// "We found Devin on this Mac" (issue #78): Devin shows up in Agents only after Connect, so this offers it
/// in one click, turning Agents on too when it's off. After Connect it says what to do next, until Done or
/// the page is left. On Home and at the top of Modules, under the Agents offer's place: while that offer
/// shows, it speaks for Devin too, and this card follows once Agents is on.
struct ConnectReminderCard: View {
    let context: AppContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether there's anything to show.
    static func shows(_ reminder: ConnectReminder) -> Bool {
        reminder.tool != nil || reminder.justConnected != nil
    }

    private var reminder: ConnectReminder { context.connectReminder }

    var body: some View {
        let connected = reminder.tool == nil ? reminder.justConnected : nil
        let tool = reminder.tool ?? connected ?? .devin
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: connected == nil ? tool.symbol : "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(connected == nil ? AppPalette.primaryText : Color.black)
                .frame(width: 42, height: 42)
                .background(connected == nil ? AppPalette.selection : Color.white, in: .rect(cornerRadius: 11, style: .continuous))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(connected == nil
                        ? String(localized: "We found \(tool.name) on this Mac", comment: "Connect reminder card, e.g. We found Devin on this Mac")
                        : String(localized: "\(tool.name) is connected", comment: "Connect reminder card after Connect"))
                        .font(.app(size: 15, weight: .bold))
                    Text(detail(tool, connected: connected != nil))
                        .font(.app(size: 12.5))
                        .foregroundStyle(AppPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if connected == nil, let problem = reminder.problem {
                        Label(problem, systemImage: "exclamationmark.circle")
                            .font(.app(size: 12.5, weight: .medium))
                            .foregroundStyle(AppPalette.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                            .transition(.opacity)
                    }
                }
                .id(connected == nil)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                HStack(spacing: 8) {
                    if connected == nil {
                        Button(agentsOn
                            ? String(localized: "Connect \(tool.name)", comment: "Connect reminder card button, e.g. Connect Devin")
                            : String(localized: "Turn On Agents and Connect", comment: "Connect reminder card button while Agents is off")) {
                            withAnimation(animation) {
                                if !agentsOn { context.setEnabled("agents", true) }
                                reminder.connect()
                            }
                        }
                        .buttonStyle(ProminentPillButtonStyle())
                        .accessibilityHint(Text("Adds PancakeNotch's hooks to \(tool.name)'s settings so its sessions show in the notch."))
                        Button(String(localized: "Not Now")) {
                            withAnimation(animation) { reminder.notNow() }
                        }
                        .accessibilityHint(Text("Stops reminding you. You can still connect \(tool.name) under Modules, in Agents' settings."))
                    } else {
                        Button(String(localized: "Done")) {
                            withAnimation(animation) { reminder.finish() }
                        }
                    }
                }
                .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.cardInset)
        .padding(.vertical, 16)
        .glassPanel()
        .animation(animation, value: connected == nil)
        .animation(animation, value: reminder.problem)
        // The "connected" note is read here, or not at all: it doesn't wait for the next visit.
        .onDisappear { reminder.finish() }
    }

    private var agentsOn: Bool { context.agentsSettings.agentsEnabled }

    private func detail(_ tool: AgentTool, connected: Bool) -> String {
        if connected {
            return String(localized: "Start a new \(tool.name) session and it shows up in the notch. \(tool.name) skips hooks in a workspace opened in Restricted Mode.")
        }
        return agentsOn
            ? String(localized: "Connect it to see its sessions beside the notch and answer its questions from there. Disconnect in Agents' settings takes it out again.")
            : String(localized: "Turn on Agents and connect \(tool.name) to see its sessions beside the notch and answer its questions from there.")
    }

    private var animation: Animation {
        .easeInOut(duration: reduceMotion ? 0.15 : 0.25)
    }
}
