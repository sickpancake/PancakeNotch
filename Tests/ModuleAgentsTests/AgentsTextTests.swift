import AgentsCore
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
}
