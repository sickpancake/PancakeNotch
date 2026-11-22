import Foundation
import Testing
@testable import AgentsCore

/// Codex cloud, GitHub's coding agent, pull request checks and Devin's quick replies (issue #55).
@MainActor
struct CloudAgentsTests {
    /// Answers like the tools: the output given for a command, by its first two words; counts the runs.
    final class FakeTools: @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [String: CloudCommand.Output] = [:]
        private var _runs: [[String]] = []
        var installed = true
        var runs: [[String]] { lock.withLock { _runs } }

        func answer(_ command: String, _ json: String, status: Int32 = 0) {
            lock.withLock { answers[command] = .init(status: status, data: Data(json.utf8)) }
        }

        var run: CloudCommand.Run {
            { [self] program, arguments in
                lock.withLock {
                    _runs.append([program.rawValue] + arguments)
                    guard installed else { return nil }
                    return answers[([program.rawValue] + arguments.prefix(2)).joined(separator: " ")] ?? .init(status: 1, data: Data())
                }
            }
        }
    }

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "CloudAgentsTests.\(UUID().uuidString)")! }
    private func settings() -> AgentsSettings { AgentsSettings(defaults: defaults()) }

    // MARK: Reading the tools

    @Test func codexTasksMapToAgentStatuses() throws {
        let json = #"""
        {"tasks": [
          {"id": "task_a", "url": "https://chatgpt.com/codex/tasks/task_a", "title": "Add CSV export", "status": "pending", "updated_at": "2026-11-21T10:00:00Z", "environment_label": "web"},
          {"id": "task_b", "url": "https://chatgpt.com/codex/tasks/task_b", "title": "Fix login", "status": "ready", "updated_at": "2026-11-21T10:00:00.123Z", "summary": {"files_changed": 3}},
          {"id": "task_c", "title": "Bump deps", "status": "error"},
          {"id": "task_d", "status": "applied", "url": "http://insecure.example"},
          {"id": "task_e", "status": "something-new"},
          {"status": "pending"}
        ], "cursor": null}
        """#
        let tasks = try #require(CloudService.codex.tasks(from: Data(json.utf8)))
        #expect(tasks.map(\.id) == ["task_a", "task_b", "task_c", "task_d"])
        #expect(tasks.map(\.status) == [.working, .done, .failed, .done])
        #expect(tasks[0].byline == "web")
        #expect(tasks[0].link?.absoluteString == "https://chatgpt.com/codex/tasks/task_a")
        #expect(tasks[1].byline == "3 files changed")
        #expect(tasks[1].changed != nil)
        #expect(tasks[3].link == nil)
        #expect(tasks[3].title == "Codex cloud")
        #expect(CloudService.codex.tasks(from: Data("not json".utf8)) == nil)
    }

    @Test func gitHubTasksKeepTheNewestPerPullRequestAndLinkIt() throws {
        let json = #"""
        [
          {"id": "s1", "name": "Fix the flaky test", "state": "completed", "repository": "me/app", "updatedAt": "2026-11-21T09:00:00Z",
           "pullRequestNumber": 7, "pullRequestUrl": "https://github.com/me/app/pull/7", "pullRequestState": "OPEN"},
          {"id": "s0", "name": "Fix the flaky test", "state": "failed", "repository": "me/app", "updatedAt": "2026-11-21T08:00:00Z",
           "pullRequestNumber": 7, "pullRequestUrl": "https://github.com/me/app/pull/7"},
          {"id": "s2", "name": "Add a dark mode", "state": "waiting_for_user", "repository": "me/app", "updatedAt": "2026-11-21T09:30:00Z",
           "pullRequestNumber": 8, "pullRequestUrl": "https://github.com/me/app/pull/8"},
          {"id": "s3", "name": "Speed up CI", "state": "timed_out", "updatedAt": "2026-11-21T07:00:00Z"},
          {"id": "s4", "state": "queued"}
        ]
        """#
        let tasks = try #require(CloudService.github.tasks(from: Data(json.utf8)))
        #expect(tasks.map(\.id) == ["s2", "s1", "s3", "s4"])
        #expect(tasks.map(\.status) == [.needsYou(.input), .done, .failed, .working])
        #expect(tasks[0].reason == "Waiting for you")
        #expect(tasks[0].link?.absoluteString == "https://github.com/me/app/pull/8/agent-sessions/s2")
        #expect(tasks[1].link?.absoluteString == "https://github.com/me/app/pull/7")
        #expect(tasks[1].byline == "app · PR #7 · Open")
        #expect(tasks[2].byline == "Timed out")
        #expect(tasks[3].title == "GitHub coding agent")
    }

    @Test func checksReadFromTheirBuckets() {
        func checks(_ buckets: String...) -> PullRequestChecks? {
            PullRequestChecks.from(Data(("[" + buckets.map { #"{"bucket": "\#($0)"}"# }.joined(separator: ",") + "]").utf8))
        }
        #expect(checks("pass", "skipping") == .passed)
        #expect(checks("pass", "pending") == .running)
        #expect(checks("pending", "fail") == .failed)
        #expect(checks("cancel") == .failed)
        #expect(checks() == nil)
        #expect(PullRequestChecks.from(Data("no checks reported".utf8)) == nil)
    }

    // MARK: Turning on

    @Test func turnOnSaysWhatsMissingAndStaysOff() async {
        let tools = FakeTools()
        tools.installed = false
        let store = defaults()
        let cloud = CloudAgents(defaults: store, run: tools.run)
        #expect(await cloud.turnOn(.github) == CloudAgents.missing(.github))
        #expect(cloud.state(.github) == .off)
        tools.installed = true
        #expect(await cloud.turnOn(.codex) == CloudAgents.signedOut(.codex))
        #expect(cloud.state(.codex) == .off)
        #expect(CloudAgents(defaults: store, run: tools.run).state(.codex) == .off)
    }

    @Test func nothingRunsUntilTurnedOnAndTasksShowAfter() async {
        let tools = FakeTools()
        tools.answer("codex cloud list", #"{"tasks": [{"id": "t1", "title": "Add CSV export", "status": "pending", "url": "https://chatgpt.com/codex/tasks/t1"}]}"#)
        let store = defaults()
        let agents = AgentsCenter(settings: settings())
        let cloud = CloudAgents(defaults: store, run: tools.run)
        cloud.follow(agents: agents)
        await cloud.settle()
        #expect(tools.runs.isEmpty)

        #expect(await cloud.turnOn(.codex) == nil)
        await cloud.settle()
        let thread = agents.thread("codex-cloud:t1")
        #expect(thread?.status == .working)
        #expect(thread?.isCloud == true)
        #expect(thread?.tool == .codex)
        #expect(thread?.project == "Codex cloud")
        #expect(cloud.hasScheduledCheck)
        #expect(!agents.isBusy)
        #expect(CloudAgents(defaults: store, run: tools.run).state(.codex) == .on)

        // Gone from the list while it worked: over.
        tools.answer("codex cloud list", #"{"tasks": []}"#)
        cloud.check()
        await cloud.settle()
        #expect(agents.thread("codex-cloud:t1")?.status == .stopped)

        cloud.turnOff(.codex)
        #expect(agents.thread("codex-cloud:t1") == nil)
        #expect(!cloud.hasScheduledCheck)
    }

    @Test func signingOutDropsTheRowsAndKeepsTrying() async {
        let tools = FakeTools()
        tools.answer("gh agent-task list", #"[{"id": "s1", "name": "Add a dark mode", "state": "waiting_for_user", "repository": "me/app"}, {"id": "s2", "name": "Speed up CI", "state": "in_progress"}]"#)
        let agents = AgentsCenter(settings: settings())
        let cloud = CloudAgents(defaults: defaults(), run: tools.run)
        cloud.follow(agents: agents)
        #expect(await cloud.turnOn(.github) == nil)
        await cloud.settle()
        #expect(agents.thread("github-cloud:s1")?.status == .needsYou(.input))
        #expect(agents.thread("github-cloud:s2")?.status == .working)

        // `gh auth logout`: nothing in the list can be trusted, and it's tried again later.
        tools.answer("gh agent-task list", "", status: 4)
        cloud.check()
        await cloud.settle()
        #expect(cloud.state(.github) == .unavailable)
        #expect(cloud.problems[.github] == CloudAgents.signedOut(.github))
        #expect(agents.thread("github-cloud:s1") == nil)
        #expect(agents.thread("github-cloud:s2") == nil)
        #expect(!agents.threads.contains { $0.status.needsYou })
        #expect(cloud.hasScheduledCheck)

        // The tool goes missing too: same.
        tools.installed = false
        cloud.check()
        await cloud.settle()
        #expect(cloud.problems[.github] == CloudAgents.missing(.github))
        #expect(cloud.hasScheduledCheck)

        // Signed in again: back without a click.
        tools.installed = true
        tools.answer("gh agent-task list", #"[{"id": "s2", "name": "Speed up CI", "state": "in_progress"}]"#)
        cloud.check()
        await cloud.settle()
        #expect(cloud.state(.github) == .on)
        #expect(cloud.problems[.github] == nil)
        #expect(agents.thread("github-cloud:s2")?.status == .working)
    }

    @Test func finishedPullRequestsGetTheirChecks() async {
        let tools = FakeTools()
        tools.answer("gh agent-task list", #"[{"id": "s1", "name": "Fix it", "state": "completed", "updatedAt": "\#(Date().ISO8601Format())", "pullRequestNumber": 7, "pullRequestUrl": "https://github.com/me/app/pull/7"}]"#)
        tools.answer("gh pr checks", #"[{"bucket": "pass"}, {"bucket": "pending"}]"#, status: 8)
        let agents = AgentsCenter(settings: settings())
        let cloud = CloudAgents(defaults: defaults(), run: tools.run)
        cloud.follow(agents: agents)
        #expect(await cloud.turnOn(.github) == nil)
        await cloud.settle()
        let thread = agents.thread("github-cloud:s1")
        #expect(thread?.status == .done)
        #expect(thread?.tool == .github)
        #expect(thread?.pullRequest?.absoluteString == "https://github.com/me/app/pull/7")
        #expect(thread?.checks == .running)
        #expect(cloud.hasScheduledCheck)
        #expect(tools.runs.contains(["gh", "pr", "checks", "https://github.com/me/app/pull/7", "--json", "bucket"]))

        tools.answer("gh pr checks", #"[{"bucket": "pass"}, {"bucket": "fail"}]"#, status: 1)
        cloud.check()
        await cloud.settle()
        #expect(agents.thread("github-cloud:s1")?.checks == .failed)
        #expect(!cloud.hasScheduledCheck)
    }

    // MARK: Devin quick replies

    @Test func devinWaitingForAMessageGetsContinueAndStop() async throws {
        let fake = DevinCloudTests.FakeDevin()
        let now = Int(Date().timeIntervalSince1970)
        fake.sessions = #"{"items": [{"session_id": "devin-q", "status": "running", "status_detail": "waiting_for_user", "url": "https://app.devin.ai/sessions/q", "created_at": \#(now), "updated_at": \#(now), "user_id": "me"}], "has_next_page": false}"#
        let cloud = DevinCloud(defaults: defaults(), store: DevinCloudTests.MemoryStore(), send: fake.send)
        let agents = AgentsCenter(settings: settings())
        cloud.follow(agents: agents, usage: nil)
        #expect(await cloud.connect(token: "cog_secret123") == nil)
        await cloud.settle()
        let thread = try #require(agents.thread("devin-cloud:devin-q"))
        #expect(thread.quickReplies == [.proceed, .stop])

        agents.quickReply(.proceed, to: thread)
        #expect(agents.thread("devin-cloud:devin-q")?.status == .working)
        #expect(agents.thread("devin-cloud:devin-q")?.quickReplies == [])
        for _ in 0..<50 where !fake.requests.contains(where: { $0.httpMethod == "POST" }) { try await Task.sleep(for: .milliseconds(20)) }
        let post = try #require(fake.requests.first { $0.httpMethod == "POST" })
        #expect(post.url?.path() == "/v3/organizations/org-1/sessions/devin-q/messages")
        let body = try #require(post.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(body == ["message": "Continue"])
    }

    @Test func devinStopArchivesTheSession() async throws {
        let fake = DevinCloudTests.FakeDevin()
        let now = Int(Date().timeIntervalSince1970)
        fake.sessions = #"{"items": [{"session_id": "devin-s", "status": "running", "status_detail": "waiting_for_user", "url": "https://app.devin.ai/sessions/s", "created_at": \#(now), "updated_at": \#(now), "user_id": "me"}], "has_next_page": false}"#
        let cloud = DevinCloud(defaults: defaults(), store: DevinCloudTests.MemoryStore(), send: fake.send)
        let agents = AgentsCenter(settings: settings())
        cloud.follow(agents: agents, usage: nil)
        #expect(await cloud.connect(token: "cog_secret123") == nil)
        await cloud.settle()
        let thread = try #require(agents.thread("devin-cloud:devin-s"))

        agents.quickReply(.stop, to: thread)
        #expect(agents.thread("devin-cloud:devin-s")?.status == .stopped)
        for _ in 0..<50 where !fake.requests.contains(where: { $0.httpMethod == "POST" }) { try await Task.sleep(for: .milliseconds(20)) }
        let post = try #require(fake.requests.first { $0.httpMethod == "POST" })
        #expect(post.url?.path() == "/v3/organizations/org-1/sessions/devin-s/archive")
    }

    @Test func practiceCloudListShowsEveryService() {
        let threads = PracticeAgents.cloudThreads(now: .now)
        let tools = Set(threads.map(\.tool))
        #expect(tools == [.devin, .codex, .github])
        #expect(threads.allSatisfy { $0.isCloud })
        #expect(threads.contains { !$0.quickReplies.isEmpty })
        #expect(threads.contains { $0.checks == .failed })
    }

    @Test func practiceLessonHasCloudAgentsThatAnswerQuickReplies() async throws {
        let center = AgentsCenter.practice()
        let ids = Set(center.threads.map(\.id))
        #expect(ids.isSuperset(of: [PracticeAgents.cloudAskingID, PracticeAgents.codexCloudID,
                                    PracticeAgents.copilotID, PracticeAgents.cloudID]))
        let asking = try #require(center.thread(PracticeAgents.cloudAskingID))
        center.quickReply(.stop, to: asking)
        #expect(center.thread(PracticeAgents.cloudAskingID)?.status == .stopped)
        #expect(center.thread(PracticeAgents.cloudAskingID)?.quickReplies == [])
        center.reset()
        let again = try #require(center.thread(PracticeAgents.cloudAskingID))
        center.quickReply(.proceed, to: again)
        #expect(center.thread(PracticeAgents.cloudAskingID)?.status == .working)
    }
}
