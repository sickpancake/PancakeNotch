import Foundation
import Stats
import Testing
@testable import AgentsCore

struct UsageCheckpointTests {
    @Test func scanUsesCheckpointsAcrossBatchesAndSkipsOldFiles() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sessions = folder.appending(path: "sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let stats = StatsStore(url: nil)
        let ledger = UsageLedger(stats: stats)
        let account = UsageLedger.Account(id: "codex", tool: .codex, folder: folder)
        let now = Date()
        var expected: [String: AIFileProgress] = [:]

        for index in 0...256 {
            let file = sessions.appending(path: "rollout-\(index)'s.jsonl")
            try Data("a\nb\n".utf8).write(to: file)
            let checkpoint = AIFileProgress(size: 4, offset: 2, state: "state-\(index)")
            stats.recordAIUsage([], file: file.path, progress: checkpoint)
            expected[file.path] = checkpoint
        }
        let old = sessions.appending(path: "rollout-old.jsonl")
        try Data("a\nb\n".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-91 * 86_400)], ofItemAtPath: old.path)
        stats.recordAIUsage([], file: old.path, progress: AIFileProgress(size: 2, offset: 2))

        let unread = ledger.unread([account], now: now)
        #expect(unread.count == expected.count)
        for file in unread {
            #expect(AIFileProgress(size: file.size, offset: file.start, state: file.state) == expected[file.url.path])
        }

        ledger.cancelled.withLock { $0 = true }
        #expect(ledger.unread([account], now: now).isEmpty)
    }
}
