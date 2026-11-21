import Foundation
import SQLite3
import Stats
import Testing
@testable import AgentsCore

struct ModelPricesTests {
    @Test func namesAreNormalized() {
        #expect(ModelPrices.normalized("claude-sonnet-4-5-20250929") == "claude-sonnet-4-5")
        #expect(ModelPrices.normalized("anthropic/claude-opus-5-5[1m]") == "claude-opus-5-5")
        #expect(ModelPrices.normalized("opus") == "claude-opus-5-5")
    }

    @Test func theLongestKnownNameWins() throws {
        // "claude-opus-4-5" must not be priced as "claude-opus-4".
        let price = try #require(ModelPrices.price(for: "claude-opus-4-5-20251101"))
        #expect(price.input == 5)
        #expect(ModelPrices.price(for: "claude-opus-4-20250514")?.input == 15)
        #expect(ModelPrices.price(for: "some-new-model") == nil)
    }

    @Test func claudeCostCountsCacheWritesAndFastMode() throws {
        // Opus 5.5: $4 in, $20 out, 5-minute writes 1.25× input, 1-hour writes 2×, reads $0.20.
        let cost = try #require(ModelPrices.claudeCost(model: "claude-opus-5-5", input: 1_000_000, output: 1_000_000,
                                                       cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000, cacheRead: 1_000_000, fast: false))
        #expect(abs(cost - (4 + 20 + 5 + 8 + 0.20)) < 0.0001)
        let fast = try #require(ModelPrices.claudeCost(model: "claude-opus-5-5", input: 1_000_000, output: 0,
                                                       cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0, fast: true))
        #expect(abs(fast - 8) < 0.0001)
    }

    @Test func longPromptsUseTheLongPrice() throws {
        let short = try #require(ModelPrices.codexCost(model: "gpt-6.1-sol", input: 100_000, cached: 0, output: 0, prompt: 100_000))
        let long = try #require(ModelPrices.codexCost(model: "gpt-6.1-sol", input: 300_000, cached: 0, output: 0, prompt: 300_000))
        #expect(abs(short - 0.2) < 0.0001)
        #expect(abs(long - 1.2) < 0.0001)
    }

    @Test func displayNames() {
        #expect(ModelPrices.displayName("claude-opus-5-5-20261001") == "Opus 5.5")
        #expect(ModelPrices.displayName("claude-3-5-haiku-20241022") == "Haiku 3.5")
        #expect(ModelPrices.displayName("gpt-6.1-sol") == "GPT-6.1 Sol")
        #expect(ModelPrices.displayName("gpt-5.3-codex") == "GPT-5.3 Codex")
        #expect(ModelPrices.displayName("o4-mini") == "o4-mini")
        #expect(ModelPrices.displayName("codex-auto-review") == "Codex auto review")
    }
}

struct AccountTests {
    @Test func folderNames() {
        #expect(AccountFinder.tool(forFolderNamed: ".claude") == .claude)
        #expect(AccountFinder.tool(forFolderNamed: ".claude-work") == .claude)
        #expect(AccountFinder.tool(forFolderNamed: ".codex_personal") == .codex)
        #expect(AccountFinder.tool(forFolderNamed: ".claude.json") == nil)
        #expect(AccountFinder.tool(forFolderNamed: ".claude-backup") == nil)
        #expect(AccountFinder.tool(forFolderNamed: ".claude-before-update") == nil)
        #expect(AccountFinder.tool(forFolderNamed: ".claudette") == nil)
    }

    @Test func initials() {
        let folder = URL(fileURLWithPath: "/tmp/.claude")
        #expect(AgentAccount(tool: .claude, folder: folder, email: "sam@studio.example").initials == "SS")
        #expect(AgentAccount(tool: .claude, folder: folder, email: "sam@studio.example", name: "Work").initials == "W")
        #expect(AgentAccount(tool: .claude, folder: folder, name: "Work Max").initials == "WM")
        #expect(AgentAccount(tool: .codex, folder: folder).initials == "CO")
    }

    @Test func claudePlans() {
        #expect(AccountIdentity.claudePlan(type: "claude_max", tier: "default_claude_max_5x") == "Max")
        #expect(AccountIdentity.claudePlan(type: "claude_max", tier: "default_claude_max_20x") == "Ultra")
        #expect(AccountIdentity.claudePlan(type: "claude_pro", tier: nil) == "Pro")
        #expect(AccountIdentity.claudePlan(type: nil, tier: nil) == nil)
    }

    @Test func claudeLimitsFromTheSettingsFile() throws {
        let folder = try temporaryFolder()
        let file = folder.appending(path: ".claude.json")
        try Data(#"""
        {"oauthAccount": {"accountUuid": "a", "emailAddress": "sam@studio.example", "organizationType": "claude_pro"},
         "cachedUsageUtilization": {"accountUuid": "a", "fetchedAtMs": 1792617049506, "utilization": {
           "five_hour": {"utilization": 41, "resets_at": "2026-10-22T00:20:00.423502+00:00"},
           "seven_day": {"utilization": 24.5, "resets_at": "2026-10-26T10:00:00+00:00"},
           "seven_day_opus": null}}}
        """#.utf8).write(to: file)
        let identity = try #require(AccountIdentity.claude(configFile: file))
        #expect(identity.email == "sam@studio.example")
        #expect(identity.plan == "Pro")
        #expect(identity.limits.state == .available)
        #expect(identity.limits.limits.map(\.kind) == [.session, .weekly])
        #expect(identity.limits.limits.first?.usedPercent == 41)
        let resets = try #require(identity.limits.limits.first?.resetsAt)
        #expect(abs(resets.timeIntervalSince1970 - 1_792_628_400) < 1)
    }

    @Test func theNewerLimitListIsUnderstoodToo() {
        let limits = AccountIdentity.claudeLimits(["limits": [
            ["kind": "session", "group": "session", "percent": 41, "resets_at": "2026-10-22T00:20:00+00:00"],
            ["kind": "weekly_all", "group": "weekly", "percent": 24],
            ["kind": "weekly_opus", "group": "weekly", "percent": 70, "scope": "opus"],
        ]])
        #expect(limits.map(\.kind) == [.session, .weekly, .weeklyModel("Opus")])
    }

    @Test func anAPIKeyAccountHasNoLimits() throws {
        let file = try temporaryFolder().appending(path: ".claude.json")
        try Data(#"{"primaryApiKey": "not-a-real-key"}"#.utf8).write(to: file)
        let identity = try #require(AccountIdentity.claude(configFile: file))
        #expect(identity.billing == .apiKey)
        #expect(identity.limits.state == .noLimits)
    }

    @Test func codexSignInShowsTheEmailAndPlan() throws {
        let folder = try temporaryFolder()
        let claims = #"{"email":"sam@studio.example","https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}"#
        let payload = Data(claims.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        try Data(#"{"auth_mode": "chatgpt", "tokens": {"id_token": "e30.\#(payload).sig"}}"#.utf8)
            .write(to: folder.appending(path: "auth.json"))
        let identity = AccountIdentity.codex(folder: folder)
        #expect(identity.email == "sam@studio.example")
        #expect(identity.plan == "Plus")
        #expect(identity.billing == .plan)
    }

    @Test func codexWindowsBecomeSessionAndWeekly() throws {
        let limits = try #require(CodexRateLimits([
            "primary": ["used_percent": 12.0, "window_minutes": 300, "resets_at": 1_792_283_320],
            "secondary": ["used_percent": 13.0, "window_minutes": 10080, "resets_at": 1_792_699_461],
            "plan_type": "plus",
        ], at: .now))
        #expect(limits.limits.map(\.kind) == [.session, .weekly])
        let expected: [TimeInterval?] = [5 * 3600, 7 * 86_400]
        #expect(limits.limits.map(\.window) == expected)
        #expect(limits.plan == "plus")
    }
}

struct UsageLogTests {
    @Test func aClaudeMessageBecomesOneRecord() throws {
        let line = Data(#"""
        {"type":"assistant","timestamp":"2026-10-21T19:38:11.392Z","requestId":"req_1","message":{"model":"claude-opus-5-5","id":"msg_1","content":[{"type":"text","text":"never kept"}],"usage":{"input_tokens":2,"cache_creation_input_tokens":20579,"cache_read_input_tokens":10216,"output_tokens":1085,"cache_creation":{"ephemeral_1h_input_tokens":20579,"ephemeral_5m_input_tokens":0},"speed":"standard"}}}
        """#.utf8)
        let record = try #require(ClaudeUsageLog.record(line, account: "claude:/a"))
        #expect(record.id == "msg_1")
        #expect(record.model == "claude-opus-5-5")
        #expect(record.input == 2 && record.output == 1085 && record.cacheWrite == 20579 && record.cacheRead == 10216)
        // 2 × $4 + 1085 × $20 + 20579 × $8 (1-hour writes) + 10216 × $0.20, per million.
        let expected: Double = (8 + 21_700 + 164_632 + 2_043.2) / 1_000_000
        #expect(abs((record.cost ?? 0) - expected) < 0.000001)
    }

    @Test func otherClaudeLinesAreSkipped() {
        let user = Data(#"{"type":"user","message":{"content":"what's the usage of \"assistant\"?"}}"#.utf8)
        let synthetic = Data(#"{"type":"assistant","timestamp":"2026-10-21T19:38:11Z","message":{"model":"<synthetic>","id":"m","usage":{"output_tokens":1}}}"#.utf8)
        #expect(ClaudeUsageLog.record(user, account: "a") == nil)
        #expect(ClaudeUsageLog.record(synthetic, account: "a") == nil)
    }

    @Test func codexRecordsWhatEachRequestAdded() throws {
        var log = CodexUsageLog()
        let meta = Data(#"{"timestamp":"2026-10-17T19:41:40.000Z","type":"session_meta","payload":{"id":"thread-1"}}"#.utf8)
        let context = Data(#"{"timestamp":"2026-10-17T19:41:41.000Z","type":"turn_context","payload":{"model":"gpt-6.1-sol"}}"#.utf8)
        func count(_ input: Int, _ cached: Int, _ output: Int, last: Int) -> Data {
            Data(#"{"timestamp":"2026-10-17T19:41:48.372Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output),"total_tokens":\#(input + output)},"last_token_usage":{"input_tokens":\#(last)}}}}"#.utf8)
        }
        func feed(_ line: Data) -> AIUsageRecord? { log.record(line, account: "x", fallbackThread: "file") }
        #expect(feed(meta) == nil)
        #expect(feed(context) == nil)
        let first = try #require(feed(count(24648, 7296, 266, last: 24648)))
        #expect(first.id == "thread-1:24914")
        #expect(first.input == 24648 - 7296 && first.cacheRead == 7296 && first.output == 266)
        // The same total again (a limits-only update) adds nothing.
        #expect(feed(count(24648, 7296, 266, last: 24648)) == nil)
        let second = try #require(feed(count(56950, 31744, 313, last: 32302)))
        #expect(second.input == (56950 - 24648) - (31744 - 7296) && second.cacheRead == 31744 - 7296 && second.output == 47)
        // Picking up mid-file later carries on from the saved total.
        var resumed = CodexUsageLog(state: log.state)
        let again = resumed.record(count(56950, 31744, 313, last: 32302), account: "x", fallbackThread: "file")
        #expect(again == nil)
        #expect(resumed.thread == "thread-1" && resumed.model == "gpt-6.1-sol")
    }

    @Test func addedCodexFoldersAreNotMistakenForClaudeSessions() throws {
        let home = try temporaryFolder()
        let folder = home.appending(path: "custom-account")
        try FileManager.default.createDirectory(at: folder.appending(path: "sessions/2026"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appending(path: "auth.json"))
        #expect(AccountFinder.tool(of: folder, home: home) == .codex)
        #expect(AccountFinder.find(home: home, added: [folder.path]).map(\.tool) == [.codex])
    }

    @Test func newestLimitsUseTheirObservationTimeRatherThanTheFilesWriteTime() throws {
        let folder = try temporaryFolder()
        let day = folder.appending(path: "sessions/2026/10/21")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        for (name, stamp, percent, modified) in [
            ("rollout-old.jsonl", "2026-10-21T10:00:00Z", 90, 2000.0),
            ("rollout-new.jsonl", "2026-10-21T11:00:00Z", 20, 1000.0)
        ] {
            let file = day.appending(path: name)
            let line = #"{"timestamp":"\#(stamp)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":\#(percent)}}}}"#
            try Data((line + "\n").utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: modified)], ofItemAtPath: file.path)
        }
        #expect(CodexLimitsLog.latest(in: folder)?.primary?.usedPercent == 20)
    }

    @Test func threadIDFromTheFileName() {
        #expect(CodexUsageLog.thread(inFileName: "rollout-2026-10-17T19-41-40-0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b.jsonl")
            == "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b")
    }

    @Test func jsonLinesStopsBeforeAHalfWrittenLine() throws {
        let file = try temporaryFolder().appending(path: "log.jsonl")
        try Data("{\"a\":1}\n{\"b\":2}\n{\"c\":".utf8).write(to: file)
        var lines: [String] = []
        let offset = JSONLines.read(file, from: 0) { lines.append(String(decoding: $0, as: UTF8.self)) }
        #expect(lines == ["{\"a\":1}", "{\"b\":2}"])
        #expect(offset == 16)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("3}\n".utf8))
        try handle.close()
        lines = []
        _ = JSONLines.read(file, from: offset) { lines.append(String(decoding: $0, as: UTF8.self)) }
        #expect(lines == ["{\"c\":3}"])
    }

    @Test func jsonLinesKeepsExactOffsetsAcrossChunks() throws {
        let file = try temporaryFolder().appending(path: "large.jsonl")
        let first = String(repeating: "a", count: 300_000)
        let text = first + "\nsecond\nunfinished"
        try Data(text.utf8).write(to: file)
        var lengths: [Int] = []
        let offset = JSONLines.read(file, from: 0) { lengths.append($0.count) }
        #expect(lengths == [300_000, 6])
        #expect(offset == 300_008)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\nlast\n".utf8))
        try handle.close()
        var lines: [String] = []
        let end = JSONLines.read(file, from: offset) { lines.append(String(decoding: $0, as: UTF8.self)) }
        #expect(lines == ["unfinished", "last"])
        #expect(end == UInt64(text.utf8.count + 6))
    }

    @Test func codexPrefixFilteringPreservesUsageAndByteOffsets() throws {
        let file = try temporaryFolder().appending(path: "rollout-test.jsonl")
        let chunk = 256 * 1024
        let cap = 2 * chunk
        let beforeEmoji = #"{"padding":""#
        func padded(_ head: String, _ tail: String, to length: Int) -> String {
            head + String(repeating: "a", count: length - head.utf8.count - tail.utf8.count) + tail
        }
        func tokens(markerEndsAt: Int, input: Int, length: Int) -> String {
            let prefix = padded(beforeEmoji + "😀",
                                #"","timestamp":"2026-10-17T19:41:48Z","type":"event_msg","payload":{"type":"token_count""#,
                                to: markerEndsAt)
            return padded(prefix + #","info":{"total_token_usage":{"input_tokens":\#(input),"total_tokens":\#(input)}},"padding":""#,
                          #""}}"#, to: length)
        }
        // The next line's first emoji byte is the last byte in the first chunk.
        let meta = padded(#"{"type":"session_meta","payload":{"id":"thread","padding":""#, #""}}"#,
                          to: chunk - beforeEmoji.utf8.count - 2)
        let accepted = tokens(markerEndsAt: 200, input: 8, length: cap)
        let rejected = tokens(markerEndsAt: 201, input: 99, length: 1024)
        let context = #"{"type":"turn_context","payload":{"model":"gpt-6.1-sol"}}"#
        let oversized = tokens(markerEndsAt: 200, input: 999, length: cap + 1)
        let text = [meta, accepted, rejected, context, oversized].joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: file)

        typealias Filter = (length: Int, accepts: (Data) -> Bool)
        func read(filter: Filter?) -> (UInt64, [UInt64], [AIUsageRecord], CodexUsageLog) {
            var offsets: [UInt64] = []
            var records: [AIUsageRecord] = []
            var usage = CodexUsageLog()
            let end = JSONLines.read(file, from: 0, maxLine: cap, spanningLineFilter: filter) { line, offset in
                offsets.append(offset)
                if let record = usage.record(line, account: "x", fallbackThread: "file") { records.append(record) }
            }
            return (end, offsets, records, usage)
        }
        let (baselineEnd, baselineOffsets, baselineRecords, baselineUsage) = read(filter: nil)
        let (end, offsets, records, usage) = read(filter: CodexUsageLog.spanningLineFilter)
        let acceptedStart = UInt64(meta.utf8.count + 1)
        let rejectedStart = acceptedStart + UInt64(cap + 1)
        let contextStart = rejectedStart + UInt64(rejected.utf8.count + 1)
        #expect(baselineOffsets == [0, acceptedStart, rejectedStart, contextStart])
        #expect(offsets == [0, acceptedStart, contextStart])
        #expect(end == baselineEnd && end == UInt64(text.utf8.count))
        #expect(usage == baselineUsage && usage.thread == "thread" && usage.model == "gpt-6.1-sol")
        #expect(records == baselineRecords && records.map(\.input) == [8])
    }

    @Test func rejectedSpanningLineCommitsOnlyAtItsNewline() throws {
        let file = try temporaryFolder().appending(path: "rollout-test.jsonl")
        let rejected = String(repeating: "x", count: 300_000)
        let prefix = "first\n" + rejected
        try Data(prefix.utf8).write(to: file)
        let filter = (length: 200, accepts: { (prefix: Data) in prefix.first != UInt8(ascii: "x") })
        var offsets: [UInt64] = []
        let partial = JSONLines.read(file, from: 0, spanningLineFilter: filter) { _, offset in offsets.append(offset) }
        #expect(offsets == [0])
        #expect(partial == 6)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\nlast\n".utf8))
        try handle.close()
        var checks = 0
        let cancelled = JSONLines.read(file, from: partial, spanningLineFilter: filter, shouldContinue: {
            checks += 1
            return checks < 3 // Stop at the rejected line's newline, in the second chunk.
        }) { _, offset in offsets.append(offset) }
        #expect(cancelled == partial)
        #expect(offsets == [0])

        let end = JSONLines.read(file, from: cancelled, spanningLineFilter: filter) { _, offset in offsets.append(offset) }
        #expect(offsets == [0, UInt64(prefix.utf8.count + 1)])
        #expect(end == UInt64(prefix.utf8.count + 6))
    }

    @Test func oversizedLinesAreSkippedWholeAndCancellationResumesOnALine() throws {
        let file = try temporaryFolder().appending(path: "large.jsonl")
        let text = "first\n" + String(repeating: "a", count: 300_000) + "\nlast\n"
        try Data(text.utf8).write(to: file)
        var lines: [String] = []
        let offset = JSONLines.read(file, from: 0, maxLine: 100, shouldContinue: { lines.isEmpty }) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }
        #expect(lines == ["first"])
        #expect(offset == 6)
        lines = []
        let end = JSONLines.read(file, from: offset, maxLine: 100) { lines.append(String(decoding: $0, as: UTF8.self)) }
        #expect(lines == ["last"])
        #expect(end == UInt64(text.utf8.count))
    }

    @Test func theLedgerReadsEachFileOnceAndKeepsOneRecordPerMessage() async throws {
        let folder = try temporaryFolder()
        let projects = folder.appending(path: "projects/-tmp-app")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now)
        func message(_ id: String, output: Int) -> String {
            #"{"type":"assistant","timestamp":"\#(stamp)","message":{"model":"claude-sonnet-5-5","id":"\#(id)","usage":{"input_tokens":10,"output_tokens":\#(output)}}}"# + "\n"
        }
        let file = projects.appending(path: "session.jsonl")
        // Claude writes a message once per content block.
        try Data((message("m1", output: 5) + message("m1", output: 5) + message("m2", output: 7)).utf8).write(to: file)

        let stats = StatsStore(url: nil)
        let ledger = UsageLedger(stats: stats, progress: [:])
        let account = UsageLedger.Account(id: "claude:\(folder.path)", tool: .claude, folder: folder)
        for log in ledger.unread([account]) { ledger.read(log) }
        #expect(ledger.unread([account]).isEmpty)
        var totals = LiveUsageSources.totals(await stats.aiTotals(accounts: [account.id], days: 1))
        #expect(totals.tokens == 10 + 5 + 10 + 7)
        #expect(totals.models.map(\.name) == ["Sonnet 5.5"])

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(message("m3", output: 1).utf8))
        try handle.close()
        let more = ledger.unread([account])
        #expect(more.count == 1 && more.first?.start ?? 0 > 0)
        for log in more { ledger.read(log) }
        totals = LiveUsageSources.totals(await stats.aiTotals(accounts: [account.id], days: 1))
        #expect(totals.tokens == 32 + 11)

        // Clearing during an import must not bring older messages back; offsets still advance.
        ledger.discardHistory(before: now.addingTimeInterval(0.5))
        stats.clear()
        let future = ISO8601DateFormatter().string(from: now.addingTimeInterval(2))
        let resumed = try FileHandle(forWritingTo: file)
        try resumed.seekToEnd()
        try resumed.write(contentsOf: Data((message("old", output: 4)
            + message("new", output: 10).replacingOccurrences(of: stamp, with: future)).utf8))
        try resumed.close()
        for log in ledger.unread([account]) { ledger.read(log) }
        totals = LiveUsageSources.totals(await stats.aiTotals(accounts: [account.id], days: 1))
        #expect(totals.tokens == 20)
        let restarted = UsageLedger(stats: stats, progress: await stats.aiFileProgress())
        #expect(restarted.unread([account]).isEmpty)
    }
}

struct UsageWriteRecoveryTests {
    @Test func failedIntermediateBatchLeavesTheLogUnreadForRetry() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let projects = folder.appending(path: "projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: false)
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now)
        let lines = (0..<257).map { id in
            #"{"type":"assistant","timestamp":"\#(stamp)","message":{"model":"claude-sonnet-5-5","id":"m\#(id)","usage":{"input_tokens":1,"output_tokens":1}}}"#
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: projects.appending(path: "session.jsonl"))

        let url = folder.appending(path: "stats.sqlite")
        let stats = StatsStore(url: url)
        _ = await stats.aiTotals(accounts: ["test"], days: 1, now: now)
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        try #require(sqlite3_exec(db, """
            CREATE TRIGGER refuse_batch BEFORE INSERT ON ai_usage WHEN NEW.id = 'm0'
            BEGIN SELECT RAISE(ABORT, 'fixture'); END
            """, nil, nil, nil) == SQLITE_OK)

        let ledger = UsageLedger(stats: stats, progress: [:])
        let account = UsageLedger.Account(id: "test", tool: .claude, folder: folder)
        let log = try #require(ledger.unread([account], now: now).first)
        ledger.read(log, now: now)
        #expect(await stats.aiTotals(accounts: ["test"], days: 1, now: now).isEmpty)
        let retry = try #require(ledger.unread([account], now: now).first)
        #expect(retry.start == 0)

        try #require(sqlite3_exec(db, "DROP TRIGGER refuse_batch", nil, nil, nil) == SQLITE_OK)
        ledger.read(retry, now: now)
        #expect(ledger.unread([account], now: now).isEmpty)
        #expect(await stats.aiTotals(accounts: ["test"], days: 1, now: now).first?.tokens == 514)
    }
}

func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "AgentsCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

struct PrivacyAndFreshnessTests {
    @Test func emailsAreHalfHidden() throws {
        let parts = try #require(EmailPrivacy.parts("sam@studio.example"))
        #expect(parts.first == "s" && parts.hidden == "am" && parts.domain == "@studio.example")
        #expect(EmailPrivacy.masked("tester@example.com") == "t•••••@example.com")
        #expect(EmailPrivacy.masked("Work") == "Work")
        #expect(EmailPrivacy.parts("@nothing") == nil)
    }

    @Test func codexAnswersBecomeLimits() throws {
        let rates = try #require(CodexLimitsRequest.limits([
            "rateLimits": ["primary": ["usedPercent": 57, "windowDurationMins": 300, "resetsAt": 1_792_647_539],
                           "secondary": ["usedPercent": 10, "windowDurationMins": 10080, "resetsAt": 1_793_108_662],
                           "planType": "plus"],
        ]))
        #expect(rates.limits.map(\.kind) == [.session, .weekly])
        #expect(rates.limits.map(\.usedPercent) == [57, 10])
        #expect(rates.plan == "plus")
    }

    /// Only OpenAI's own Codex runs as PancakeNotch's child.
    @Test func onlyCodexSignedByOpenAIIsRun() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // A program in Codex's place: Apple's own `true`, and an ad hoc signed copy of it.
        let fake = folder.appending(path: ".local/bin/codex")
        try FileManager.default.createDirectory(at: fake.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: fake)
        #expect(!CodexLimitsRequest.isSignedByOpenAI(URL(fileURLWithPath: "/usr/bin/true")))
        #expect(!CodexLimitsRequest.isSignedByOpenAI(fake))
        #expect(CodexLimitsRequest.binary(home: folder) == nil || CodexLimitsRequest.binary(home: folder) != fake)
        // The same check passes for the team that did sign a program (Apple's binaries have no team: use
        // whatever OpenAI-signed Codex this Mac has, if any).
        if let real = CodexLimitsRequest.binary(home: FileManager.default.homeDirectoryForCurrentUser) {
            #expect(CodexLimitsRequest.isSignedByOpenAI(real))
        }
    }
}
