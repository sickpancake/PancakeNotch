import Foundation
import Testing
@testable import AgentsCore

/// Allow is offered only for what the notch shows whole (ADR-0037, 2026-10-28 amendment).
struct AgentReviewTests {
    /// A project folder with a file, a link to a folder outside it, and a broken link.
    private func project() throws -> (project: String, outside: String) {
        let root = try temporaryFolder()
        let project = root.appending(path: "project"), outside = root.appending(path: "outside")
        try FileManager.default.createDirectory(at: project.appending(path: "Sources"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.appending(path: ".git/hooks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("let a = 1\n".utf8).write(to: project.appending(path: "Sources/App.swift"))
        try FileManager.default.createSymbolicLink(atPath: project.appending(path: "link").path, withDestinationPath: outside.path)
        try FileManager.default.createSymbolicLink(atPath: project.appending(path: "broken").path,
                                                   withDestinationPath: outside.appending(path: "missing.txt").path)
        return (project.path, outside.path)
    }

    private func review(_ tool: String, _ input: [String: Any], cwd: String? = nil) -> AgentReview? {
        AgentReview.make(tool: tool, input: input, cwd: cwd, home: NSHomeDirectory())
    }

    private func change(_ tool: String, _ input: [String: Any], cwd: String) -> AgentReview.FileChange? {
        guard case .edit(let change)? = review(tool, input, cwd: cwd)?.content else { return nil }
        return change
    }

    @Test func commandsShowWholeOrNotAtAll() {
        #expect(review("Bash", ["command": "npm test"])?.content == .command(lines: ["npm test"]))
        #expect(review("exec_command", ["cmd": "rm -rf build\nnpm run build"])?.content == .command(lines: ["rm -rf build", "npm run build"]))
        // 72 columns a line, 3 lines at most.
        let long = String(repeating: "x", count: AgentReview.columns * 3)
        #expect(review("Bash", ["command": long])?.content == .command(lines: Array(repeating: String(repeating: "x", count: AgentReview.columns), count: 3)))
        #expect(review("Bash", ["command": long + "x"]) == nil)
        #expect(review("Bash", ["command": "a\nb\nc\nd"]) == nil)
        // Nothing that could hide or pass for something else, and no argument lists.
        #expect(review("Bash", ["command": "echo hi\u{202E}hs.lru"]) == nil)
        #expect(review("Bash", ["command": "echo\u{200B} hi"]) == nil)
        #expect(review("Bash", ["command": "echo café"]) == nil)
        #expect(review("Bash", ["command": "echo\thi"]) == nil)
        #expect(review("Bash", ["command": "echo hi\rrm -rf ~"]) == nil)
        #expect(review("exec_command", ["cmd": ["rm", "-rf", "build"]]) == nil)
        #expect(review("Bash", ["command": "   "]) == nil)
        #expect(review("WebFetch", ["url": "https://example.com"]) == nil)
        #expect(review("mcp__github__create_issue", ["title": "x"]) == nil)
    }

    @Test func anEditShowsWhereTheFileReallyIsAndTheWholeChange() throws {
        let (project, outside) = try project()
        defer { try? FileManager.default.removeItem(atPath: (project as NSString).deletingLastPathComponent) }
        let edit = try #require(change("Edit", ["file_path": project + "/Sources/App.swift",
                                                "old_string": "func a() {\n    1\n}", "new_string": "func a() {\n    2\n}"], cwd: project))
        #expect(edit.path == ["Sources/App.swift"])
        #expect(edit.action == .change)
        #expect(edit.warning == nil)
        #expect(edit.lines.map(\.kind) == [.context, .removed, .added, .context])
        #expect(edit.lines.map(\.text) == ["func a() {", "    1", "    2", "}"])
        #expect(change("Edit", ["file_path": "Sources/App.swift", "old_string": "a", "new_string": "b", "replace_all": true], cwd: project)?.everyMatch == true)

        // A new file through a linked folder is where the link goes: outside.
        let linked = try #require(change("Write", ["file_path": project + "/link/new.txt", "content": "hi\n"], cwd: project))
        #expect(linked.warning == .outsideProject)
        #expect(linked.action == .create)
        #expect(linked.path.joined().hasSuffix("outside/new.txt"))
        #expect(!linked.path.joined().hasPrefix("link"))
        _ = outside

        // Files that run code later.
        #expect(change("Write", ["file_path": ".git/hooks/pre-commit", "content": "echo hi\n"], cwd: project)?.warning == .runsCode)
        #expect(change("Write", ["file_path": "package.json", "content": "{}\n"], cwd: project)?.warning == .runsCode)
        #expect(change("Write", ["file_path": "Sources/App.swift", "content": "let a = 2\n"], cwd: project)?.action == .replace)

        // No place: a climb, a broken link, a folder, no project.
        #expect(review("Write", ["file_path": project + "/../x.txt", "content": "x"], cwd: project) == nil)
        #expect(review("Write", ["file_path": project + "/broken", "content": "x"], cwd: project) == nil)
        #expect(review("Write", ["file_path": project + "/Sources", "content": "x"], cwd: project) == nil)
        #expect(review("Write", ["file_path": "a.txt", "content": "x"], cwd: nil) == nil)
        #expect(review("NotebookEdit", ["notebook_path": "a.ipynb", "new_source": "x"], cwd: project) == nil)
    }

    @Test func aChangeTooBigOrDisguisedHasNoReview() throws {
        let (project, _) = try project()
        defer { try? FileManager.default.removeItem(atPath: (project as NSString).deletingLastPathComponent) }
        let fits = (1...AgentReview.changeLines).map { "line \($0)" }.joined(separator: "\n")
        #expect(review("Write", ["file_path": "a.txt", "content": fits], cwd: project) != nil)
        #expect(review("Write", ["file_path": "a.txt", "content": fits + "\nmore"], cwd: project) == nil)
        // A long line wraps, and the wrapped lines count.
        let wide = String(repeating: "y", count: AgentReview.columns * AgentReview.changeLines + 1)
        #expect(review("Write", ["file_path": "a.txt", "content": wide], cwd: project) == nil)
        for hidden in ["\u{202E}", "\u{2066}", "\u{200B}", "\u{FEFF}", "\u{00A0}", "\u{0007}", "\r"] {
            #expect(review("Write", ["file_path": "a.txt", "content": "a\(hidden)b"], cwd: project) == nil)
        }
        // Trailing spaces show; tabs are spaces; other languages are fine.
        let shown = try #require(change("Write", ["file_path": "a.txt", "content": "a  \n\tb\nnaïve 日本\n"], cwd: project))
        #expect(shown.lines.map(\.text) == ["a··", "    b", "naïve 日本"])
    }

    @Test func multiEditShowsEveryChange() throws {
        let (project, _) = try project()
        defer { try? FileManager.default.removeItem(atPath: (project as NSString).deletingLastPathComponent) }
        let edit = try #require(change("MultiEdit", ["file_path": "Sources/App.swift", "edits": [
            ["old_string": "a", "new_string": "b"], ["old_string": "c", "new_string": "d"],
        ]], cwd: project))
        #expect(edit.lines.map(\.kind) == [.removed, .added, .gap, .removed, .added])
        #expect(review("MultiEdit", ["file_path": "Sources/App.swift", "edits": [["old_string": "a", "new_string": "a"]]], cwd: project) == nil)
    }

    @Test func codexPatchesForExactlyOneFile() throws {
        let (project, _) = try project()
        defer { try? FileManager.default.removeItem(atPath: (project as NSString).deletingLastPathComponent) }
        func patch(_ body: String) -> AgentReview? { review("apply_patch", ["input": "*** Begin Patch\n\(body)\n*** End Patch\n"], cwd: project) }
        let update = try #require(patch("*** Update File: Sources/App.swift\n@@ func a\n-let a = 1\n+let a = 2"))
        guard case .edit(let change) = update.content else { Issue.record("not an edit"); return }
        #expect(change.action == .change)
        #expect(change.lines.map(\.kind) == [.context, .removed, .added])
        #expect(patch("*** Add File: new.txt\n+hello") != nil)
        #expect(patch("*** Add File: Sources/App.swift\n+exists") == nil)
        #expect(patch("*** Delete File: Sources/App.swift") != nil)
        // Two files, a move, or a marker Codex would find on a trimmed line.
        #expect(patch("*** Update File: a.txt\n-a\n+b\n*** Add File: b.txt\n+c") == nil)
        #expect(patch("*** Update File: Sources/App.swift\n*** Move to: Sources/B.swift\n-a\n+b") == nil)
        #expect(patch("*** Update File: Sources/App.swift\n-a\n+b\n *** Add File: .git/hooks/pre-commit") == nil)
        #expect(patch("*** Update File: Sources/App.swift\nnot a patch line") == nil)
    }

    @Test func readsOnlyInsideTheProject() throws {
        let (project, _) = try project()
        defer { try? FileManager.default.removeItem(atPath: (project as NSString).deletingLastPathComponent) }
        #expect(review("Read", ["file_path": project + "/Sources/App.swift"], cwd: project)?.content == .read(lines: ["Sources/App.swift"]))
        #expect(review("Read", ["file_path": project + "/link/secret.txt"], cwd: project) == nil)
        #expect(review("Read", ["file_path": "/etc/hosts"], cwd: project) == nil)
    }
}

@MainActor
struct PendingApprovalTests {
    private func center() -> AgentsCenter {
        AgentsCenter(settings: AgentsSettings(defaults: UserDefaults(suiteName: "PendingApproval.\(UUID().uuidString)")!))
    }

    private func request(_ command: String, id: Int?) -> HookEvent {
        var event = HookEvent(tool: .claude, name: "PermissionRequest", parentPID: 0,
                              payload: ["session_id": "s", "cwd": "/tmp", "tool_name": "Bash", "tool_input": ["command": command]])
        event.requestID = id
        return event
    }

    /// Sol's finding: a second request that doesn't wait replaced the words, while Allow still answered
    /// the first.
    @Test func laterEventsCannotChangeWhatAllowAnswers() throws {
        let center = center()
        let sources = LiveAgentSources(center: center)
        sources.handle(request("rm -rf ~/Documents", id: 7))
        let shown = try #require(center.threads.first)
        #expect(shown.approval?.review.content == .command(lines: ["rm -rf ~/Documents"]))
        let words = shown.request

        sources.handle(request("echo harmless", id: nil))
        var event = HookEvent(tool: .claude, name: "Notification", parentPID: 0,
                              payload: ["session_id": "s", "notification_type": "permission_prompt", "message": "Claude needs your permission to use Bash"])
        event.requestID = nil
        sources.handle(event)
        let now = try #require(center.threads.first)
        #expect(now.approval == shown.approval)
        #expect(now.request == words)
    }

    @Test func allowAnswersOnlyTheRequestThatWasShown() throws {
        let center = center()
        let sources = LiveAgentSources(center: center)
        sources.handle(request("npm test", id: 1))
        let first = try #require(center.threads.first)
        // A new request takes its place before the click lands.
        sources.handle(request("rm -rf build", id: 2))
        center.allow(first)
        let now = try #require(center.threads.first)
        #expect(now.status == .needsYou(.permission))
        #expect(now.approval?.review.content == .command(lines: ["rm -rf build"]))
        // (The center here isn't started, so its answer goes straight to the sources.)
        sources.answer(threadID: now.id, requestID: try #require(now.approval).requestID, allow: false)
        #expect(center.threads.first?.approval == nil)
        #expect(center.threads.first?.status == .working)
    }

    @Test func aClickOnAnOutdatedCopyDoesNothing() throws {
        let center = AgentsCenter.practice()
        var events: [AgentsPracticeEvent] = []
        center.onPracticeEvent = { events.append($0) }
        let asking = try #require(center.threads.first { $0.canAnswer })
        var outdated = asking
        outdated.approval = PendingApproval(requestID: 99, review: AgentReview(content: .command(lines: ["echo harmless"])))
        center.allow(outdated)
        center.deny(outdated)
        #expect(events.isEmpty)
        center.allow(asking)
        #expect(events == [.allowed])
    }

    @Test func aRequestTheNotchCantShowWholeIsHandedBack() throws {
        let center = center()
        let sources = LiveAgentSources(center: center)
        sources.handle(request(String(repeating: "x", count: 400), id: 3))
        let thread = try #require(center.threads.first)
        #expect(thread.status == .needsYou(.permission))
        #expect(thread.approval == nil)
    }
}
