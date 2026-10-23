import Foundation
import Testing
@testable import AgentsCore

@MainActor
struct AgentNamesTests {
    private func center() -> AgentsCenter {
        AgentsCenter(settings: AgentsSettings(defaults: UserDefaults(suiteName: "AgentNamesTests.\(UUID().uuidString)")!))
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "AgentNamesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theChosenNameShowsAndFallsBackToTheTitle() throws {
        let center = center()
        let repo = try temporaryFolder().appending(path: "web-app")
        try FileManager.default.createDirectory(at: repo.appending(path: ".git"), withIntermediateDirectories: true)
        try "ref: refs/heads/fix-login\n".write(to: repo.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
        let now = Date()
        center.apply(.init(id: "claude:a", tool: .claude, at: now, title: "Fix the login redirect", cwd: repo.path, status: .working))
        #expect(center.threads.first?.title == "Fix the login redirect")

        center.settings.nameStyle = .lastMessage
        #expect(center.threads.first?.title == "Fix the login redirect")
        center.apply(.init(id: "claude:a", tool: .claude, at: now, lastMessage: "Can you finish this up?\nMore text"))
        #expect(center.threads.first?.title == "Can you finish this up?")

        center.settings.nameStyle = .branch
        #expect(center.threads.first?.title == "fix-login")
        center.settings.nameStyle = .title
        #expect(center.threads.first?.title == "Fix the login redirect")
    }

    @Test func aThreadWithoutATitleGoesByItsFolderUntilItGetsOne() {
        let center = center()
        let now = Date()
        center.apply(.init(id: "codex:a", tool: .codex, at: now, cwd: "/tmp/compiler", status: .working))
        #expect(center.threads.first?.title == "compiler")
        center.apply(.init(id: "codex:a", tool: .codex, at: now, title: "Refactor the parser"))
        center.apply(.init(id: "codex:a", tool: .codex, at: now, cwd: "/tmp/compiler"))
        #expect(center.threads.first?.title == "Refactor the parser")
    }

    @Test func oneLineSkipsWhatTheToolAdded() {
        #expect(AgentNames.oneLine("  Fix   the bug \nsecond line") == "Fix the bug")
        #expect(AgentNames.oneLine("<environment_context>\nhello") == nil)
        #expect(AgentNames.oneLine("# AGENTS.md instructions for /x\n\nDo things") == nil)
        #expect(AgentNames.oneLine(String(repeating: "a", count: 100))?.count == 80)
        #expect(AgentNames.oneLine("   \n") == nil)
    }

    @Test func branchOfAFolderAndAWorktree() throws {
        let root = try temporaryFolder()
        let repo = root.appending(path: "repo")
        try FileManager.default.createDirectory(at: repo.appending(path: ".git/worktrees/wt"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appending(path: "Sources/Deep"), withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(to: repo.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
        #expect(GitBranch.name(cwd: repo.appending(path: "Sources/Deep").path) == "main")

        let worktree = root.appending(path: "wt")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: \(repo.path)/.git/worktrees/wt\n".write(to: worktree.appending(path: ".git"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/feature/names\n".write(to: repo.appending(path: ".git/worktrees/wt/HEAD"), atomically: true, encoding: .utf8)
        #expect(GitBranch.name(cwd: worktree.path) == "feature/names")

        try "0123456789abcdef0123456789abcdef01234567\n".write(to: repo.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
        #expect(GitBranch.name(cwd: repo.path) == nil)
    }

    @Test func claudeTranscriptGivesTheLastPrompt() throws {
        let url = try temporaryFolder().appending(path: "s.jsonl")
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"First question"}}"#,
            #"{"type":"ai-title","aiTitle":"Login fixes"}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Now the redirect"}]}}"#,
            #"{"type":"user","isMeta":true,"message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#,
        ]
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        let details = ClaudeTranscript.details(at: url, wantsStep: false)
        #expect(details.title == "Login fixes")
        #expect(details.lastMessage == "Now the redirect")

        try (lines + [#"{"type":"last-prompt","lastPrompt":"Ship it"}"#]).joined(separator: "\n").appending("\n")
            .write(to: url, atomically: true, encoding: .utf8)
        #expect(ClaudeTranscript.details(at: url, wantsStep: false).lastMessage == "Ship it")
    }

    @Test func codexRolloutGivesTheLastUserMessage() {
        var rollout = CodexRollout()
        let context = #"{"timestamp":"2026-10-22T10:00:00Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>\n</environment_context>"}]}}"#
        let message = #"{"timestamp":"2026-10-22T10:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Can you finish this up?"}]}}"#
        let event = #"{"timestamp":"2026-10-22T10:05:00Z","type":"event_msg","payload":{"type":"user_message","message":"And add tests"}}"#
        let addedContext = rollout.consume(Data(context.utf8))
        #expect(!addedContext)
        let sentMessage = rollout.consume(Data(message.utf8))
        #expect(sentMessage)
        #expect(rollout.lastMessage == "Can you finish this up?")
        let sentEvent = rollout.consume(Data(event.utf8))
        #expect(sentEvent)
        #expect(rollout.lastMessage == "And add tests")
    }
}

struct JSONLinesTests {
    @Test func theEndOfTheLastCompleteLine() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "JSONLinesTests-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("one\ntwo\nhalf".utf8).write(to: url)
        #expect(JSONLines.endOfLastLine(of: url) == 8)
        try Data("no newline".utf8).write(to: url)
        #expect(JSONLines.endOfLastLine(of: url) == 0)
        try Data(("a\n" + String(repeating: "x", count: 200_000)).utf8).write(to: url)
        #expect(JSONLines.endOfLastLine(of: url) == 2)
    }
}
