import Foundation
import Testing
@testable import AgentsCore

struct CodexApprovalTests {
    private func transcript(_ lines: String) throws -> URL {
        let folder = try temporaryFolder()
        let url = folder.appending(path: "rollout.jsonl")
        try Data((lines + "\n").utf8).write(to: url)
        return url
    }

    private func event(_ url: URL, turnID: String = "current", mode: String = "default") -> HookEvent {
        HookEvent(tool: .codex, name: "PermissionRequest", parentPID: 0,
                  payload: ["session_id": "thread", "turn_id": turnID, "transcript_path": url.path, "permission_mode": mode])
    }

    @Test(arguments: ["auto_review", "guardian_subagent", "unknown_future_reviewer"])
    func automaticAndUnknownReviewersNeverAskTheUser(reviewer: String) throws {
        let url = try transcript("""
        {"type":"turn_context","payload":{"turn_id":"current","approval_policy":"on-request","approvals_reviewer":"\(reviewer)"}}
        """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(!CodexApprovalRouting.needsUser(event(url)))
    }

    @Test func confirmedHumanReviewWorksForAnyHost() throws {
        let url = try transcript("""
        { "type": "turn_context", "payload": {"turn_id":"current","approval_policy":"on-request","approvals_reviewer":"user"} }
        """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(CodexApprovalRouting.needsUser(event(url)))
        #expect(!CodexApprovalRouting.needsUser(event(url, turnID: "older")))
        #expect(!CodexApprovalRouting.needsUser(event(url, mode: "bypassPermissions")))
    }

    @Test func neverAndMissingReviewersDeferToCodex() throws {
        let url = try transcript("""
        {"type":"turn_context","payload":{"turn_id":"current","approval_policy":"never","approvals_reviewer":"user"}}
        """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(!CodexApprovalRouting.needsUser(event(url)))
        try Data(#"{"type":"turn_context","payload":{"turn_id":"current","approval_policy":"on-request"}}"#.utf8).write(to: url)
        #expect(!CodexApprovalRouting.needsUser(event(url)))
        try Data(#"{"type":"turn_context","payload":{"turn_id":"current","approval_policy":null,"approvals_reviewer":"user"}}"#.utf8).write(to: url)
        #expect(!CodexApprovalRouting.needsUser(event(url)))
        try FileManager.default.removeItem(at: url)
        #expect(!CodexApprovalRouting.needsUser(event(url)))
    }

    @Test func anOlderHumanTurnCannotOverrideTheLatestAutomaticTurn() throws {
        let url = try transcript("""
        {"type":"turn_context","payload":{"turn_id":"old","approval_policy":"on-request","approvals_reviewer":"user"}}
        {"type":"turn_context","payload":{"turn_id":"current","approval_policy":"on-request","approvals_reviewer":"auto_review"}}
        """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(!CodexApprovalRouting.needsUser(event(url)))
        #expect(!CodexApprovalRouting.needsUser(event(url, turnID: "old")))
    }

    @Test func aContextBeyondTheBoundedReadDefersInsteadOfGuessing() throws {
        let url = try transcript("""
        {"type":"turn_context","payload":{"turn_id":"current","approval_policy":"on-request","approvals_reviewer":"user"}}
        """ + "\n" + String(repeating: "x", count: CodexApprovalRouting.tailBytes))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(!CodexApprovalRouting.needsUser(event(url)))
    }
}

@MainActor
struct CodexApprovalSocketTests {
    @MainActor
    private final class Received {
        weak var server: HookServer?
        var events: [HookEvent] = []
        let center: AgentsCenter
        let sources: LiveAgentSources
        var alerts = 0

        init() {
            let center = AgentsCenter(settings: AgentsSettings(defaults: UserDefaults(suiteName: "CodexApprovalSocket.\(UUID().uuidString)")!))
            self.center = center
            self.sources = LiveAgentSources(center: center)
            center.apply(.init(id: "codex:thread", tool: .codex, at: .now, status: .working))
            center.onAlert = { [weak self] _ in self?.alerts += 1 }
        }

        func receive(_ event: HookEvent) {
            events.append(event)
            // The helper's real parent is this test runner inside the frontmost app. Model a
            // background agent so the existing frontmost-app suppression doesn't hide its controls.
            var background = HookEvent(tool: event.tool, name: event.name, parentPID: 0,
                                       payload: ["session_id": event.sessionID ?? "", "turn_id": event.turnID ?? "",
                                                 "transcript_path": event.transcriptPath ?? ""])
            background.requestID = event.requestID
            sources.handle(background)
            if let id = event.requestID { server?.answer(id, with: LiveAgentSources.decision(allow: false, tool: event.tool)) }
        }
    }

    @Test func automaticReviewStepsAsideButHumanReviewStillReachesTheApp() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transcript = folder.appending(path: "rollout.jsonl")
        let socket = "/tmp/pn-approval-\(UUID().uuidString).sock"
        let received = Received()
        let server = HookServer(path: socket, onEvent: { received.receive($0) }, onGone: { _ in })
        received.server = server
        #expect(server.start())
        defer { received.sources.stop(); server.stop() }
        let helper = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: ".build/debug/pancakenotch-hook")
        #expect(FileManager.default.isExecutableFile(atPath: helper.path))

        for reviewer in ["auto_review", "guardian_subagent", "unknown_future_reviewer", "user"] {
            try Data("""
            {"type":"turn_context","payload":{"turn_id":"current","approval_policy":"on-request","approvals_reviewer":"\(reviewer)"}}

            """.utf8).write(to: transcript)
            let payload = try JSONSerialization.data(withJSONObject: ["session_id": "thread", "turn_id": "current", "transcript_path": transcript.path, "permission_mode": "default"])
            let output = try await Task.detached {
                let process = Process(), input = Pipe(), output = Pipe()
                process.executableURL = helper
                process.arguments = ["codex", "PermissionRequest"]
                process.environment = ["PANCAKENOTCH_AGENTS_SOCKET": socket]
                process.standardInput = input
                process.standardOutput = output
                try process.run()
                try input.fileHandleForWriting.write(contentsOf: payload)
                try input.fileHandleForWriting.close()
                let data = try output.fileHandleForReading.readToEnd() ?? Data()
                process.waitUntilExit()
                return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }.value
            if reviewer != "user" {
                #expect(output == "{}")
                #expect(received.events.isEmpty)
                #expect(received.center.attention == .working(count: 1))
                #expect(received.alerts == 0)
            } else {
                #expect(output.contains("deny"))
                #expect(received.events.count == 1)
                #expect(received.events.first?.requestID != nil)
                #expect(received.center.thread("codex:thread")?.status == .needsYou(.permission))
                #expect(received.center.thread("codex:thread")?.canAnswer == true)
                #expect(received.alerts == 1)
            }
        }
    }
}
