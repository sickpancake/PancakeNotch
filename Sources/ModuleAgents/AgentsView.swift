import AgentsCore
import NotchCore
import SwiftUI

/// The open Agents panel: every thread in a list that scrolls (needs you first, then working, then
/// finished), with a summary or "Clear finished" in the band beside the notch (ADR-0037).
struct AgentsView: View {
    let module: AgentsModule
    let layout: AgentsLayout

    var body: some View {
        let center = module.center
        let threads = center.threads
        VStack(spacing: 0) {
            band(threads, hasFinished: center.hasFinished)
                .frame(height: layout.bandHeight)
                .padding(.horizontal, AgentsLayout.sidePadding)
            if threads.isEmpty {
                PanelNote(symbol: "sparkles", title: "No agents running",
                          detail: "Start Claude Code, Codex or Cursor and they'll show up here.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, AgentsLayout.bottomPadding)
            } else {
                AgentsList(module: module, threads: threads)
            }
        }
        .frame(width: layout.body.width, height: layout.body.height, alignment: .top)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Agents"))
    }

    /// Beside the notch: nothing on the left (the module tabs live there); on the right what's going on,
    /// and "Clear finished" while there is something to clear.
    private func band(_ threads: [AgentThread], hasFinished: Bool) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Color.clear.frame(width: layout.notchWidth)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                bandTrailing(AgentsText.summary(threads, includesFinished: false), hasFinished: hasFinished)
            }
            .frame(width: layout.bandSideWidth)
        }
    }

    @ViewBuilder
    private func bandTrailing(_ summary: String?, hasFinished: Bool) -> some View {
        if hasFinished {
            // The button wins when both don't fit.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    if let summary { AgentsSummary(text: summary) }
                    ClearFinishedButton(center: module.center)
                }
                ClearFinishedButton(center: module.center)
            }
        } else if let summary {
            AgentsSummary(text: summary)
        }
    }
}

private struct AgentsSummary: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
            .fixedSize()
    }
}

/// Only shown while something has finished.
private struct ClearFinishedButton: View {
    let center: AgentsCenter
    @State private var isHovered = false

    var body: some View {
        Button {
            center.clearFinished()
        } label: {
            Text("Clear finished")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovered ? 0.95 : 0.7))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(.white.opacity(isHovered ? 0.12 : 0.06), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text("Remove the finished threads from this list"))
        .accessibilityLabel(Text("Clear finished"))
        .accessibilityHint(Text("Removes the finished threads from the list."))
    }
}

// MARK: List

private struct AgentsList: View {
    let module: AgentsModule
    let threads: [AgentThread]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PanelScroll(isSnapshot: module.isSnapshot, bottomMargin: AgentsLayout.bottomPadding) {
            VStack(spacing: 0) {
                ForEach(threads) { thread in
                    AgentRow(module: module, thread: thread)
                        .transition(.opacity)
                    if module.openSubagents.contains(thread.id) {
                        ForEach(thread.subagents) { subagent in
                            SubagentRow(subagent: subagent)
                                .transition(.opacity)
                        }
                    }
                }
            }
            // The rows' highlight reaches 10 pt past their content, so the content lines up with the band.
            .padding(.horizontal, AgentsLayout.sidePadding - AgentRow.inset)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: shownIDs)
        }
    }

    /// Threads and the subagents shown under them, for animating rows in and out.
    private var shownIDs: [String] {
        threads.flatMap { thread in
            [thread.id] + (module.openSubagents.contains(thread.id) ? thread.subagents.map(\.id) : [])
        }
    }
}

/// One thread: its status mark, tool and title, what it's doing, and on the right how long (or, when it
/// asks and can be answered here, Open / Deny / Allow). It opens the thread's app only if it can.
private struct AgentRow: View {
    static let inset: CGFloat = 10

    let module: AgentsModule
    let thread: AgentThread
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            AgentMark(status: thread.status, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Image(systemName: thread.tool.symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(thread.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(AgentsText.subtitle(thread))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !thread.subagents.isEmpty {
                SubagentsToggle(module: module, thread: thread, isOpen: module.openSubagents.contains(thread.id))
            }
            if thread.canAnswer {
                AnswerButtons(module: module, thread: thread)
            } else {
                // The time moves on once a minute while this is on screen.
                TimelineView(.everyMinute) { context in
                    Text(AgentsText.statusLine(thread.status, since: thread.statusSince, now: context.date))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(thread.status.needsYou ? 0.9 : 0.6))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, Self.inset)
        .frame(height: 40)
        .background(.white.opacity(isHovered && thread.canOpen ? 0.08 : 0), in: .rect(cornerRadius: 9, style: .continuous))
        .contentShape(.rect(cornerRadius: 9, style: .continuous))
        .onHover { isHovered = $0 }
        .modifier(OpensOnClick(canOpen: thread.canOpen, hasOpenButton: thread.canAnswer) { module.open(thread) })
        .accessibilityElement(children: thread.canAnswer || !thread.subagents.isEmpty ? .contain : .combine)
        .accessibilityLabel(Text(AgentsText.spoken(thread, now: .now)))
    }
}

/// "2 subagents ⌄": shows or hides the thread's working helpers under it. Just the number beside the
/// answer buttons, where room is short.
private struct SubagentsToggle: View {
    let module: AgentsModule
    let thread: AgentThread
    let isOpen: Bool
    @State private var isHovered = false

    var body: some View {
        let count = thread.subagents.count
        Button {
            module.toggleSubagents(of: thread)
        } label: {
            HStack(spacing: 4) {
                Text(thread.canAnswer ? "\(count)" : AgentsText.subagents(count))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .foregroundStyle(.white.opacity(isHovered ? 0.95 : 0.7))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(.white.opacity(isHovered || isOpen ? 0.12 : 0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text(isOpen ? "Hide this thread's subagents" : "Show this thread's subagents"))
        .accessibilityLabel(Text(AgentsText.subagents(count)))
        .accessibilityValue(Text(isOpen ? "Shown" : "Hidden"))
        .accessibilityHint(Text(isOpen ? "Hides them from the list." : "Shows them under this thread."))
    }
}

/// A helper under its thread, lined up with the thread's title: its mark, what it's doing and for how long.
private struct SubagentRow: View {
    let subagent: AgentSubagent

    var body: some View {
        HStack(spacing: 8) {
            AgentMark(status: subagent.status, size: 14)
            Text(subagent.title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            TimelineView(.everyMinute) { context in
                Text(AgentsText.statusLine(subagent.status, since: subagent.statusSince, now: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        // Under the thread's title: past its 22 pt mark and the 10 pt gap.
        .padding(.leading, AgentRow.inset + 32)
        .padding(.trailing, AgentRow.inset)
        .frame(height: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AgentsText.spoken(subagent, now: .now)))
    }
}

/// A click anywhere on the row opens the thread's app (the buttons on it keep their own clicks). VoiceOver
/// gets the same as the row's action, unless the row has its own Open button.
private struct OpensOnClick: ViewModifier {
    let canOpen: Bool
    let hasOpenButton: Bool
    let open: () -> Void

    func body(content: Content) -> some View {
        if canOpen, hasOpenButton {
            content.onTapGesture(perform: open)
        } else if canOpen {
            content
                .onTapGesture(perform: open)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default, open)
        } else {
            content
        }
    }
}

/// Open (when its app is known), Deny and Allow, for a request that can be answered here. Allow means once.
private struct AnswerButtons: View {
    let module: AgentsModule
    let thread: AgentThread

    var body: some View {
        HStack(spacing: 6) {
            if thread.canOpen {
                AnswerButton(title: String(localized: "Open"), label: String(localized: "Open \(thread.tool.name)"),
                             help: String(localized: "Go to this thread and answer there")) {
                    module.open(thread)
                }
            }
            AnswerButton(title: String(localized: "Deny"), label: String(localized: "Deny"),
                         help: String(localized: "Say no to this request")) {
                module.center.deny(thread.id)
            }
            AnswerButton(title: String(localized: "Allow"), label: String(localized: "Allow once"),
                         help: String(localized: "Say yes to this request, this once"), prominent: true) {
                module.center.allow(thread.id)
            }
        }
    }
}

/// A capsule button: outlined, or white with black text for the main answer.
private struct AnswerButton: View {
    let title: String
    let label: String
    let help: String
    var prominent = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(prominent ? .black : .white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(prominent ? .white.opacity(isHovered ? 0.88 : 1) : .white.opacity(isHovered ? 0.12 : 0), in: Capsule())
                .overlay {
                    if !prominent { Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text(help))
        .accessibilityLabel(Text(label))
    }
}
