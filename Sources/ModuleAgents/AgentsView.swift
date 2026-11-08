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
            if let (thread, change) = reviewed(threads) {
                AgentsReviewScreen(module: module, thread: thread, change: change)
                    .padding(.horizontal, AgentsLayout.sidePadding)
                    .padding(.bottom, AgentsLayout.bottomPadding)
            } else if threads.isEmpty {
                PanelNote(symbol: "sparkles", title: "No agents running",
                          detail: "Start Claude Code or Codex and they'll show up here. Cursor too, after Connect.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, AgentsLayout.bottomPadding)
            } else {
                AgentsList(module: module, threads: threads)
            }
        }
        // The request on the review screen was answered, handed back or replaced: back to the list.
        .onChange(of: reviewed(threads) == nil) { _, gone in
            if gone { module.closeReview() }
        }
        // Here rather than in the list, which the "No agents" note replaces when the last thread goes.
        .onChange(of: rowSpots(threads)) { old, new in module.rowsMoved(from: old, to: new) }
        .frame(width: layout.body.width, height: layout.body.height, alignment: .top)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Agents"))
    }

    /// Every row the list shows, top to bottom, with what makes it taller.
    private func rowSpots(_ threads: [AgentThread]) -> [AgentsModule.RowSpot] {
        threads.flatMap { thread in
            [AgentsModule.RowSpot(id: thread.id, extraLines: AgentsText.rowLines(thread.approval?.review).count)]
                + (module.openSubagents.contains(thread.id) ? thread.subagents.map { AgentsModule.RowSpot(id: $0.id) } : [])
        }
    }

    /// The thread and change on the review screen, while that very request still waits.
    private func reviewed(_ threads: [AgentThread]) -> (AgentThread, AgentReview.FileChange)? {
        guard let reviewing = module.reviewing, let thread = threads.first(where: { $0.id == reviewing.threadID }),
              thread.approval == reviewing.approval, case .edit(let change) = reviewing.approval.review.content else { return nil }
        return (thread, change)
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
    static let space = "AgentsList"

    let module: AgentsModule
    let threads: [AgentThread]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The list's visible height, and where the opened row ends in it.
    @State private var visibleHeight: CGFloat = 0
    @State private var previewedBottom: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            list
                .coordinateSpace(.named(Self.space))
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { visibleHeight = $0 }
                // An opened row that runs past the bottom scrolls up just enough to show it all; the pointer
                // stays on it (the row grew downward by at least that much).
                .task(id: module.previewed) {
                    guard let id = module.previewed, !module.isSnapshot else { return }
                    try? await Task.sleep(for: .milliseconds(reduceMotion ? 20 : 220))
                    guard !Task.isCancelled, module.previewed == id,
                          previewedBottom > visibleHeight - AgentsLayout.bottomPadding + 0.5 else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                }
        }
    }

    private var list: some View {
        PanelScroll(isSnapshot: module.isSnapshot, bottomMargin: AgentsLayout.bottomPadding) {
            VStack(spacing: 0) {
                ForEach(threads) { thread in
                    AgentRow(module: module, thread: thread) { previewedBottom = $0 }
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
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: module.previewed)
        }
        // Scrolled by the user (not by the reveal above, which keeps the pointer on the opened row).
        .onScrollPhaseChange { _, phase in
            if phase == .tracking || phase == .interacting || phase == .decelerating { module.listScrolled() }
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
/// asks and can be answered here, Open / Deny / Allow). It opens the thread's app only if it can. When
/// the pointer rests on it, it opens a little downward: the whole title, the whole of what it's doing,
/// and the app it runs in.
private struct AgentRow: View {
    static let inset: CGFloat = 10

    let module: AgentsModule
    let thread: AgentThread
    /// Where the row ends in the list, told only while it's opened.
    let previewedBottom: (CGFloat) -> Void
    @State private var isHovered = false

    var body: some View {
        let lines = AgentsText.rowLines(thread.approval?.review)
        VStack(alignment: .leading, spacing: 0) {
            summary
            // A command or a file to read, whole, under the title: Allow approves exactly this.
            if !lines.isEmpty {
                RequestLines(lines: lines)
                    .padding(.leading, 32)
                    .padding(.bottom, 9)
            }
        }
        .padding(.horizontal, Self.inset)
        .background(.white.opacity(isHovered && thread.canOpen ? 0.08 : 0), in: .rect(cornerRadius: 9, style: .continuous))
        .contentShape(.rect(cornerRadius: 9, style: .continuous))
        .onHover { inside in
            isHovered = inside
            module.hoverChanged(thread.id, isInside: inside)
        }
        .modifier(ReportsBottom(isOn: isPreviewed, report: previewedBottom))
        .modifier(OpensOnClick(canOpen: thread.canOpen, hasOpenButton: thread.canAnswer) { module.open(thread) })
        .accessibilityElement(children: thread.canAnswer || !thread.subagents.isEmpty ? .contain : .combine)
        .accessibilityLabel(Text(AgentsText.spoken(thread, now: .now)))
    }

    private var isPreviewed: Bool { module.previewed == thread.id }

    /// The mark, the words and what's on the right, each in the first 40 pt; an open row's words carry on
    /// below, so nothing else moves.
    private var summary: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentMark(status: thread.status, size: 22)
                .frame(height: 40)
            words
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .frame(height: 40)
        }
    }

    /// Title and what it's doing, on one line each. Opened, the whole of both and the app it runs in,
    /// starting where the one-line words start (the one-line copy, hidden, holds that place).
    private var words: some View {
        ZStack(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
            lines(lineLimit: 1)
                .frame(height: 40)
                .opacity(isPreviewed ? 0 : 1)
            if isPreviewed {
                VStack(alignment: .leading, spacing: 1) {
                    lines(lineLimit: Self.previewLineLimit)
                    Text(AgentsText.harness(thread))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 2)
                }
                .padding(.bottom, 9)
                .transition(.opacity)
                // VoiceOver reads all of this in the row's label already.
                .accessibilityHidden(true)
            }
        }
    }

    /// The most lines an opened title or step takes, so a very long one can't fill the list.
    private static let previewLineLimit = 4

    private func lines(lineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: thread.tool.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    // One column for every tool's mark, so the titles line up.
                    .frame(width: 18, alignment: .leading)
                Text(thread.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(lineLimit)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(AgentsText.subtitle(thread))
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trailing: some View {
        HStack(spacing: 10) {
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
    }
}

/// A command or a file's place, line for line as cut to fit (`AgentReview.columns`), in a fixed-width
/// font so nothing can pass for something else. Read out as part of the row.
struct RequestLines: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityHidden(true)
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

/// Tells where the view ends in the list, while `isOn`: only the opened row is followed. One shape
/// either way, so the row keeps its state (hover, Allow's wait) when it opens.
private struct ReportsBottom: ViewModifier {
    let isOn: Bool
    let report: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat?.self, of: { isOn ? $0.frame(in: .named(AgentsList.space)).maxY : nil }) { bottom in
            if let bottom { report(bottom) }
        }
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
/// A change shows Review instead: Allow is on the review screen, under the whole change. Allow wakes up
/// half a second after its request appears, so a click meant for something else can't land on it.
struct AnswerButtons: View {
    let module: AgentsModule
    let thread: AgentThread
    /// On the review screen: no Review, Allow instead.
    var inReview = false
    /// False when the review screen can't show the whole change: Open and Deny only.
    var allowsAllow = true
    @State private var armed: PendingApproval?

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
                module.center.deny(thread)
            }
            if case .edit? = thread.approval?.review.content, !inReview {
                AnswerButton(title: String(localized: "Review"), label: String(localized: "Review the change"),
                             help: String(localized: "See the whole change, then Allow or Deny it"), prominent: true) {
                    module.review(thread)
                }
            } else if allowsAllow {
                AnswerButton(title: String(localized: "Allow"), label: String(localized: "Allow once"),
                             help: String(localized: "Say yes to this request, this once"), prominent: true,
                             isEnabled: module.isSnapshot || (armed != nil && armed == thread.approval)) {
                    module.center.allow(thread)
                }
            }
        }
        .task(id: thread.approval) {
            armed = nil
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { armed = thread.approval }
        }
    }
}

/// A capsule button: outlined, or white with black text for the main answer.
private struct AnswerButton: View {
    let title: String
    let label: String
    let help: String
    var prominent = false
    var isEnabled = true
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            if isEnabled { action() }
        } label: {
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
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text(help))
        .accessibilityLabel(Text(label))
    }
}
