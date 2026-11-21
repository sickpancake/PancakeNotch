import Foundation

@main struct BatchBenchmark {
    static func main() async throws {
        let width = Int(CommandLine.arguments[1])!
        let batches = 80
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date.now
        let store = StatsStore(url: folder.appending(path: "stats.sqlite"))
        // Open and migrate the database outside the timed workload.
        _ = await store.aiTotals(accounts: ["account"], days: 1, now: now)
        let data = (0..<batches).map { batch in
            (0..<width).map { i in
                AIUsageRecord(account: "account", id: "event-\(batch)-\(i)", date: now,
                              model: "example", input: 1, output: 2, cacheWrite: 3, cacheRead: 4,
                              cost: i.isMultiple(of: 2) ? nil : 0.25)
            }
        }
        let start = DispatchTime.now().uptimeNanoseconds
        for (batch, records) in data.enumerated() {
            store.recordAIUsage(records, file: "session.jsonl",
                                progress: AIFileProgress(size: UInt64(batches), offset: UInt64(batch + 1)))
            store.waitForWrites()
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let totals = await store.aiTotals(accounts: ["account"], days: 1, now: now)
        let count = Int64(width * batches)
        precondition(totals.count == 1 && totals[0].tokens == count * 10 && totals[0].cost == Double(count) / 8)
        precondition(totals[0].unpricedTokens == count * 5)
        let checkpoint = store.queue.sync {
            var offset: Int64?
            store.database.query("SELECT offset FROM ai_files WHERE path = 'session.jsonl'") { offset = $0.integer(0) }
            return offset
        }
        precondition(checkpoint == Int64(batches))
        print(elapsed)
    }
}
