import Foundation
import Testing
@testable import AgentsCore

/// Devin on this Mac (issue #56, local part): Devin CLI and Devin Desktop through their hooks.
@MainActor
struct DevinTests {
    private func center() -> AgentsCenter {
        AgentsCenter(settings: AgentsSettings(defaults: UserDefaults(suiteName: "DevinTests.\(UUID().uuidString)")!))
    }

    private func devinEvent(_ name: String, _ payload: [String: Any] = [:], requestID: Int? = nil,
                            projectDir: String? = "/Users/someone/code/web-app") -> HookEvent {
        var all: [String: Any] = ["session_id": "devin-1", "prompt_id": "p1"]
        all.merge(payload) { _, new in new }
        var event = HookEvent(tool: .devin, name: name, parentPID: 0, payload: all, projectDir: projectDir)
        event.requestID = requestID
        return event
    }

    // MARK: The tool

    @Test func devinIsAnAgentsOnlyToolThatCanBeAnswered() {
        #expect(AgentTool.allCases.contains(.devin))
        #expect(AgentTool.devin.name == "Devin")
        #expect(!AgentTool.devin.hasUsage)
        #expect(AgentTool.devin.canAnswerInNotch)
        #expect(!AgentTool.devin.hasTranscripts)
        #expect(AgentTool(rawValue: "devin") == .devin)
    }

    @Test func devinIsFoundByItsFoldersOrApp() throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let withoutApp = !FileManager.default.fileExists(atPath: "/Applications/Devin.app")
        if withoutApp { #expect(!AgentsDetection.foundTools(home: home).contains(.devin)) }
        try FileManager.default.createDirectory(at: home.appending(path: ".config/devin"), withIntermediateDirectories: true)
        #expect(AgentsDetection.foundTools(home: home).contains(.devin))
        #expect(AccountFinder.devinConfigFile(home: home).path == home.appending(path: ".config/devin/config.json").path)
    }

    @Test func connectTargetsDevinsUserSettings() throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let settings = AgentsSettings(defaults: UserDefaults(suiteName: "DevinTests.\(UUID().uuidString)")!)
        try FileManager.default.createDirectory(at: home.appending(path: ".local/share/devin"), withIntermediateDirectories: true)
        let connector = AgentConnector(settings: settings, home: home)
        let targets = connector.hookFiles(for: .devin)
        #expect(targets.map(\.url.path) == [home.appending(path: ".config/devin/config.json").path])
        #expect(targets.first?.kind == .devin)
        #expect(connector.state(.devin) == .notConnected)
    }

    // MARK: Connect and Disconnect

    @Test func connectWritesDevinsHookFormatAndDisconnectTakesOnlyOursOut() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "config.json")
        let theirs: [String: Any] = [
            "read_config_from": ["claude": true],
            "hooks": ["PreToolUse": [["matcher": "exec", "hooks": [["type": "command", "command": "./check.sh"]]]]],
        ]
        try JSONSerialization.data(withJSONObject: theirs).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)

        try HookFile.update(file, kind: .devin, connect: true)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect((object["read_config_from"] as? [String: Any])?["claude"] as? Bool == true)
        let hooks = try #require(object["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop", "SessionEnd"])
        for (event, value) in hooks {
            let groups = try #require(value as? [[String: Any]])
            let ours = try #require(groups.last)
            #expect(ours["matcher"] as? String == "")
            let handler = try #require((ours["hooks"] as? [[String: Any]])?.first)
            #expect(handler["type"] as? String == "command")
            #expect((handler["command"] as? String)?.hasSuffix("' devin \(event)") == true)
            #expect(handler["async"] == nil)
            #expect(handler["timeout"] as? Int == (event == "PermissionRequest" ? HookHelper.answerTimeout : HookHelper.quickTimeout))
        }
        // The user's own PreToolUse hook is still there, ahead of ours.
        #expect((hooks["PreToolUse"] as? [Any])?.count == 2)
        // Devin keeps this file private; it stays that way.
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)

        try HookFile.update(file, kind: .devin, connect: false)
        let back = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect((back["read_config_from"] as? [String: Any])?["claude"] as? Bool == true)
        let left = try #require(back["hooks"] as? [String: Any])
        #expect(Array(left.keys) == ["PreToolUse"])
        #expect(!(try #require(HookFile.read(file))).contains(HookHelper.marker))
    }

    @Test func connectCreatesDevinsSettingsWhenThereAreNone() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: ".config/devin/config.json")
        try HookFile.update(file, kind: .devin, connect: true)
        #expect(try #require(HookFile.read(file)).contains("devin PermissionRequest"))
        try HookFile.update(file, kind: .devin, connect: false)
        let back = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(back.isEmpty)
    }

    @Test func connectAndDisconnectHandleCommentsInDevinConfig() throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = AccountFinder.devinConfigFile(home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let commented = """
        // Devin user configuration
        {
            /* Block comment before settings */
            "read_config_from": {
                "claude": true, // trailing comma with inline comment
            },
            "endpoint": "https://example.com/*keep*///keep",
            "hooks": {
                // Keep my custom hook
                "PreToolUse": [
                    {"hooks": [{"type": "command", "command": "echo \\"//keep\\""}]}, // custom
                ],
            },
        }
        """
        try Data(commented.utf8).write(to: file)

        let settings = AgentsSettings(defaults: UserDefaults(suiteName: "DevinTests.\(UUID().uuidString)")!)
        let connector = AgentConnector(settings: settings, home: home)
        #expect(connector.state(.devin) == .notConnected)

        try HookFile.update(file, kind: .devin, connect: true)
        #expect(HookFile.isConnected(file, kind: .devin))
        let backup = file.appendingPathExtension("before-pancakenotch")
        #expect(try String(contentsOf: backup, encoding: .utf8) == commented)
        let connected = try #require(DevinHookConfig(Data(contentsOf: file))?.object)
        #expect(connected["endpoint"] as? String == "https://example.com/*keep*///keep")
        #expect((connected["read_config_from"] as? [String: Any])?["claude"] as? Bool == true)
        let connectedText = try #require(HookFile.read(file))
        #expect(connectedText.hasPrefix("// Devin user configuration\n"))
        #expect(connectedText.contains("/* Block comment before settings */"))
        #expect(connectedText.contains("// trailing comma with inline comment"))

        // Adding comments after connecting still reports Connected and allows Disconnect.
        let commentedAfter = "// user note\n" + connectedText.replacingOccurrences(
            of: "\"timeout\":", with: "/* inside generated hook */ \"timeout\":"
        ) + "\n/* trailing */\n"
        try Data(commentedAfter.utf8).write(to: file)
        #expect(HookFile.isConnected(file, kind: .devin))
        connector.refresh()
        #expect(connector.state(.devin) == .connected)

        #expect(connector.disconnect(.devin))
        #expect(connector.state(.devin) == .notConnected)
        let afterDisconnect = try #require(DevinHookConfig(Data(contentsOf: file))?.object)
        #expect(afterDisconnect["endpoint"] as? String == "https://example.com/*keep*///keep")
        let hooks = try #require(afterDisconnect["hooks"] as? [String: [[String: Any]]])
        #expect(Set(hooks.keys) == ["PreToolUse"])
        let handlers = try #require(hooks["PreToolUse"]?.first?["hooks"] as? [[String: String]])
        #expect(handlers.map { $0["command"] } == ["echo \"//keep\""])
        let disconnectedText = try #require(HookFile.read(file))
        for comment in ["// user note", "/* trailing */", "/* Block comment before settings */",
                        "// trailing comma with inline comment", "// Keep my custom hook", "// custom",
                        "/* inside generated hook */"] {
            #expect(disconnectedText.contains(comment))
        }

        for broken in ["{ /* unclosed", #"{"a":1,,}"#, #"{"hooks":{"Stop":false}}"#] {
            try Data(broken.utf8).write(to: file)
            #expect(throws: HookFile.Problem.self) { try HookFile.update(file, kind: .devin, connect: true) }
            #expect(HookFile.read(file) == broken)
        }
    }

    @Test func connectEditsCompactDevinConfigWithoutMovingInlineComments() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "config.json")
        let text = "\u{FEFF}{\"z\":1, \"a\":true /* user setting */}"
        try Data(text.utf8).write(to: file)
        try HookFile.update(file, kind: .devin, connect: true)
        #expect(HookFile.isConnected(file, kind: .devin))
        #expect(HookFile.read(file)?.contains("\"z\":1, \"a\":true, /* user setting */") == true)
        #expect(try Data(contentsOf: file).starts(with: [0xEF, 0xBB, 0xBF]))
        try HookFile.update(file, kind: .devin, connect: false)
        #expect(!HookFile.isConnected(file, kind: .devin))
        #expect(HookFile.read(file)?.contains("\"z\":1, \"a\":true /* user setting */") == true)
    }

    @Test func repeatedConnectAndDisconnectPreserveDevinConfigFormatting() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "config.json")
        let original = """
        {
          "hooks": {
            "PreToolUse": [
              {"hooks": [{"command": "./check.sh"}]} // user hook
            ]
          }
        }
        """
        try Data(original.utf8).write(to: file)
        try HookFile.update(file, kind: .devin, connect: true)
        let connected = try Data(contentsOf: file)
        try HookFile.update(file, kind: .devin, connect: true)
        #expect(try Data(contentsOf: file) == connected)
        try HookFile.update(file, kind: .devin, connect: false)
        #expect(HookFile.read(file) == original)
    }

    // MARK: Answers

    @Test func permissionAnswersUseDevinsFormat() throws {
        let allow = try #require(JSONSerialization.jsonObject(with: Data(LiveAgentSources.decision(allow: true, tool: .devin).utf8)) as? [String: Any])
        #expect(allow as NSDictionary == ["decision": "approve"] as NSDictionary)
        let deny = try #require(JSONSerialization.jsonObject(with: Data(LiveAgentSources.decision(allow: false, tool: .devin).utf8)) as? [String: Any])
        #expect(deny["decision"] as? String == "block")
        #expect(deny["reason"] as? String == "Denied from PancakeNotch.")
        // Claude Code and Codex keep theirs.
        #expect(LiveAgentSources.decision(allow: true, tool: .claude).contains("hookSpecificOutput"))
    }

    @Test func devinsCommandsCanBeReviewedButItsFileToolsGoBack() {
        let review = AgentReview.make(tool: "exec", input: ["command": "npm test", "shell_id": "main"], cwd: "/p", home: "/h")
        #expect(review?.content == .command(lines: ["npm test"]))
        // Devin doesn't publish how these tools' input is laid out: never guess what Allow would approve.
        for tool in ["edit", "write", "read", "notebook_edit", "write_to_process", "mcp__github__create_issue"] {
            #expect(AgentReview.make(tool: tool, input: ["file_path": "/p/a.txt", "old_string": "a", "new_string": "b",
                                                         "content": "x", "command": "y"], cwd: "/p", home: "/h") == nil)
        }
    }

    @Test func devinsToolNamesBecomeSteps() {
        #expect(AgentSteps.step(tool: "exec", input: ["command": "npm test"]) == "Running npm test")
        #expect(AgentSteps.step(tool: "edit", input: ["file_path": "/p/Sources/App.swift"]) == "Editing App.swift")
        #expect(AgentSteps.step(tool: "edit", input: [:]) == "Editing files")
        #expect(AgentSteps.step(tool: "read", input: [:]) == "Reading files")
        #expect(AgentSteps.step(tool: "grep", input: [:]) == "Searching the code")
        #expect(AgentSteps.step(tool: "webfetch", input: [:]) == "Looking on the web")
        #expect(AgentSteps.step(tool: "run_subagent", input: [:]) == "Running a helper agent")
        #expect(AgentSteps.step(tool: "todo_write", input: [:]) == "Planning")
        #expect(AgentSteps.request(tool: "exec", input: ["command": "rm -rf build"]) == "Wants to run: rm -rf build")
    }

    // MARK: A Devin session, hook by hook

    @Test func aDevinSessionFromPromptToFinish() {
        let center = center()
        let sources = LiveAgentSources(center: center)
        defer { sources.stop() }
        let id = "devin:devin-1"

        sources.handle(devinEvent("UserPromptSubmit", ["prompt": "Fix the login redirect\nand add a test"]))
        var thread = center.thread(id)
        #expect(thread?.tool == .devin)
        #expect(thread?.status == .working)
        #expect(thread?.project == "web-app")
        #expect(thread?.lastMessage == "Fix the login redirect")

        sources.handle(devinEvent("PreToolUse", ["tool_name": "exec", "tool_input": ["command": "npm test"]]))
        #expect(center.thread(id)?.step == "Running npm test")

        sources.handle(devinEvent("PermissionRequest", ["tool_name": "exec", "tool_input": ["command": "rm -rf build"]], requestID: 7))
        thread = center.thread(id)
        #expect(thread?.status == .needsYou(.permission))
        #expect(thread?.canAnswer == true)
        #expect(thread?.approval?.review.content == .command(lines: ["rm -rf build"]))

        sources.answer(threadID: id, requestID: 7, allow: true)
        #expect(center.thread(id)?.status == .working)
        #expect(center.thread(id)?.approval == nil)

        sources.handle(devinEvent("PostToolUse", ["tool_name": "exec", "tool_input": ["command": "rm -rf build"],
                                                   "tool_response": ["success": true, "output": "", "error": NSNull()]]))
        #expect(center.thread(id)?.step == "Running rm -rf build")

        sources.handle(devinEvent("Stop", ["stop_hook_active": false]))
        #expect(center.thread(id)?.status == .done)

        sources.handle(devinEvent("SessionEnd", ["reason": "exit"]))
        #expect(center.thread(id)?.status == .done)
        #expect(center.threads.count == 1)
    }

    @Test func aRequestTheNotchCantShowWholeStaysInDevin() {
        let center = center()
        let sources = LiveAgentSources(center: center)
        defer { sources.stop() }
        sources.handle(devinEvent("UserPromptSubmit", ["prompt": "Tidy up"]))
        sources.handle(devinEvent("PreToolUse", ["tool_name": "edit", "tool_input": ["file_path": "/p/a.swift"]]))
        sources.handle(devinEvent("PermissionRequest", ["tool_name": "edit", "tool_input": ["file_path": "/p/a.swift"]], requestID: 3))
        let thread = center.thread("devin:devin-1")
        #expect(thread?.status == .needsYou(.permission))
        #expect(thread?.canAnswer == false)
        #expect(thread?.request == "Wants to edit a.swift")
        // Answering it in Devin's own window lets the tool run: the next hook settles the row.
        sources.handle(devinEvent("PostToolUse", ["tool_name": "edit", "tool_input": ["file_path": "/p/a.swift"]]))
        #expect(center.thread("devin:devin-1")?.status == .working)
        #expect(center.thread("devin:devin-1")?.request == nil)
    }

    @Test func anotherToolCallLeavesAWaitingRequestAlone() {
        let center = center()
        let sources = LiveAgentSources(center: center)
        defer { sources.stop() }
        let id = "devin:devin-1"
        sources.handle(devinEvent("UserPromptSubmit", ["prompt": "Clean"]))
        sources.handle(devinEvent("PermissionRequest", ["tool_name": "exec", "tool_input": ["command": "make clean"]], requestID: 9))
        // A tool running alongside (or a late event from an earlier turn) can't answer it: only the notch can.
        sources.handle(devinEvent("PostToolUse", ["tool_name": "grep", "tool_input": [:], "prompt_id": "p0"]))
        sources.handle(devinEvent("PreToolUse", ["tool_name": "read", "tool_input": [:]]))
        #expect(center.thread(id)?.status == .needsYou(.permission))
        #expect(center.thread(id)?.approval?.review.content == .command(lines: ["make clean"]))
        // Open hands it back to Devin; once answered there, the next tool call shows Devin at work again.
        sources.handBack(threadID: id)
        #expect(center.thread(id)?.canAnswer == false)
        #expect(center.thread(id)?.status == .needsYou(.permission))
        sources.handle(devinEvent("PostToolUse", ["tool_name": "exec", "tool_input": ["command": "make clean"]]))
        #expect(center.thread(id)?.status == .working)
        // A late click on the old request does nothing.
        sources.answer(threadID: id, requestID: 9, allow: true)
        #expect(center.thread(id)?.step == "Running make clean")
    }

    @Test func parallelToolCallsDoNotClearNeedsYouWhileDevinDialogIsOpen() {
        let center = center()
        let sources = LiveAgentSources(center: center)
        defer { sources.stop() }
        let id = "devin:devin-1"

        sources.handle(devinEvent("UserPromptSubmit", ["prompt": "Edit and search"]))
        sources.handle(devinEvent("PreToolUse", ["tool_name": "grep", "tool_input": ["pattern": "foo"]]))
        sources.handle(devinEvent("PreToolUse", ["tool_name": "edit", "tool_input": ["file_path": "/p/b.swift"]]))
        sources.handle(devinEvent("PreToolUse", ["tool_name": "edit", "tool_input": ["file_path": "/p/a.swift"]]))
        sources.handle(devinEvent("PermissionRequest", ["tool_name": "edit", "tool_input": ["file_path": "/p/a.swift"]], requestID: 3))
        #expect(center.thread(id)?.status == .needsYou(.permission))
        #expect(center.thread(id)?.canAnswer == false)
        #expect(center.thread(id)?.request == "Wants to edit a.swift")

        // Calls that were already running leave Needs you intact.
        sources.handle(devinEvent("PostToolUse", ["tool_name": "grep", "tool_input": ["pattern": "foo"]]))
        #expect(center.thread(id)?.status == .needsYou(.permission))
        #expect(center.thread(id)?.request == "Wants to edit a.swift")
        #expect(center.thread(id)?.step == "Searching the code")

        sources.handle(devinEvent("PostToolUse", ["tool_name": "edit", "tool_input": ["file_path": "/p/b.swift"]]))
        #expect(center.thread(id)?.status == .needsYou(.permission))

        // Only the waiting edit's own PostToolUse settles Needs you.
        sources.handle(devinEvent("PostToolUse", ["tool_name": "edit", "tool_input": ["file_path": "/p/a.swift"]]))
        #expect(center.thread(id)?.status == .working)
        #expect(center.thread(id)?.request == nil)
    }

    @Test func parallelToolCallsAfterHandBackDoNotClearNeedsYou() {
        let center = center()
        let sources = LiveAgentSources(center: center)
        defer { sources.stop() }
        let id = "devin:devin-1"

        sources.handle(devinEvent("UserPromptSubmit", ["prompt": "Clean"]))
        sources.handle(devinEvent("PreToolUse", ["tool_name": "read", "tool_input": ["file_path": "/p/a.swift"]]))
        sources.handle(devinEvent("PreToolUse", ["tool_name": "exec", "tool_input": ["command": "make clean"]]))
        sources.handle(devinEvent("PermissionRequest", ["tool_name": "exec", "tool_input": ["command": "make clean"]], requestID: 11))
        sources.handBack(threadID: id)
        #expect(center.thread(id)?.status == .needsYou(.permission))
        #expect(center.thread(id)?.canAnswer == false)

        sources.handle(devinEvent("PostToolUse", ["tool_name": "read", "tool_input": ["file_path": "/p/a.swift"]]))
        #expect(center.thread(id)?.status == .needsYou(.permission))

        sources.handle(devinEvent("PostToolUse", ["tool_name": "exec", "tool_input": ["command": "make clean"]]))
        #expect(center.thread(id)?.status == .working)
    }

    @Test(arguments: [false, true])
    func devinResumesAfterDenialOrRewrittenToolInput(denied: Bool) {
        let center = center()
        let sources = LiveAgentSources(center: center)
        defer { sources.stop() }
        let id = "devin:devin-1"
        sources.handle(devinEvent("UserPromptSubmit", ["prompt": "Edit"]))
        sources.handle(devinEvent("PreToolUse", ["tool_name": "edit", "tool_input": ["file_path": "/p/a.swift"]]))
        sources.handle(devinEvent("PermissionRequest", ["tool_name": "edit", "tool_input": ["file_path": "/p/a.swift"]], requestID: 12))

        let tool = denied ? "read" : "edit"
        let path = denied ? "/p/b.swift" : "/p/a.swift"
        if denied { sources.handle(devinEvent("PreToolUse", ["tool_name": tool, "tool_input": ["file_path": path]])) }
        #expect(center.thread(id)?.status == .needsYou(.permission))
        sources.handle(devinEvent("PostToolUse", ["tool_name": tool, "prompt_id": "old", "tool_input": ["file_path": path]]))
        #expect(center.thread(id)?.status == .needsYou(.permission))
        sources.handle(devinEvent("PostToolUse", ["tool_name": tool, "tool_input": ["file_path": path, "normalized": true]]))
        #expect(center.thread(id)?.status == .working)
        #expect(center.thread(id)?.request == nil)
    }

    @Test func devinCompletionWithChangedInputCanSettleWithoutAStart() {
        let center = center()
        let sources = LiveAgentSources(center: center)
        defer { sources.stop() }
        let id = "devin:devin-1"
        sources.handle(devinEvent("PermissionRequest", ["tool_name": "edit", "tool_input": ["file_path": "/p/a.swift"]], requestID: 13))
        sources.handle(devinEvent("PostToolUse", ["tool_name": "edit", "tool_input": ["file_path": "/p/a.swift", "replace_all": false]]))
        #expect(center.thread(id)?.status == .working)
    }

    @Test(arguments: [false, true])
    func rewrittenCompletionsDistinguishParallelEdits(olderFinishesFirst: Bool) {
        let center = center()
        let sources = LiveAgentSources(center: center)
        defer { sources.stop() }
        let id = "devin:devin-1"

        func edit(_ hook: String, _ file: String, replaceAll: Bool = false, requestID: Int? = nil) {
            let input: [String: Any] = ["file_path": "/p/\(file).swift", "replace_all": replaceAll]
            sources.handle(devinEvent(hook, ["tool_name": "edit", "tool_input": input], requestID: requestID))
        }

        edit("PreToolUse", "older")
        edit("PreToolUse", "approved")
        edit("PermissionRequest", "approved", requestID: 15)
        if olderFinishesFirst {
            edit("PostToolUse", "older", replaceAll: true)
            #expect(center.thread(id)?.status == .needsYou(.permission))
        }
        edit("PostToolUse", "approved", replaceAll: true)
        #expect(center.thread(id)?.status == .working)
        #expect(center.thread(id)?.request == nil)
        if !olderFinishesFirst {
            edit("PostToolUse", "older", replaceAll: true)
            #expect(center.thread(id)?.status == .working)
        }
    }

    @Test(arguments: [false, true])
    func rewrittenCommandSettlesTheApprovedParallelExec(olderFinishesFirst: Bool) {
        let center = center()
        let sources = LiveAgentSources(center: center)
        defer { sources.stop() }
        let id = "devin:devin-1"

        func exec(_ hook: String, _ command: String, requestID: Int? = nil, extra: [String: Any] = [:]) {
            let input = ["command": command, "shell_id": "main"].merging(extra) { _, value in value }
            sources.handle(devinEvent(hook, ["tool_name": "exec", "tool_input": input], requestID: requestID))
        }

        exec("PreToolUse", "npm test")
        exec("PreToolUse", "rm -rf build")
        exec("PermissionRequest", "rm -rf build", requestID: 16)
        sources.handBack(threadID: id)
        #expect(center.thread(id)?.status == .needsYou(.permission))
        #expect(center.thread(id)?.canAnswer == false)

        if olderFinishesFirst {
            exec("PostToolUse", "npm test", extra: ["timeout": 1000])
            #expect(center.thread(id)?.status == .needsYou(.permission))
        }
        exec("PostToolUse", "rm -rf ./build")
        #expect(center.thread(id)?.status == .working)
        #expect(center.thread(id)?.request == nil)
        if !olderFinishesFirst {
            exec("PostToolUse", "npm test")
            #expect(center.thread(id)?.status == .working)
        }
    }

    @Test func identicalParallelCompletionDoesNotSettleTheLaterRequest() {
        let center = center()
        let sources = LiveAgentSources(center: center)
        defer { sources.stop() }
        let id = "devin:devin-1"
        let call: [String: Any] = ["tool_name": "edit", "tool_input": ["file_path": "/p/a.swift"]]
        sources.handle(devinEvent("PreToolUse", call))
        sources.handle(devinEvent("PreToolUse", call))
        sources.handle(devinEvent("PermissionRequest", call, requestID: 14))
        sources.handle(devinEvent("PostToolUse", call))
        #expect(center.thread(id)?.status == .needsYou(.permission))
        sources.handle(devinEvent("PostToolUse", call))
        #expect(center.thread(id)?.status == .working)
    }

    @Test func stopAndNewPromptClearWaitingDevinDialog() {
        let center = center()
        let sources = LiveAgentSources(center: center)
        defer { sources.stop() }
        let id = "devin:devin-1"

        sources.handle(devinEvent("UserPromptSubmit", ["prompt": "Edit"]))
        sources.handle(devinEvent("PermissionRequest", ["tool_name": "edit", "tool_input": ["file_path": "/p/a.swift"]], requestID: 4))
        #expect(center.thread(id)?.status == .needsYou(.permission))

        // Denying in Devin's dialog may end the turn without PostToolUse.
        sources.handle(devinEvent("Stop", ["stop_hook_active": false]))
        #expect(center.thread(id)?.status == .done)

        sources.handle(devinEvent("PermissionRequest", ["tool_name": "edit", "tool_input": ["file_path": "/p/b.swift"]], requestID: 5))
        #expect(center.thread(id)?.status == .needsYou(.permission))
        sources.handle(devinEvent("UserPromptSubmit", ["prompt": "Never mind"]))
        #expect(center.thread(id)?.status == .working)
    }

    @Test func onlyAPlainCommandInDevinsMainShellCanBeAllowedFromTheNotch() {
        func review(_ tool: String, _ input: [String: Any]) -> AgentReview? {
            devinEvent("PermissionRequest", ["tool_name": tool, "tool_input": input]).review
        }
        #expect(review("exec", ["command": "npm test"])?.content == .command(lines: ["npm test"]))
        #expect(review("exec", ["command": "npm test", "shell_id": "main"]) != nil)
        // Another shell may sit in another folder, or have other settings: Devin asks.
        #expect(review("exec", ["command": "pwd", "shell_id": "alternate"]) == nil)
        #expect(review("exec", ["command": "pwd", "cwd": "/"]) == nil)
        #expect(review("exec", ["command": "pwd", "env": ["PATH": "/tmp"]]) == nil)
        // A patch Claude Code or Codex could show is still Devin's to answer.
        let patch = "*** Begin Patch\n*** Add File: hello.txt\n+hi\n*** End Patch"
        #expect(review("apply_patch", ["input": patch, "patch": patch, "command": patch]) == nil)
        #expect(review("write_to_process", ["command": "y"]) == nil)
    }

    @Test func aUsersOwnHookThatMentionsTheHelperIsNeverTakenForOurs() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "config.json")
        let theirs = "printf '%s' 'pancakenotch-hook'"
        try JSONSerialization.data(withJSONObject: ["hooks": ["Stop": [["matcher": "", "hooks": [["type": "command", "command": theirs]]]]]])
            .write(to: file)
        #expect(!HookFile.isConnected(file, kind: .devin))
        try HookFile.update(file, kind: .devin, connect: true)
        #expect(HookFile.isConnected(file, kind: .devin))
        try HookFile.update(file, kind: .devin, connect: false)
        #expect(!HookFile.isConnected(file, kind: .devin))
        #expect(try #require(HookFile.read(file)).contains("printf"))

        #expect(HookFile.isOurs("'/Users/a b/Library/Application Support/PancakeNotch/bin/pancakenotch-hook' devin Stop"))
        #expect(HookFile.isOurs(#"'/Users/o'\''neil/bin/pancakenotch-hook' claude PermissionRequest"#))
        #expect(!HookFile.isOurs("/usr/local/bin/pancakenotch-hook devin Stop"))
        #expect(!HookFile.isOurs("'/x/pancakenotch-hook' devin Stop; rm -rf ~"))
        #expect(!HookFile.isOurs("'/x/pancakenotch-hook' other Stop"))
    }

    @Test func aNewDevinSettingsFileIsPrivate() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: ".config/devin/config.json")
        try HookFile.update(file, kind: .devin, connect: true)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func devinRunningClaudeCodesHooksIsNotAClaudeThread() {
        let center = center()
        let sources = LiveAgentSources(center: center)
        defer { sources.stop() }
        // Devin reads ~/.claude/settings.json's hooks too: its input arrives on Claude Code's entry.
        for name in ["UserPromptSubmit", "PermissionRequest", "Stop"] {
            var event = HookEvent(tool: .claude, name: name, parentPID: 0,
                                  payload: ["session_id": "devin-1", "prompt_id": "p1", "prompt": "hi",
                                            "tool_name": "exec", "tool_input": ["command": "ls"]])
            if name == "PermissionRequest" { event.requestID = 1 }
            #expect(event.isDevinInClaudeHook)
            sources.handle(event)
        }
        #expect(center.threads.isEmpty)
        // Claude Code's own input always names its transcript.
        let claude = HookEvent(tool: .claude, name: "UserPromptSubmit", parentPID: 0,
                               payload: ["session_id": "c1", "prompt_id": "x", "transcript_path": "/t.jsonl", "cwd": "/p", "prompt": "hi"])
        #expect(!claude.isDevinInClaudeHook)
        sources.handle(claude)
        #expect(center.threads.map(\.id) == ["claude:c1"])
    }

    @Test func aHelperFolderIsOnlyUsedWhenDevinSendsNoneAndIsAbsolute() {
        #expect(devinEvent("Stop").cwd == "/Users/someone/code/web-app")
        #expect(devinEvent("Stop", ["cwd": "/elsewhere"]).cwd == "/elsewhere")
        #expect(devinEvent("Stop", projectDir: "relative/dir").cwd == nil)
        #expect(devinEvent("Stop", projectDir: nil).cwd == nil)
    }

    @Test func hidingDevinKeepsItOutAndIsRemembered() {
        let defaults = UserDefaults(suiteName: "DevinTests.\(UUID().uuidString)")!
        let settings = AgentsSettings(defaults: defaults)
        settings.hiddenTools = [.devin]
        #expect(AgentsSettings(defaults: defaults).hiddenTools == [.devin])
        let center = AgentsCenter(settings: settings)
        center.apply(.init(id: "devin:a", tool: .devin, at: .now, status: .needsYou(.permission)))
        #expect(center.threads.isEmpty)
    }
}

/// The real helper (`pancakenotch-hook`) talking to the app's socket, as Devin runs it.
@MainActor
struct DevinHelperSocketTests {
    @MainActor
    private final class Received {
        weak var server: HookServer?
        var events: [HookEvent] = []
        var answer: String?
        func receive(_ event: HookEvent) {
            events.append(event)
            if let id = event.requestID { server?.answer(id, with: answer) }
        }
    }

    private var helper: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: ".build/debug/pancakenotch-hook")
    }

    private func run(_ arguments: [String], payload: [String: Any], environment: [String: String]) async throws -> String {
        let helper = helper
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try await Task.detached {
            let process = Process(), input = Pipe(), output = Pipe()
            process.executableURL = helper
            process.arguments = arguments
            process.environment = environment
            process.standardInput = input
            process.standardOutput = output
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: data)
            try input.fileHandleForWriting.close()
            let result = try output.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            return String(decoding: result, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    private func withServer(_ body: (Received, String) async throws -> Void) async throws {
        let socket = "/tmp/pn-devin-\(UUID().uuidString.prefix(8)).sock"
        let received = Received()
        let server = HookServer(path: socket, onEvent: { received.receive($0) }, onGone: { _ in })
        received.server = server
        #expect(server.start())
        defer { server.stop() }
        #expect(FileManager.default.isExecutableFile(atPath: helper.path))
        try await body(received, socket)
    }

    private let permission: [String: Any] = ["session_id": "devin-1", "prompt_id": "p1", "hook_event_name": "PermissionRequest",
                                             "tool_name": "exec", "tool_input": ["command": "npm test", "shell_id": "main"]]

    @Test func allowAndDenyReachDevinInItsOwnFormat() async throws {
        try await withServer { received, socket in
            let project = "/tmp/My \"quoted\" \\ project ✓"
            let environment = ["PANCAKENOTCH_AGENTS_SOCKET": socket, "DEVIN_PROJECT_DIR": project]
            received.answer = LiveAgentSources.decision(allow: true, tool: .devin)
            let allowed = try await run(["devin", "PermissionRequest"], payload: permission, environment: environment)
            #expect(allowed == #"{"decision":"approve"}"#)
            let event = try #require(received.events.first)
            #expect(event.tool == .devin)
            #expect(event.requestID != nil)
            #expect(event.sessionID == "devin-1")
            #expect(event.cwd == project)
            #expect(event.review?.content == .command(lines: ["npm test"]))

            received.answer = LiveAgentSources.decision(allow: false, tool: .devin)
            let denied = try await run(["devin", "PermissionRequest"], payload: permission, environment: environment)
            let object = try #require(JSONSerialization.jsonObject(with: Data(denied.utf8)) as? [String: Any])
            #expect(object["decision"] as? String == "block")

            // Handed back (Open, or too much to show): Devin asks in its own window.
            received.answer = nil
            #expect(try await run(["devin", "PermissionRequest"], payload: permission, environment: environment) == "{}")
        }
    }

    @Test func reportOnlyHooksDontWait() async throws {
        try await withServer { received, socket in
            let environment = ["PANCAKENOTCH_AGENTS_SOCKET": socket, "DEVIN_PROJECT_DIR": "/tmp/p"]
            for name in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"] {
                let output = try await run(["devin", name], payload: ["session_id": "devin-1", "prompt_id": "p1"], environment: environment)
                #expect(output == "{}")
            }
            try await Task.sleep(for: .milliseconds(200))
            #expect(received.events.map(\.name) == ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"])
            #expect(received.events.allSatisfy { $0.requestID == nil && $0.cwd == "/tmp/p" })

            // The longest folder macOS allows, every byte needing escapes, still arrives whole.
            let long = "/" + String(repeating: "\"", count: 1022)
            _ = try await run(["devin", "Stop"], payload: ["session_id": "devin-1"],
                              environment: ["PANCAKENOTCH_AGENTS_SOCKET": socket, "DEVIN_PROJECT_DIR": long])
            try await Task.sleep(for: .milliseconds(200))
            #expect(received.events.last?.cwd == long)
        }
    }

    @Test func devinRunningClaudesHookStepsAsideAtOnce() async throws {
        try await withServer { received, socket in
            received.answer = LiveAgentSources.decision(allow: true, tool: .claude)
            let devin = ["PANCAKENOTCH_AGENTS_SOCKET": socket, "DEVIN_PROJECT_DIR": "/tmp/p"]
            #expect(try await run(["claude", "PermissionRequest"], payload: permission, environment: devin) == "{}")
            try await Task.sleep(for: .milliseconds(200))
            #expect(received.events.isEmpty)
            // Claude Code's own hook (it sets CLAUDE_PROJECT_DIR) still reaches the app.
            let claude = ["PANCAKENOTCH_AGENTS_SOCKET": socket, "CLAUDE_PROJECT_DIR": "/tmp/p"]
            let output = try await run(["claude", "PermissionRequest"],
                                       payload: ["session_id": "c1", "transcript_path": "/tmp/t.jsonl", "cwd": "/tmp/p",
                                                 "tool_name": "Bash", "tool_input": ["command": "ls"]],
                                       environment: claude)
            #expect(output.contains("hookSpecificOutput"))
            #expect(received.events.map(\.tool) == [.claude])
        }
    }

    @Test func withoutTheAppDevinCarriesOnAsUsual() async throws {
        let output = try await run(["devin", "PermissionRequest"], payload: permission,
                                   environment: ["PANCAKENOTCH_AGENTS_SOCKET": "/tmp/pn-none-\(UUID().uuidString.prefix(8)).sock"])
        #expect(output == "{}")
    }
}
