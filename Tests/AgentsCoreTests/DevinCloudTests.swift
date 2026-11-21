import Foundation
import Testing
@testable import AgentsCore

/// Devin's cloud sessions (issue #55): read from Devin's API after Connect, shown in Agents and AI Usage.
@MainActor
struct DevinCloudTests {
    /// Keeps the token in memory instead of the Keychain.
    final class MemoryStore: DevinTokenStore, @unchecked Sendable {
        private let lock = NSLock()
        private var token: String?
        init(_ token: String? = nil) { self.token = token }
        func read() -> String? { lock.withLock { token } }
        func save(_ token: String) -> Bool { lock.withLock { self.token = token }; return true }
        func delete() { lock.withLock { token = nil } }
    }

    /// Answers like Devin's API: `/self`, then the sessions JSON it's given; counts the requests.
    final class FakeDevin: @unchecked Sendable {
        private let lock = NSLock()
        private var _sessions: String = #"{"items": []}"#
        private var _status = 200
        private var _requests: [URLRequest] = []
        var sessions: String { get { lock.withLock { _sessions } } set { lock.withLock { _sessions = newValue } } }
        var status: Int { get { lock.withLock { _status } } set { lock.withLock { _status = newValue } } }
        var requests: [URLRequest] { lock.withLock { _requests } }

        var send: DevinCloudAPI.Send {
            { [self] request in
                let (status, body) = lock.withLock { () -> (Int, String) in
                    _requests.append(request)
                    let isSelf = request.url?.path().hasSuffix("/v3/self") == true
                    return (_status, isSelf ? #"{"user_id": "me", "user_name": "Sam", "org_id": "org-1", "principal_type": "pat_user"}"# : _sessions)
                }
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (Data(body.utf8), response)
            }
        }
    }

    private func settings() -> AgentsSettings {
        AgentsSettings(defaults: UserDefaults(suiteName: "DevinCloudTests.\(UUID().uuidString)")!)
    }

    private func cloud(_ fake: FakeDevin, store: MemoryStore = MemoryStore()) -> DevinCloud {
        DevinCloud(defaults: UserDefaults(suiteName: "DevinCloudTests.\(UUID().uuidString)")!, store: store, send: fake.send)
    }

    private func session(_ id: String, status: String, detail: String? = nil, title: String? = "Fix the build",
                         created: Date, updated: Date? = nil, acus: Double = 1, user: String = "me",
                         pr: String? = nil, prState: String? = nil) -> String {
        var fields = [#""session_id": "\#(id)""#, #""status": "\#(status)""#, #""url": "https://app.devin.ai/sessions/\#(id)""#,
                      #""created_at": \#(Int(created.timeIntervalSince1970))"#,
                      #""updated_at": \#(Int((updated ?? created).timeIntervalSince1970))"#,
                      #""acus_consumed": \#(acus)"#, #""user_id": "\#(user)""#, #""tags": []"#, #""org_id": "org-1""#]
        if let detail { fields.append(#""status_detail": "\#(detail)""#) }
        if let title { fields.append(#""title": "\#(title)""#) }
        if let pr { fields.append(#""pull_requests": [{"pr_url": "\#(pr)", "pr_state": \#(prState.map { "\"\($0)\"" } ?? "null")}]"#) }
        return "{" + fields.joined(separator: ", ") + "}"
    }

    private func page(_ items: String...) -> String { #"{"items": [\#(items.joined(separator: ","))], "has_next_page": false}"# }

    // MARK: Reading Devin's answers

    @Test func sessionsReadWithSecondsOrMillisecondsAndBadItemsAreSkipped() throws {
        let json = #"""
        {"items": [
          {"session_id": "devin-a", "status": "running", "status_detail": "working", "created_at": 1795000000, "updated_at": 1795000000000, "acus_consumed": 2.5, "pull_requests": [], "tags": []},
          {"status": "running"},
          {"session_id": "devin-b", "status": "exit", "created_at": "2026-11-20T10:00:00Z"}
        ], "has_next_page": true, "end_cursor": "c1"}
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let page = try decoder.decode(DevinCloudPage.self, from: Data(json.utf8))
        #expect(page.items.map(\.sessionId) == ["devin-a", "devin-b"])
        #expect(page.items[0].createdAt == Date(timeIntervalSince1970: 1_795_000_000))
        #expect(page.items[0].updatedAt == Date(timeIntervalSince1970: 1_795_000_000))
        #expect(page.items[0].acusConsumed == 2.5)
        #expect(page.items[1].createdAt != nil)
        #expect(page.hasNextPage == true && page.endCursor == "c1")
    }

    @Test func statusesMapToTheAgentsList() {
        func status(_ status: String?, _ detail: String? = nil) -> AgentStatus? {
            DevinCloudSession(sessionId: "x", status: status, statusDetail: detail).agentStatus?.status
        }
        #expect(status("new") == .working)
        #expect(status("claimed") == .working)
        #expect(status("resuming") == .working)
        #expect(status("running", "working") == .working)
        #expect(status("running") == .working)
        #expect(status("running", "waiting_for_user") == .needsYou(.input))
        #expect(status("running", "waiting_for_approval") == .needsYou(.permission))
        #expect(status("running", "finished") == .done)
        #expect(status("exit") == .done)
        #expect(status("error") == .failed)
        #expect(status("suspended", "inactivity") == .done)
        #expect(status("suspended", "user_request") == .stopped)
        #expect(status("suspended", "out_of_credits") == .failed)
        #expect(status("suspended", "payment_declined") == .failed)
        // Unknown: left out rather than shown wrong.
        #expect(status("something_new") == nil)
        #expect(status(nil) == nil)
    }

    @Test func aFinishedSessionOpensItsPullRequestAndOnlyWebLinksOpen() {
        let pr = [DevinCloudSession.PullRequest(prUrl: "https://github.com/o/r/pull/128", prState: "merged")]
        let done = DevinCloudSession(sessionId: "x", url: "https://app.devin.ai/sessions/x", status: "exit", pullRequests: pr)
        #expect(done.link?.absoluteString == "https://github.com/o/r/pull/128")
        #expect(done.pullRequestLabel == "PR #128 · Merged")
        let working = DevinCloudSession(sessionId: "x", url: "https://app.devin.ai/sessions/x", status: "running", pullRequests: pr)
        #expect(working.link?.absoluteString == "https://app.devin.ai/sessions/x")
        let odd = DevinCloudSession(sessionId: "x", url: "file:///etc/passwd", status: "running")
        #expect(odd.link == nil)
        #expect(DevinCloudSession(sessionId: "x", status: "exit").pullRequestLabel == nil)
    }

    // MARK: Connecting

    @Test func aKeyOfTheWrongFormIsTurnedDownWithoutAskingDevin() async {
        let fake = FakeDevin()
        let cloud = cloud(fake)
        #expect(await cloud.connect(token: "apk_user_123") != nil)
        #expect(fake.requests.isEmpty)
        #expect(cloud.phase == .notConnected)
    }

    @Test func connectingSavesTheKeyAndOnlyTalksToDevin() async throws {
        let fake = FakeDevin()
        let store = MemoryStore()
        let cloud = cloud(fake, store: store)
        let agents = AgentsCenter(settings: settings())
        cloud.follow(agents: agents, usage: nil)
        #expect(fake.requests.isEmpty)
        #expect(await cloud.connect(token: "  cog_secret123\n") == nil)
        await cloud.settle()
        #expect(cloud.phase == .connected)
        #expect(cloud.userName == "Sam")
        #expect(store.read() == "cog_secret123")
        #expect(fake.requests.allSatisfy { $0.url?.host() == "api.devin.ai" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer cog_secret123" })
        #expect(fake.requests.contains { $0.url?.path() == "/v3/organizations/org-1/sessions" })
    }

    @Test func aRejectedKeyDisconnectsAndSaysSo() async {
        let fake = FakeDevin()
        fake.status = 401
        let cloud = cloud(fake)
        #expect(await cloud.connect(token: "cog_secret123") != nil)
        #expect(cloud.phase == .notConnected)

        // Later, while connected: the key stops working.
        fake.status = 200
        _ = await cloud.connect(token: "cog_secret123")
        let agents = AgentsCenter(settings: settings())
        fake.status = 401
        cloud.follow(agents: agents, usage: nil)
        cloud.check()
        await cloud.settle()
        #expect(cloud.phase == .notConnected)
        #expect(cloud.problem != nil)
    }

    @Test func nothingIsAskedWhileNeitherModuleIsOn() async {
        let fake = FakeDevin()
        let cloud = cloud(fake)
        _ = await cloud.connect(token: "cog_secret123")
        let asked = fake.requests.count
        cloud.check()
        cloud.checkIfOlder(than: 0)
        await cloud.settle()
        #expect(fake.requests.count == asked)
    }

    // MARK: Agents

    @Test func cloudSessionsShowInAgentsAndOpenTheirPage() async throws {
        let now = Date()
        let fake = FakeDevin()
        fake.sessions = page(
            session("devin-w", status: "running", detail: "working", title: "Add dark mode", created: now.addingTimeInterval(-300)),
            session("devin-d", status: "exit", title: "Bump deps", created: now.addingTimeInterval(-900), updated: now.addingTimeInterval(-120),
                    pr: "https://github.com/o/r/pull/7", prState: "open"),
            session("devin-old", status: "exit", created: now.addingTimeInterval(-86_400), updated: now.addingTimeInterval(-7_200)),
            session("devin-other", status: "running", detail: "working", created: now, user: "someone-else")
        )
        let agents = AgentsCenter(settings: settings())
        var alerts: [AgentAlert.Kind] = []
        agents.onAlert = { alerts.append($0.kind) }
        let cloud = cloud(fake)
        cloud.follow(agents: agents, usage: nil)
        _ = await cloud.connect(token: "cog_secret123")
        await cloud.settle()

        let threads = agents.threads
        #expect(threads.map(\.id) == ["devin-cloud:devin-w", "devin-cloud:devin-d"])
        let working = try #require(threads.first)
        #expect(working.tool == .devin && working.isCloud && working.canOpen)
        #expect(working.title == "Add dark mode")
        #expect(working.project == "Devin cloud")
        #expect(threads[1].project == "Devin cloud · PR #7 · Open")
        // The first look shows what's going on without popping up.
        #expect(alerts.isEmpty)
        // Cloud work doesn't keep the Mac awake.
        #expect(!agents.isBusy)
        #expect(cloud.hasScheduledCheck)

        // It asks something: that pops up.
        fake.sessions = page(session("devin-w", status: "running", detail: "waiting_for_user", title: "Add dark mode",
                                     created: now.addingTimeInterval(-300), updated: now))
        cloud.check()
        await cloud.settle()
        #expect(agents.threads.first?.status == .needsYou(.input))
        #expect(agents.threads.first?.request == "Waiting for your reply")
        #expect(alerts == [.needsYou])
        #expect(cloud.hasScheduledCheck)

        // Archived (gone from the list) while it waited: over.
        fake.sessions = page()
        cloud.check()
        await cloud.settle()
        #expect(agents.threads.first { $0.id == "devin-cloud:devin-w" }?.status == .stopped)
        #expect(!cloud.hasScheduledCheck)
    }

    @Test func everythingFinishedMeansNoFurtherChecks() async {
        let now = Date()
        let fake = FakeDevin()
        fake.sessions = page(session("devin-d", status: "exit", created: now.addingTimeInterval(-600), updated: now.addingTimeInterval(-60)))
        let agents = AgentsCenter(settings: settings())
        let cloud = cloud(fake)
        cloud.follow(agents: agents, usage: nil)
        _ = await cloud.connect(token: "cog_secret123")
        await cloud.settle()
        #expect(agents.threads.count == 1)
        #expect(!cloud.hasScheduledCheck)
        // The list coming on screen right after doesn't ask again (15 s apart at least).
        let asked = fake.requests.count
        agents.listShown()
        await cloud.settle()
        #expect(fake.requests.count == asked)
    }

    @Test func disconnectingForgetsTheKeyAndTheSessions() async {
        let now = Date()
        let fake = FakeDevin()
        fake.sessions = page(session("devin-w", status: "running", created: now))
        let store = MemoryStore()
        let agents = AgentsCenter(settings: settings())
        let usage = UsageCenter(settings: settings(), stats: nil)
        let cloud = cloud(fake, store: store)
        cloud.follow(agents: agents, usage: usage)
        _ = await cloud.connect(token: "cog_secret123")
        await cloud.settle()
        #expect(agents.threads.count == 1)
        #expect(usage.accounts.contains(.devinCloud))
        cloud.disconnect()
        #expect(store.read() == nil)
        #expect(agents.threads.isEmpty)
        #expect(!usage.accounts.contains(.devinCloud))
        #expect(!cloud.hasScheduledCheck)
    }

    // MARK: AI Usage

    @Test func usageAddsUpACUsByTheDaySessionsBegan() async throws {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let fake = FakeDevin()
        fake.sessions = page(
            session("devin-1", status: "exit", title: "Today", created: today.addingTimeInterval(60), acus: 2.5),
            session("devin-2", status: "exit", title: "Three days ago", created: calendar.date(byAdding: .day, value: -3, to: today)!, acus: 4),
            session("devin-3", status: "exit", title: "Twenty days ago", created: calendar.date(byAdding: .day, value: -20, to: today)!, acus: 10)
        )
        let usage = UsageCenter(settings: settings(), stats: nil)
        let cloud = cloud(fake)
        cloud.follow(agents: nil, usage: usage)
        _ = await cloud.connect(token: "cog_secret123")
        await cloud.settle()
        let devin = try #require(usage.devinUsage)
        #expect(devin.acus(in: .today, now: now) == 2.5)
        #expect(devin.acus(in: .week, now: now) == 6.5)
        #expect(devin.acus(in: .month, now: now) == 16.5)
        #expect(devin.top(2, in: .month, now: now).map(\.title) == ["Twenty days ago", "Three days ago"])
        #expect(usage.accounts == [.devinCloud])
        #expect(usage.accounts.first?.name == "Devin")
        #expect(usage.earReading == nil)
        // AI Usage alone checks on its own schedule only: nothing is running, so nothing more is planned.
        #expect(!cloud.hasScheduledCheck)
    }
}
