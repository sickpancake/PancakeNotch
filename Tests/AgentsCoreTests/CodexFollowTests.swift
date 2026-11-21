import Foundation
import Testing
@testable import AgentsCore

@MainActor
struct CodexFollowTests {
    private func line(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
    }
    private func event(_ type: String, at time: String, extra: [String: Any] = [:]) -> String {
        line(["timestamp": "2026-10-28T01:27:\(time)Z", "type": "event_msg",
              "payload": ["type": type, "turn_id": "t1"].merging(extra) { $1 }])
    }

    @Test func aTurnThatEndsOnAnErrorFails() {
        var rollout = CodexRollout()
        _ = rollout.consume(Data(event("task_started", at: "22.778").utf8))
        _ = rollout.consume(Data(event("task_complete", at: "24.980", extra: ["error": ["message": "You've hit your usage limit."]]).utf8))
        #expect(rollout.status == .failed)
        _ = rollout.consume(Data(event("task_started", at: "30.000").utf8))
        _ = rollout.consume(Data(event("task_complete", at: "31.000", extra: ["error": NSNull()]).utf8))
        #expect(rollout.status == .done)
    }

    /// T3 Code's Codex keeps a helper's rollout open; a folder watch hears of its creation only. A turn
    /// that fails sends no Stop hook, so the rollout itself must be followed while the thread works.
    @Test func aWorkingThreadsOpenRolloutIsFollowedToItsFailure() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "CodexFollow-\(UUID().uuidString)", directoryHint: .isDirectory)
        let day = folder.appending(path: "sessions/2026/10/27", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rollout = day.appending(path: "rollout-2026-10-27T21-27-22-helper.jsonl")
        try (line(["timestamp": "2026-10-28T01:27:22.778Z", "type": "session_meta", "payload": ["id": "helper", "source": "vscode"]])
             + event("task_started", at: "22.778")).write(to: rollout, atomically: false, encoding: .utf8)
        let center = AgentsCenter(settings: AgentsSettings(defaults: UserDefaults(suiteName: "CodexFollow.\(UUID())")!))
        let sources = LiveAgentSources(center: center, accounts: [.init(tool: .codex, folder: folder)])
        defer { sources.stop() }
        sources.codexRead(CodexReader().read(changed: [rollout.path], folders: [folder]))
        #expect(center.thread("codex:helper")?.status == .working)
        // The same open file gets the turn's end, with no hook and no folder event.
        try await Task.sleep(for: .milliseconds(200))
        let handle = try FileHandle(forWritingTo: rollout)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(event("task_complete", at: "24.980", extra: ["error": ["message": "Usage limit"]]).utf8))
        for _ in 0..<50 where center.thread("codex:helper")?.status != .failed {
            try await Task.sleep(for: .milliseconds(100))
        }
        try handle.close()
        #expect(center.thread("codex:helper")?.status == .failed)
    }
}
