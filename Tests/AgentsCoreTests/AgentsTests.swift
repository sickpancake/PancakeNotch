import Foundation
import Testing
@testable import AgentsCore

@MainActor
struct AgentsCenterTests {
    private func center() -> AgentsCenter {
        AgentsCenter(settings: AgentsSettings(defaults: UserDefaults(suiteName: "AgentsCenterTests.\(UUID().uuidString)")!))
    }

    @Test func aThreadThatNeedsYouAlertsAndComesFirst() {
        let center = center()
        var alerts: [AgentAlert.Kind] = []
        center.onAlert = { alerts.append($0.kind) }
        let now = Date()
        center.apply(.init(id: "claude:a", tool: .claude, at: now, cwd: "/tmp/web-app", status: .working))
        center.apply(.init(id: "codex:b", tool: .codex, at: now, status: .working))
        center.apply(.init(id: "codex:b", tool: .codex, at: now, status: .needsYou(.permission), request: .some("Wants to run: ls")))
        #expect(alerts == [.needsYou])
        #expect(center.threads.first?.id == "codex:b")
        #expect(center.threads.first?.request == "Wants to run: ls")
        #expect(center.attention == .needsYou(count: 1))
        #expect(center.threads.last?.title == "web-app")
    }

    @Test func onlyLongWorkPeeksWhenItFinishes() {
        let center = center()
        var alerts: [AgentAlert.Kind] = []
        center.onAlert = { alerts.append($0.kind) }
        let now = Date()
        center.apply(.init(id: "claude:quick", tool: .claude, at: now, status: .working))
        center.apply(.init(id: "claude:quick", tool: .claude, at: now, status: .done))
        center.apply(.init(id: "claude:long", tool: .claude, at: now.addingTimeInterval(-60), status: .working))
        center.apply(.init(id: "claude:long", tool: .claude, at: now, status: .done))
        #expect(alerts == [.finished])
        #expect(center.attention == .finished(count: 2))
    }

    @Test func threadsFoundAtLaunchArriveQuietly() {
        let center = center()
        var alerted = false
        center.onAlert = { _ in alerted = true }
        center.apply(.init(id: "claude:old", tool: .claude, at: .now, status: .done, quietly: true))
        #expect(!alerted)
        #expect(center.threads.first?.isSeen == true)
        #expect(center.attention == nil)
    }

    @Test func seenFinishedThreadsLeaveAfterHalfAnHour() {
        let center = center()
        let start = Date()
        center.apply(.init(id: "claude:a", tool: .claude, at: start, status: .done))
        center.listShown()
        center.listHidden()
        #expect(center.threads.count == 1)
        center.apply(.init(id: "claude:b", tool: .claude, at: Date().addingTimeInterval(AgentsCenter.keepAfterSeen + 60), status: .working))
        #expect(center.threads.map(\.id) == ["claude:b"])
    }

    @Test func clearFinishedKeepsTheOthers() {
        let center = center()
        center.apply(.init(id: "claude:a", tool: .claude, at: .now, status: .done))
        center.apply(.init(id: "claude:b", tool: .claude, at: .now, status: .working))
        center.clearFinished()
        #expect(center.threads.map(\.id) == ["claude:b"])
        #expect(!center.hasFinished)
    }

    @Test func theEndOfASessionStopsAWaitingThread() {
        let center = center()
        center.apply(.init(id: "claude:a", tool: .claude, at: .now, status: .needsYou(.input)))
        center.ended("claude:a", at: .now)
        #expect(center.threads.first?.status == .stopped)
    }

    @Test func aWorkingSessionThatQuitsIsStopped() {
        let center = center()
        center.apply(.init(id: "claude:a", tool: .claude, at: .now, status: .working))
        center.ended("claude:a", at: .now)
        #expect(center.threads.first?.status == .stopped)
    }

    @Test func codexHooksHideReviewersAndHelpers() throws {
        let center = center()
        let sources = LiveAgentSources(center: center)
        sources.handle(HookEvent(tool: .codex, name: "UserPromptSubmit", parentPID: 0,
                                 payload: ["session_id": "review", "model": "codex-auto-review"]))
        #expect(center.threads.isEmpty)
        let file = try temporaryFolder().appending(path: "helper.jsonl")
        try Data(#"{"type":"session_meta","payload":{"id":"helper","source":{"subagent":{"other":"guardian"}}}}"#.utf8).write(to: file)
        sources.handle(HookEvent(tool: .codex, name: "UserPromptSubmit", parentPID: 0,
                                 payload: ["session_id": "helper", "transcript_path": file.path]))
        #expect(center.threads.isEmpty)
        // A run that saves no history (a background helper, no rollout) never shows.
        sources.handle(HookEvent(tool: .codex, name: "UserPromptSubmit", parentPID: 0,
                                 payload: ["session_id": "real", "model": "gpt-6.1-sol"]))
        sources.handle(HookEvent(tool: .codex, name: "Interrupt", parentPID: 0,
                                 payload: ["session_id": "ephemeral", "transcript_path": "/nonexistent/rollout.jsonl"]))
        #expect(center.threads.isEmpty)
        let rollout = try temporaryFolder().appending(path: "real.jsonl")
        try Data(#"{"type":"session_meta","payload":{"id":"real"}}"#.utf8).write(to: rollout)
        sources.handle(HookEvent(tool: .codex, name: "UserPromptSubmit", parentPID: 0,
                                 payload: ["session_id": "real", "model": "gpt-6.1-sol", "transcript_path": rollout.path]))
        #expect(center.threads.map(\.id) == ["codex:real"])
        // Nor can it change the conversation it shares an ID with.
        sources.handle(HookEvent(tool: .codex, name: "Interrupt", parentPID: 0, payload: ["session_id": "real"]))
        #expect(center.threads.first?.status == .working)
        // The reviewer's hooks carry its parent's session ID: the parent stays.
        let review = try temporaryFolder().appending(path: "review.jsonl")
        try Data(#"{"type":"session_meta","payload":{"id":"guardian","session_id":"real","source":{"subagent":{"other":"guardian"}}}}"#.utf8).write(to: review)
        sources.handle(HookEvent(tool: .codex, name: "UserPromptSubmit", parentPID: 0,
                                 payload: ["session_id": "real", "transcript_path": review.path]))
        sources.handle(HookEvent(tool: .codex, name: "SessionEnd", parentPID: 0,
                                 payload: ["session_id": "real", "transcript_path": review.path]))
        #expect(center.threads.map(\.id) == ["codex:real"])
        #expect(center.threads.first?.status == .working)
        sources.stop()
        sources.handle(HookEvent(tool: .codex, name: "UserPromptSubmit", parentPID: 0, payload: ["session_id": "late"]))
        #expect(center.threads.map(\.id) == ["codex:real"])
    }

    @Test func aHostAppsHelperIsMatchedFromItsFirstPromptHook() async throws {
        let center = center()
        let sources = LiveAgentSources(center: center)
        defer { sources.stop() }
        let task = "Review the notch views for alignment. Read only."
        let main = try temporaryFolder().appending(path: "main.jsonl")
        try Data((#"{"type":"user","message":{"role":"user","content":"Polish the app"}}"# + "\n"
            + #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__t3-code__delegate_task","input":{"title":"Notch review","task":"\#(task)"}}]}}"# + "\n").utf8).write(to: main)
        sources.handle(HookEvent(tool: .claude, name: "UserPromptSubmit", parentPID: 0,
                                 payload: ["session_id": "main", "transcript_path": main.path, "prompt": "Polish the app"]))
        // The helper's own transcript isn't written yet: its hook carries the task.
        sources.handle(HookEvent(tool: .claude, name: "UserPromptSubmit", parentPID: 0,
                                 payload: ["session_id": "helper", "transcript_path": "/nonexistent/helper.jsonl",
                                           "prompt": "Act as the review sub-agent for this task.\n\n\(task)"]))
        for _ in 0..<200 where center.threads.count != 1 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(center.threads.map(\.id) == ["claude:main"])
        #expect(center.threads.first?.subagents.map(\.title) == ["Notch review"])
    }

    @Test func twoVisibleListsKeepFinishedThreadsSeenUntilBothClose() {
        let center = center()
        center.listShown()
        center.listShown()
        center.listHidden()
        center.apply(.init(id: "claude:a", tool: .claude, at: .now, status: .done))
        #expect(center.thread("claude:a")?.isSeen == true)
        center.listHidden()
        center.apply(.init(id: "claude:b", tool: .claude, at: .now, status: .done))
        #expect(center.thread("claude:b")?.isSeen == false)
    }

    @Test func practiceAllowGoesBackToWork() throws {
        let center = AgentsCenter.practice()
        var events: [AgentsPracticeEvent] = []
        center.onPracticeEvent = { events.append($0) }
        let asking = try #require(center.threads.first { $0.status.needsYou })
        center.allow(asking)
        #expect(events == [.allowed])
        #expect(center.thread(asking.id)?.status == .working)
        center.reset()
        #expect(center.thread(asking.id)?.status.needsYou == true)
    }
}

struct AgentStepsTests {
    @Test func steps() {
        #expect(AgentSteps.step(tool: "Bash", input: ["command": "npm test\necho done"]) == "Running npm test")
        #expect(AgentSteps.step(tool: "Edit", input: ["file_path": "/a/b/NotchView.swift"]) == "Editing NotchView.swift")
        #expect(AgentSteps.step(tool: "apply_patch", input: ["input": "*** Begin Patch\n*** Update File: Sources/App.swift\n"]) == "Editing App.swift")
        #expect(AgentSteps.step(tool: "mcp__github__create_issue", input: [:]) == "Using create_issue (github)")
        #expect(AgentSteps.request(tool: "exec_command", input: ["cmd": ["rm", "-rf", "build"]]) == "Wants to run: rm -rf build")
        #expect(AgentSteps.request(tool: "WebFetch", input: ["url": "https://example.com/page"]) == "Wants to open example.com")
    }

    @Test func longCommandsAreCut() throws {
        let command = try #require(AgentSteps.command(in: ["command": String(repeating: "a", count: 100)]))
        #expect(command.count == 60 && command.hasSuffix("…"))
    }
}

struct ToolFilesTests {
    @Test func claudeSessionList() throws {
        let session = try #require(ClaudeSession(data: Data(#"""
        {"pid": 123, "sessionId": "s1", "cwd": "/tmp/app", "name": "Untitled session", "status": "waiting",
         "waitingFor": "permission to run Bash", "statusUpdatedAt": 1792617049506}
        """#.utf8)))
        #expect(session.name == nil)
        #expect(session.agentStatus == .needsYou(.permission))
        #expect(session.request == "Permission to run Bash")
        #expect(ClaudeSession(data: Data(#"{"pid": 1, "sessionId": "s", "status": "busy"}"#.utf8))?.agentStatus == .working)
        #expect(ClaudeSession(data: Data(#"{"pid": 1, "sessionId": "s", "status": "idle"}"#.utf8))?.agentStatus == nil)
    }

    @Test func codexRolloutFollowsTheTurn() {
        var rollout = CodexRollout()
        func feed(_ text: String) -> Bool { rollout.consume(Data(text.utf8)) }
        #expect(feed(#"{"timestamp":"2026-10-17T19:41:40.000Z","type":"session_meta","payload":{"id":"t1","cwd":"/tmp/compiler","originator":"Codex Desktop","source":"cli"}}"#))
        #expect(rollout.threadID == "t1" && !rollout.isHelper)
        #expect(rollout.hostBundleID == "com.openai.codex")
        #expect(feed(#"{"timestamp":"2026-10-17T19:41:41.000Z","type":"event_msg","payload":{"type":"task_started"}}"#))
        #expect(rollout.status == .working)
        #expect(feed(#"{"timestamp":"2026-10-17T19:41:42.000Z","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\"command\":[\"cargo\",\"test\"]}"}}"#))
        #expect(rollout.step == "Running cargo test")
        #expect(feed(#"{"timestamp":"2026-10-17T19:41:50.000Z","type":"event_msg","payload":{"type":"task_complete"}}"#))
        #expect(rollout.status == .done && rollout.step == nil)
        // Messages and reasoning aren't read.
        #expect(!feed(#"{"timestamp":"2026-10-17T19:41:51.000Z","type":"response_item","payload":{"type":"message","content":"hi"}}"#))
    }

    @Test func connectAddsOurHooksAndDisconnectTakesOnlyThoseOut() throws {
        let file = try temporaryFolder().appending(path: "settings.json")
        let theirs = #"{"model": "opus", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]}}"#
        try Data(theirs.utf8).write(to: file)

        try HookFile.update(file, kind: .claude, connect: true)
        let connected = try #require(HookFile.read(file))
        #expect(connected.contains(HookHelper.marker))
        #expect(connected.contains("say done"))
        #expect(FileManager.default.fileExists(atPath: file.path + ".before-pancakenotch"))
        // Connecting twice doesn't add a second copy.
        try HookFile.update(file, kind: .claude, connect: true)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let stop = try #require((object["hooks"] as? [String: Any])?["Stop"] as? [Any])
        #expect(stop.count == 2)

        try HookFile.update(file, kind: .claude, connect: false)
        let back = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(back["model"] as? String == "opus")
        let hooks = try #require(back["hooks"] as? [String: Any])
        #expect(Array(hooks.keys) == ["Stop"])
        #expect(!(try #require(HookFile.read(file))).contains(HookHelper.marker))
    }

    @Test func aBrokenHookFileIsLeftAlone() throws {
        let file = try temporaryFolder().appending(path: "hooks.json")
        try Data("{ not json".utf8).write(to: file)
        #expect(throws: HookFile.Problem.self) { try HookFile.update(file, kind: .codex, connect: true) }
        #expect(HookFile.read(file) == "{ not json")
    }

    @Test func cursorHooksGetAVersion() throws {
        let file = try temporaryFolder().appending(path: "hooks.json")
        try HookFile.update(file, kind: .cursor, connect: true)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(object["version"] as? Int == 1)
    }

    @Test func permissionAnswersUseTheToolsFormat() throws {
        let answer = LiveAgentSources.decision(allow: false, tool: .claude)
        let object = try #require(JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any])
        let output = try #require(object["hookSpecificOutput"] as? [String: Any])
        #expect(output["hookEventName"] as? String == "PermissionRequest")
        #expect((output["decision"] as? [String: Any])?["behavior"] as? String == "deny")
    }
}
