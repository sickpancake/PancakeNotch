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
        for index in 0...256 {
            let file = sessions.appending(path: "rollout-\(index)'s.jsonl")
            try Data("a\nb\n".utf8).write(to: file)
        }
        let old = sessions.appending(path: "rollout-old.jsonl")
        try Data("a\nb\n".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-91 * 86_400)], ofItemAtPath: old.path)
        stats.recordAIUsage([], file: old.path, progress: AIFileProgress(size: 2, offset: 2))

        // Use the paths returned by enumeration, which can resolve the macOS temp directory's symlink.
        let files = ledger.unread([account], now: now)
        #expect(files.count == 257)
        for file in files {
            stats.recordAIUsage([], file: file.url.path,
                                progress: AIFileProgress(size: 4, offset: 2, state: file.url.lastPathComponent))
        }
        let unread = ledger.unread([account], now: now)
        #expect(unread.count == 257)
        for file in unread {
            #expect(file.size == 4 && file.start == 2 && file.state == file.url.lastPathComponent)
        }

        ledger.cancelled.withLock { $0 = true }
        #expect(ledger.unread([account], now: now).isEmpty)
    }
}
