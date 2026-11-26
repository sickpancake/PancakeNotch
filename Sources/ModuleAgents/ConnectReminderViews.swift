import AgentsCore
import NotchCore
import SwiftUI

/// The strip under the compact notch when Devin turns up unconnected (issue #78). Shown once; clicking it
/// opens Agents, where the Connect row waits.
struct ConnectReminderPeek: View {
    let tool: AgentTool

    var body: some View {
        let text = ConnectReminderText.peek(tool)
        ViewThatFits(in: .horizontal) {
            line(text.title, text.detail)
            line(text.title, nil)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(text.title). \(text.detail)"))
    }

    private func line(_ title: String, _ detail: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: tool.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// At the top of the open Agents panel while Devin is on this Mac but not connected: what's missing, with
/// Not Now and Connect. After Connect it says what to do next, until Done or the notch closes.
struct ConnectReminderRow: View {
    let reminder: ConnectReminder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let state {
            HStack(spacing: 10) {
                Image(systemName: state.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(state.isDone ? 1 : 0.75))
                    .frame(width: 22, height: 22)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(state.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .truncationMode(.tail)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(Text(state.detail))
                .accessibilityElement(children: .combine)
                .id(state.isDone)
                .transition(.opacity)
                HStack(spacing: 8) {
                    if let tool = state.tool {
                        NotchPill(title: String(localized: "Not Now", comment: "Connect reminder: no more reminders for this tool")) {
                            withAnimation(animation) { reminder.notNow() }
                        }
                        .help(Text("Stop reminding. You can still connect \(tool.name) in Agents' settings."))
                        .accessibilityHint(Text("Stops reminding you. You can still connect \(tool.name) in Agents' settings."))
                        NotchPill(title: String(localized: "Connect", comment: "Connect reminder button"), prominent: true) {
                            withAnimation(animation) { _ = reminder.connect() }
                        }
                        .accessibilityLabel(Text("Connect \(tool.name)"))
                        .accessibilityHint(Text("Adds PancakeNotch's hooks to \(tool.name)'s settings so its sessions show here."))
                    } else {
                        NotchPill(title: String(localized: "Done", comment: "Connect reminder: the connected note was read"), prominent: true) {
                            withAnimation(animation) { reminder.finish() }
                        }
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 9, style: .continuous))
            .animation(animation, value: state.isDone)
            .accessibilityElement(children: .contain)
        }
    }

    /// What the row says: a tool to connect, or the one just connected.
    private var state: ConnectReminderText.Row? {
        if let tool = reminder.tool { return ConnectReminderText.toConnect(tool, problem: reminder.problem) }
        if let tool = reminder.justConnected { return ConnectReminderText.connected(tool) }
        return nil
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.25)
    }
}

/// The reminder's words, in the notch.
enum ConnectReminderText {
    struct Row {
        /// The tool still to connect; nil once it's connected.
        let tool: AgentTool?
        let symbol: String
        let title: String
        let detail: String
        var isDone: Bool { tool == nil }
    }

    static func peek(_ tool: AgentTool) -> (title: String, detail: String) {
        (String(localized: "\(tool.name) is on this Mac", comment: "Connect reminder strip, e.g. Devin is on this Mac"),
         String(localized: "Click to connect it", comment: "Connect reminder strip: clicking opens Agents to connect"))
    }

    static func toConnect(_ tool: AgentTool, problem: String?) -> Row {
        Row(tool: tool, symbol: tool.symbol,
            title: String(localized: "\(tool.name) is on this Mac", comment: "Connect reminder, e.g. Devin is on this Mac"),
            detail: problem ?? String(localized: "Connect it to see its sessions here."))
    }

    static func connected(_ tool: AgentTool) -> Row {
        Row(tool: nil, symbol: "checkmark",
            title: String(localized: "\(tool.name) is connected", comment: "Connect reminder after Connect, e.g. Devin is connected"),
            detail: String(localized: "Start a new \(tool.name) session and it shows up here."))
    }
}
