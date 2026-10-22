import Foundation
import Testing
import SQLite3
@testable import AgentsCore

@MainActor
struct SubagentCenterTests {
    private func center() -> AgentsCenter {
        AgentsCenter(settings: AgentsSettings(defaults: UserDefaults(suiteName: "SubagentCenterTests.\(UUID().uuidString)")!))
    }

    private func subagent(_ id: String, _ status: AgentStatus, since: Date) -> AgentSubagent {
        AgentSubagent(id: id, title: id, status: status, statusSince: since)
    }

    @Test func subagentsSitUnderTheirThreadAndDontCount() {
        let center = center()
        let now = Date()
        center.apply(.init(id: "claude:main", tool: .claude, at: now, status: .working))
        center.setSubagents([subagent("claude:b", .working, since: now), subagent("claude:a", .working, since: now.addingTimeInterval(-60)),
                             subagent("claude:old", .done, since: now)], of: "claude:main")
        #expect(center.threads.map(\.id) == ["claude:main"])
        #expect(center.threads.first?.subagents.map(\.id) == ["claude:a", "claude:b"])
        #expect(center.attention == .working(count: 1))
        center.apply(.init(id: "claude:main", tool: .claude, at: now, status: .done))
        center.setSubagents([subagent("claude:late", .working, since: now)], of: "claude:main")
        #expect(center.thread("claude:main")?.subagents.isEmpty == true)
        // A thread that isn't known yet gets nothing.
        center.setSubagents([subagent("claude:c", .working, since: now)], of: "claude:other")
        #expect(center.thread("claude:other") == nil)
    }

    @Test func aFinishedSubagentLeavesAndAnEndedSessionTakesTheRest() {
        let center = center()
        let now = Date()
        center.apply(.init(id: "codex:main", tool: .codex, at: now, status: .working))
        center.updateSubagent(subagent("codex:s1", .working, since: now), of: "codex:main")
        center.updateSubagent(subagent("codex:s2", .working, since: now), of: "codex:main")
        center.updateSubagent(subagent("codex:s1", .done, since: now), of: "codex:main")
        #expect(center.thread("codex:main")?.subagents.map(\.id) == ["codex:s2"])
        center.ended("codex:main", at: now)
        #expect(center.thread("codex:main")?.subagents.isEmpty == true)
    }
    @Test func codexHelpersArrivingFirstAndNestedHelpersJoinTheMainThread() {
        let center = center()
        let sources = LiveAgentSources(center: center)
        let now = Date()
        func update(_ id: String, parent: String? = nil, status: AgentStatus = .working) -> CodexReader.ThreadUpdate {
            .init(threadID: id, folder: URL(fileURLWithPath: "/tmp/codex"), cwd: "/tmp/app", title: id,
                  status: status, statusAt: now, step: nil, hostBundleID: nil, parentThreadID: parent,
                  modified: now, isCatchUp: false)
        }
        sources.codexRead([update("helper", parent: "main"), update("nested", parent: "helper")])
        #expect(center.threads.isEmpty)
        sources.codexRead([update("main")])
        #expect(center.threads.map(\.id) == ["codex:main"])
        #expect(Set(center.thread("codex:main")?.subagents.map(\.id) ?? []) == ["codex:helper", "codex:nested"])
        sources.codexRead([update("helper", parent: "main", status: .done)])
        #expect(center.thread("codex:main")?.subagents.map(\.id) == ["codex:nested"])
        sources.handle(HookEvent(tool: .codex, name: "Stop", parentPID: 0, payload: ["session_id": "nested"]))
        #expect(center.thread("codex:main")?.subagents.isEmpty == true)
        sources.codexRead([update("main", status: .done)])
        #expect(center.thread("codex:main")?.subagents.isEmpty == true)
        sources.stop()
    }

}

struct SubagentFilesTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "SubagentFilesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url.appending(path: "s1/subagents"), withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    @Test func claudeSubagentsAreTheUnfinishedRecentOnes() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let subagents = root.appending(path: "s1/subagents")
        for name in ["agent-a", "agent-b", "agent-c", "agent-d"] { try write("{}\n", to: subagents.appending(path: "\(name).jsonl")) }
        try write(#"{"agentType":"general-purpose","description":"Review the parser"}"#, to: subagents.appending(path: "agent-a.meta.json"))
        try write(#"{"description":"Done already","finished":true}"#, to: subagents.appending(path: "agent-b.meta.json"))
        try write(#"{"description":"Went quiet"}"#, to: subagents.appending(path: "agent-c.meta.json"))
        try write(#"{"agentType":"Explore","description":""}"#, to: subagents.appending(path: "agent-d.meta.json"))
        let quiet = Date().addingTimeInterval(-ClaudeSubagents.quietLimit - 60)
        try FileManager.default.setAttributes([.modificationDate: quiet], ofItemAtPath: subagents.appending(path: "agent-c.jsonl").path)

        let working = ClaudeSubagents.working(transcript: root.appending(path: "s1.jsonl")).sorted { $0.id < $1.id }
        #expect(working.map(\.id) == ["claude:agent-a", "claude:agent-d"])
        #expect(working.map(\.title) == ["Review the parser", "Explore"])
        #expect(working.allSatisfy { $0.status == .working })
    }

    @Test func changedFilesPointToTheirSession() {
        #expect(ClaudeSubagents.sessionID(changed: "/p/proj/s1.jsonl") == "s1")
        #expect(ClaudeSubagents.sessionID(changed: "/p/proj/s1/subagents/agent-a.jsonl") == "s1")
        #expect(ClaudeSubagents.sessionID(changed: "/p/proj/s1/subagents/agent-a.meta.json") == "s1")
        #expect(ClaudeSubagents.sessionID(changed: "/p/proj/notes.txt") == nil)
    }

    @Test func theTranscriptsTitleNamesTheThread() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let transcript = root.appending(path: "s1.jsonl")
        try write("""
        {"type":"ai-title","aiTitle":"Old title","sessionId":"s1"}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}
        { "sessionId": "s1", "type": "ai-title", "aiTitle": "Fix the login redirect" }

        """, to: transcript)
        let details = ClaudeTranscript.details(at: transcript, wantsStep: true)
        #expect(details.title == "Fix the login redirect")
        #expect(details.step == "Running npm test")
        #expect(ClaudeTranscript.details(at: transcript, wantsStep: false).step == nil)

        // A name the user gave it wins, wherever it is in the tail.
        try write("""
        {"type":"custom-title","customTitle":"Login work","sessionId":"s1"}
        { "sessionId": "s1", "type": "ai-title", "aiTitle": "Fix the login redirect" }

        """, to: transcript)
        #expect(ClaudeTranscript.details(at: transcript, wantsStep: false).title == "Login work")
    }

    @Test func aFolderNameIsntATitle() throws {
        let derived = try #require(ClaudeSession(data: Data(#"{"pid": 1, "sessionId": "s", "status": "busy", "name": "pancakenotch-5a", "nameSource": "derived"}"#.utf8)))
        #expect(derived.name == nil)
        let named = try #require(ClaudeSession(data: Data(#"{"pid": 1, "sessionId": "s", "status": "busy", "name": "Login work", "nameSource": "user"}"#.utf8)))
        #expect(named.name == "Login work")
    }

    @Test func codexSpawnedAgentsKnowTheirParent() {
        var rollout = CodexRollout()
        func feed(_ text: String) -> Bool { rollout.consume(Data(text.utf8)) }
        #expect(feed(#"{"timestamp":"2026-10-17T19:41:40.000Z","type":"session_meta","payload":{"id":"t2","cwd":"/tmp/app","source":{"subagent":{"thread_spawn":{"parent_thread_id":"t1","depth":1,"agent_path":"/root/kimi_qwen_signals","agent_nickname":"Copernicus","agent_role":null}}}}}"#))
        #expect(rollout.isHelper && rollout.parentThreadID == "t1")
        #expect(rollout.subagentTitle == "Copernicus · kimi qwen signals")

        var reviewer = CodexRollout()
        _ = reviewer.consume(Data(#"{"timestamp":"2026-10-17T19:41:40.000Z","type":"session_meta","payload":{"id":"t3","source":{"subagent":{"other":"guardian"}}}}"#.utf8))
        #expect(reviewer.isHelper && reviewer.parentThreadID == nil)
    }
}

struct CodexTitleRefreshTests {
    @Test func reopeningRefreshesARenameAndLaterRolloutReadsKeepIt() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "CodexTitles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var db: OpaquePointer?
        #expect(sqlite3_open(folder.appending(path: "state_5.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TABLE threads (id TEXT, title TEXT, name TEXT); INSERT INTO threads VALUES ('t1', 'Conversation title', '');", nil, nil, nil) == SQLITE_OK)
        let reader = CodexReader()
        #expect(reader.refreshTitle(folder: folder, threadID: "t1") == "Conversation title")
        #expect(sqlite3_exec(db, "UPDATE threads SET name = 'My renamed conversation';", nil, nil, nil) == SQLITE_OK)
        #expect(reader.refreshTitle(folder: folder, threadID: "t1") == "My renamed conversation")
        let log = folder.appending(path: "rollout-test.jsonl")
        try Data("""
        {"timestamp":"2026-10-22T14:00:00Z","type":"session_meta","payload":{"id":"t1","cwd":"/tmp/app"}}
        {"timestamp":"2026-10-22T14:00:01Z","type":"event_msg","payload":{"type":"task_started"}}

        """.utf8).write(to: log)
        let updates = reader.read(changed: [log.path], folders: [folder])
        #expect(updates.first?.title == "My renamed conversation")
        // The old schema, without a separate name, still works.
        #expect(sqlite3_exec(db, "ALTER TABLE threads DROP COLUMN name;", nil, nil, nil) == SQLITE_OK)
        #expect(reader.refreshTitle(folder: folder, threadID: "t1") == "Conversation title")
    }
}
