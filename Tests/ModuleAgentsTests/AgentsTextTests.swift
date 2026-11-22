@testable import AgentsCore
import Foundation
import Testing
@testable import ModuleAgents

struct AgentsTextTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func thread(_ status: AgentStatus, project: String = "web-app", step: String? = nil, request: String? = nil) -> AgentThread {
        AgentThread(id: "claude:\(UUID().uuidString)", tool: .claude, title: "Fix the login redirect", project: project,
                    status: status, statusSince: now.addingTimeInterval(-4 * 60), step: step, request: request)
    }

    @Test func spansUseWholeUnitsRoundedDown() {
        #expect(AgentsText.span(40) == "40s")
        #expect(AgentsText.span(4 * 60 + 59) == "4m")
        #expect(AgentsText.span(3 * 86_400 + 5_000) == "3d")
        #expect(AgentsText.span(-5) == "0s")
    }

    @Test func theStatusLineSaysHowLongOrHowLongAgo() {
        let since = now.addingTimeInterval(-4 * 60)
        #expect(AgentsText.statusLine(.working, since: since, now: now) == "Working · 4m")
        #expect(AgentsText.statusLine(.done, since: since, now: now) == "Done · 4m ago")
    }

    @Test func theSubtitleFollowsTheStatus() {
        #expect(AgentsText.subtitle(thread(.working, step: "Running tests")) == "web-app · Running tests")
        #expect(AgentsText.subtitle(thread(.needsYou(.permission), request: "Wants to run: npm test")) == "web-app · Wants to run: npm test")
        #expect(AgentsText.subtitle(thread(.done, step: "Running tests")) == "web-app")
        #expect(AgentsText.subtitle(thread(.working, project: "", step: "Running tests")) == "Running tests")
    }

    @Test func theSubtitleUsesWhatSettingsPutUnderTheName() {
        var shown = thread(.working, step: "Running tests")
        shown.byline = "Can you finish this up?"
        #expect(AgentsText.subtitle(shown) == "Can you finish this up? · Running tests")
        shown.byline = ""
        #expect(AgentsText.subtitle(shown) == "Running tests")
    }

    @Test func theSummaryCountsWhatIsGoingOn() {
        let threads = [thread(.working), thread(.working), thread(.needsYou(.input)), thread(.done)]
        #expect(AgentsText.summary(threads, includesFinished: false) == "2 working · 1 needs you")
        #expect(AgentsText.summary(threads, includesFinished: true) == "2 working · 1 needs you · 1 done")
        #expect(AgentsText.summary([thread(.needsYou(.input)), thread(.needsYou(.permission))], includesFinished: false) == "2 need you")
        #expect(AgentsText.summary([thread(.done)], includesFinished: false) == nil)
    }

    @Test func thePeekNamesToolAndProject() {
        let alert = AgentAlert(kind: .needsYou, thread: thread(.needsYou(.permission)))
        let text = AgentsText.peek(alert)
        #expect(text.subject == "Claude · web-app")
        #expect(text.verb == "needs you")
        // Without a project the title stands in.
        let untitled = AgentAlert(kind: .finished, thread: thread(.done, project: ""))
        #expect(AgentsText.peek(untitled).subject == "Claude · Fix the login redirect")
    }

    @Test func attentionPicksTheMarkAndTheWords() {
        #expect(AgentsAttention.needsYou(count: 2).count == 2)
        #expect(AgentsAttention.finished(count: 1).status == .done)
        #expect(AgentsAttention.failed(count: 1).status == .failed)
        #expect(AgentsText.spoken(.needsYou(count: 1)) == "An agent needs you")
        #expect(AgentsText.spoken(.working(count: 3)) == "3 agents are working")
    }

    @Test(arguments: ["echo one\necho two", "echo one\n\necho two", "echo " + String(repeating: "x", count: 90)])
    func approvalSpeechPreservesCommands(_ command: String) throws {
        let review = try #require(AgentReview.make(tool: "Bash", input: ["command": command], cwd: nil, home: "/tmp"))
        var pending = thread(.needsYou(.permission))
        pending.approval = PendingApproval(requestID: 1, review: review)
        #expect(AgentsText.spoken(pending, now: now).contains(", " + command + ", "))
    }

    @Test func harnessNamesTheToolAndTheAppItRunsIn() {
        var running = thread(.working)
        #expect(AgentsText.harness(running) == "Claude Code")
        running.hostName = "T3 Code"
        #expect(AgentsText.harness(running) == "Claude Code in T3 Code")
        #expect(AgentsText.spoken(running, now: now).hasPrefix("Fix the login redirect, Claude Code in T3 Code, "))
        // The tool's own app, or a blank name, isn't said twice.
        running.hostName = "claude code"
        #expect(AgentsText.harness(running) == "Claude Code")
        running.hostName = "  "
        #expect(AgentsText.harness(running) == "Claude Code")
    }
}

@MainActor
struct AgentsDoneSummaryTextTests {
    private let summary = DoneSummary(branch: "readme-refresh", filesChanged: 3, insertions: 48, deletions: 12, lastCommit: "Rewrite the install steps")

    private func finished(_ summary: DoneSummary?) -> AgentThread {
        AgentThread(id: "claude:a", tool: .claude, title: "Update the README", project: "docs", status: .done,
                    statusSince: .now, canOpen: true, isSeen: true, doneSummary: summary)
    }

    @Test func aFinishedRowSaysWhatChanged() {
        #expect(AgentsText.subtitle(finished(summary)) == "docs · readme-refresh · 3 files · +48 −12")
        #expect(AgentsText.subtitle(finished(nil)) == "docs")
        #expect(AgentsText.changes(DoneSummary(filesChanged: 1, insertions: 2, deletions: 0)) == "1 file · +2 −0")
        #expect(AgentsText.changes(DoneSummary(filesChanged: 0, insertions: 0, deletions: 0)) == "No changes")
        #expect(AgentsText.doneLine(DoneSummary(filesChanged: 2, insertions: 1, deletions: 1)) == "2 files · +1 −1")
    }

    @Test func thePeekAndTheCopyCarryTheSummary() {
        #expect(AgentsText.peek(AgentAlert(kind: .finished, thread: finished(summary))).verb == "finished")
        #expect(AgentsText.peekDetail(AgentAlert(kind: .finished, thread: finished(summary))) == "3 files · +48 −12")
        #expect(AgentsText.peekDetail(AgentAlert(kind: .finished, thread: finished(nil))) == nil)
        #expect(AgentsText.peekDetail(AgentAlert(kind: .failed, thread: finished(summary))) == nil)
        #expect(AgentsText.copyText(finished(summary), summary)
            == "Update the README (docs) · readme-refresh · 3 files · +48 −12 · Last commit: Rewrite the install steps")
    }

    @Test func voiceOverReadsTheSummary() {
        let spoken = AgentsText.spoken(finished(summary), now: .now)
        #expect(spoken.contains("On readme-refresh, 3 files changed, 48 lines added, 12 lines removed"))
        #expect(spoken.contains("Last commit: Rewrite the install steps"))
        #expect(!spoken.contains("+48"))
    }
}
