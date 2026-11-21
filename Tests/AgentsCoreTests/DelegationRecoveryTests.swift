import Foundation
import Testing
@testable import AgentsCore

@MainActor
struct DelegationRecoveryTests {
    private func file(_ lines: [String] = []) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "DelegationRecovery-\(UUID().uuidString).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    private func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    private func call(_ task: String, id: String = "a", title: String = "Review") throws -> String {
        try json(["type": "assistant", "message": ["content": [["type": "tool_use", "id": id,
                    "name": "mcp__t3-code__delegate_task", "input": ["task": task, "title": title]]]]])
    }
    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((text + "\n").utf8))
    }
    private func center() -> AgentsCenter {
        AgentsCenter(settings: AgentsSettings(defaults: UserDefaults(suiteName: "DelegationRecovery.\(UUID())")!))
    }

    @Test func allClaudeBlocksAreReadAndCallIDsDeduplicated() throws {
        let blocks = (1...3).map { ["type": "tool_use", "id": "call\($0)", "name": "mcp__t3-code__delegate_task",
                                  "input": ["task": "Unique task \($0)", "title": "Title \($0)"]] as [String: Any] }
        let line = try json(["type": "assistant", "message": ["content": blocks]])
        let parent = try file([line, line])
        let matches = DelegatedHelpers().resolve(Dictionary(uniqueKeysWithValues: (1...3).map { ("c\($0)", "Unique task \($0)") }), among: [("p", parent)])
        #expect(matches.count == 3)
        #expect(matches["c2"]?.title == "Title 2")
    }

    @Test func ambiguousParentsAndRepeatedCallsAreNeverGuessed() throws {
        let a = try file([call("Same task", id: "a")]), b = try file([call("Same task", id: "b")])
        let matcher = DelegatedHelpers()
        #expect(matcher.parent(of: "Same task", among: [("a", a), ("b", b)]) == nil)
        #expect(matcher.parent(of: "Same task", among: [("b", b), ("a", a)]) == nil)
        try append(call("Same task", id: "second", title: "Different"), to: a)
        #expect(matcher.parent(of: "Same task", among: [("a", a)]) == nil)
    }

    @Test func coldStartRecoversCallsBeyondTheOldTailAndLateCandidates() throws {
        let parent = try file([call("Old task"), String(repeating: " ", count: Int(DelegatedHelpers.firstLook) + 100), call("Recent task", id: "b")])
        let matcher = DelegatedHelpers()
        #expect(matcher.parent(of: "Old task", among: [("p", parent)])?.parentID == "p")
        #expect(matcher.parent(of: "Recent task", among: [("p", parent)])?.parentID == "p")
    }

    @Test func missesRemainRepairableAndPartialLinesAreRetried() throws {
        let parent = try file()
        let matcher = DelegatedHelpers()
        #expect(matcher.parent(of: "Late task", among: [("p", parent)]) == nil)
        let line = try call("Late task")
        let handle = try FileHandle(forWritingTo: parent)
        try handle.seekToEnd(); try handle.write(contentsOf: Data(line.utf8)); try handle.close()
        #expect(matcher.parent(of: "Late task", among: [("p", parent)]) == nil)
        try append("", to: parent)
        #expect(matcher.parent(of: "Late task", among: [("p", parent)])?.parentID == "p")
    }

    @Test func actualExecLiteralAndBatchShapesAreDataOnly() throws {
        let literal = #"text(await tools.mcp__t3_code__delegate_task({title:"Literal",role:"research",task:"Review unique literal"}));"#
        // Sanitized structure of the actual investigation's Codex functions.exec input.
        let batch = #"""
        const common = `Read only.`;
        const tasks = [{title:"First",task:common+` Unique first`},{title:"Second",task:common+` Unique second`}];
        await Promise.all(tasks.map(async task => {
          const result=await tools.mcp__t3_code__delegate_task({...task,target:{providerInstanceId:"codex",model:"example",options:{reasoningEffort:"low"}},role:"research",isolation:"shared",mode:"async"});
          text(result);
        }));
        """#
        var lines: [String] = []
        for (index, script) in [literal, batch].enumerated() {
            lines.append(try json(["type": "response_item", "payload": ["type": "custom_tool_call", "name": "exec", "namespace": "functions", "call_id": "call\(index)", "input": script]]))
            // Actual Codex custom output shape: input_text blocks containing serialized MCP results.
            let outputs = try (0..<(index + 1)).map { child in
                ["type": "input_text", "text": try json(["structuredContent": ["taskId": "task\(child)", "childThreadId": "host-child\(child)"]])]
            }
            lines.append(try json(["type": "response_item", "payload": ["type": "custom_tool_call_output", "call_id": "call\(index)", "output": outputs]]))
        }
        let parent = try file(lines)
        let matches = DelegatedHelpers().resolve(["a": "Review unique literal", "b": "Read only. Unique first", "c": "Read only. Unique second"], among: [("codex:p", parent)])
        #expect(matches.count == 3)
        #expect(matches["b"]?.title == "First")
        #expect(DelegationScript.inputs(#"tools.mcp__t3_code__delegate_task({task:readSecret()})"#).isEmpty)
        #expect(DelegationScript.inputs(#"tools.mcp__t3_code__delegate_task({task:`${readSecret()}`})"#).isEmpty)
        #expect(DelegationScript.inputs(#"const x = 'tools.mcp__t3_code__delegate_task({task:"fake"})';"#).isEmpty)
    }

    @Test func wrappedCallsNeedARecordedSuccessfulHostResult() throws {
        let input = try json(["type": "response_item", "payload": ["type": "custom_tool_call", "name": "exec", "call_id": "exec1",
                          "input": #"if(false) text(await tools.mcp__t3_code__delegate_task({task:"Not actually delegated"}));"#]])
        let parent = try file([input])
        #expect(DelegatedHelpers().parent(of: "Not actually delegated", among: [("p", parent)]) == nil)
    }

    @Test func aSingleCallCannotBeAssignedToTwoIdenticalChildren() throws {
        let parent = try file([call("Identical task")])
        #expect(DelegatedHelpers().resolve(["a": "Identical task", "b": "Identical task"], among: [("p", parent)]).isEmpty)
    }

    @Test func historyRecoversAParentMissingFromTheLiveSessionList() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DelegationHistory-\(UUID())")
        let projects = root.appending(path: "projects/sanitized")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = projects.appending(path: "parent.jsonl")
        try (#"{"sessionId":"saved-parent","type":"user","message":{"content":"Parent question"}}"# + "\n" + call("Historical task") + "\n").write(to: parent, atomically: true, encoding: .utf8)
        let matcher = DelegatedHelpers()
        let history = matcher.history(in: [.init(tool: .claude, folder: root)])
        #expect(matcher.parent(of: "Historical task", among: history)?.parentID == "claude:saved-parent")
    }

    @Test func descendantsCompletedHistoryAndClearFinishedStayTogether() {
        let c = center(), now = Date()
        for id in ["p", "child", "grandchild"] { c.apply(.init(id: id, tool: .claude, at: now, status: .working)) }
        c.setParent(of: "child", to: "p", title: "Child")
        c.setParent(of: "grandchild", to: "child", title: "Grandchild")
        c.apply(.init(id: "p", tool: .claude, at: now, status: .done, quietly: true))
        c.apply(.init(id: "child", tool: .claude, at: now, status: .done, quietly: true))
        #expect(c.threads.map(\.id) == ["p"])
        #expect(Set(c.threads[0].subagents.map(\.id)) == ["child", "grandchild"])
        c.clearFinished()
        #expect(c.thread("child") != nil)
        #expect(c.thread("p") != nil)
        #expect(c.threads.count == 1)
        c.apply(.init(id: "grandchild", tool: .claude, at: now, status: .done, quietly: true))
        #expect(c.threads[0].subagents.count == 2)
        c.clearFinished()
        #expect(c.threads.isEmpty)
    }

    @Test func nestedPermissionIsVisibleAndAlertsEvenWithSubagentsOff() {
        let c = center(), now = Date()
        var alerts = 0
        c.onAlert = { _ in alerts += 1 }
        for id in ["p", "child"] { c.apply(.init(id: id, tool: .codex, at: now, status: .working)) }
        c.setParent(of: "child", to: "p", title: "Child")
        c.settings.showsSubagents = false
        c.apply(.init(id: "child", tool: .codex, at: now, status: .needsYou(.permission), request: .some("Run a command")))
        #expect(c.threads.first?.id == "child")
        #expect(c.attention == .needsYou(count: 1))
        #expect(alerts == 1)
    }

    @Test func helperEvidenceSuppressesOnlyFinishPeekNotOrdinarySessions() {
        let c = center(), now = Date()
        var alerts: [String] = []
        c.onAlert = { alerts.append($0.thread.id) }
        c.noteHelperPrompt("Act as the research sub-agent for this task.\n\nUnique task", for: "helper")
        for id in ["ordinary", "helper"] {
            c.apply(.init(id: id, tool: .claude, at: now.addingTimeInterval(-3600), status: .working))
            c.apply(.init(id: id, tool: .claude, at: now, status: .done))
        }
        #expect(c.threads.count == 2)
        #expect(alerts == ["ordinary"])
    }

    @Test func savedFirstPromptRepairsATruncatedHookPrompt() async throws {
        let c = center()
        let live = LiveAgentSources(center: c)
        defer { live.stop() }
        let task = "Unique long task: " + String(repeating: "x", count: 70 * 1024)
        let parent = try file([call(task)])
        let prompt = "Act as the research sub-agent for this task.\n\n" + task
        let child = try file([json(["type": "user", "message": ["content": prompt]])])
        live.handle(HookEvent(tool: .claude, name: "UserPromptSubmit", parentPID: 0,
                              payload: ["session_id": "p", "transcript_path": parent.path, "prompt": "Parent question"]))
        live.handle(HookEvent(tool: .claude, name: "UserPromptSubmit", parentPID: 0,
                              payload: ["session_id": "child", "transcript_path": child.path, "prompt": prompt]))
        for _ in 0..<300 where c.thread("claude:child")?.parentID == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(c.thread("claude:child")?.parentID == "claude:p")
        #expect(c.threads.count == 1)
    }

    @Test func fileOnlyHelperEvidencePreventsFinishPeeksButOrdinaryFinishesStillPeek() async throws {
        let c = center()
        let sources = LiveAgentSources(center: c)
        defer { sources.stop() }
        let helper = try file([#"{"type":"user","message":{"content":"Act as the research sub-agent for this task.\n\nPending helper task"}}"#])
        let ordinary = try file([#"{"type":"user","message":{"content":"An ordinary conversation"}}"#])
        var alerts: [String] = []
        c.onAlert = { alerts.append($0.thread.id) }
        for (id, path) in [("helper", helper.path), ("ordinary", ordinary.path)] {
            c.apply(.init(id: "claude:\(id)", tool: .claude, at: Date().addingTimeInterval(-3600), status: .working))
            // No prompt hook: the only positive helper evidence is in its provider file. Stop can
            // arrive before asynchronous discovery, and a newer resolver batch can already be queued.
            sources.handle(HookEvent(tool: .claude, name: "Stop", parentPID: 0,
                                     payload: ["session_id": id, "transcript_path": path]))
        }
        for _ in 0..<200 where alerts.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(alerts == ["claude:ordinary"])
        #expect(c.threads.count == 2)
    }

    @Test func coldStartRestoresAnArchivedParentAndCompletedChild() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DelegationColdStart-\(UUID())")
        let projects = root.appending(path: "projects/sanitized")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = projects.appending(path: "parent.jsonl"), child = projects.appending(path: "child.jsonl")
        try (#"{"sessionId":"archived","type":"user","cwd":"/tmp/example","message":{"content":"Parent question"}}"# + "\n" + call("Recovered task") + "\n").write(to: parent, atomically: true, encoding: .utf8)
        try (#"{"sessionId":"child","type":"user","message":{"content":"Act as the research sub-agent for this task.\n\nRecovered task"}}"# + "\n").write(to: child, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 3600)], ofItemAtPath: parent.path)
        let c = center()
        let live = LiveAgentSources(center: c, accounts: [.init(tool: .claude, folder: root)])
        defer { live.stop() }
        live.handle(HookEvent(tool: .claude, name: "UserPromptSubmit", parentPID: 0,
                              payload: ["session_id": "child", "transcript_path": child.path,
                                        "prompt": "Act as the research sub-agent for this task.\n\nRecovered task"]))
        live.handle(HookEvent(tool: .claude, name: "Stop", parentPID: 0, payload: ["session_id": "child"]))
        for _ in 0..<300 where c.thread("claude:child")?.parentID == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(c.threads.map(\.id) == ["claude:archived"])
        #expect(c.threads.first?.project == "example")
        #expect(c.threads.first?.subagents.first?.status == .done)
    }

    @Test func overflowingTheSmallCacheStillBackfillsHistoryForNewCandidates() throws {
        let padding = String(repeating: "x", count: 1024 * 1024 + 100)
        let record = try json(["type": "assistant", "extra": padding, "message": ["content": [
            ["type": "tool_use", "id": "a", "name": "mcp__t3-code__delegate_task", "input": ["task": "First task"]],
            ["type": "tool_use", "id": "b", "name": "mcp__t3-code__delegate_task", "input": ["task": "Second task"]]
        ]]])
        let parent = try file([record]), matcher = DelegatedHelpers()
        #expect(matcher.parent(of: "First task", among: [("p", parent)]) != nil)
        #expect(matcher.parent(of: "Second task", among: [("p", parent)]) != nil)
        // In-place replacement with an equally sized record cannot leave stale positive evidence.
        let replacement = record.replacingOccurrences(of: "Second task", with: "Absent task")
        try replacement.appending("\n").write(to: parent, atomically: false, encoding: .utf8)
        #expect(matcher.parent(of: "Second task", among: [("p", parent)]) == nil)
    }

    @Test func laterCandidatesRereadOnlyTheSavedRecordPositions() throws {
        let filler = try json(["type": "user", "message": ["content": String(repeating: "y", count: 300 * 1024)]])
        let parent = try file([filler, call("Early task", id: "a"), filler, filler, call("Later task", id: "b", title: "Later"), filler])
        let matcher = DelegatedHelpers()
        #expect(matcher.parent(of: "Early task", among: [("p", parent)])?.parentID == "p")
        // A new candidate is matched from the remembered positions, across 256 KB read boundaries.
        #expect(matcher.parent(of: "Later task", among: [("p", parent)])?.title == "Later")
        try append(call("Appended task", id: "c"), to: parent)
        #expect(matcher.resolve(["x": "Early task", "y": "Appended task"], among: [("p", parent)]).count == 2)
    }

    @Test func completionBeforeFlushAndChildBeforeParentAreRepairedByFileEvents() async throws {
        let c = center()
        let live = LiveAgentSources(center: c)
        defer { live.stop() }
        let parent = try file(), child = try file([#"{"type":"user","message":{"content":"Act as the research sub-agent for this task.\n\nLate saved task"}}"#])
        live.handle(HookEvent(tool: .claude, name: "UserPromptSubmit", parentPID: 0,
                              payload: ["session_id": "child", "transcript_path": child.path,
                                        "prompt": "Act as the research sub-agent for this task.\n\nLate saved task"]))
        try await Task.sleep(for: .milliseconds(100))
        live.handle(HookEvent(tool: .claude, name: "UserPromptSubmit", parentPID: 0,
                              payload: ["session_id": "p", "transcript_path": parent.path, "prompt": "Parent task"]))
        for id in ["p", "child"] {
            live.handle(HookEvent(tool: .claude, name: "Stop", parentPID: 0, payload: ["session_id": id]))
        }
        try await Task.sleep(for: .milliseconds(150))
        #expect(c.thread("claude:child")?.parentID == nil)
        try append(call("Late saved task"), to: parent)
        for _ in 0..<300 where c.thread("claude:child")?.parentID == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(c.thread("claude:child")?.parentID == "claude:p")
        #expect(c.threads.count == 1)
        #expect(c.threads[0].subagents.first?.status == .done)
    }
}
