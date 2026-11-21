import Foundation
import SQLite3
import Stats

private let now = Date(timeIntervalSince1970: 1_751_544_000)
private let state = #"{"thread":"4b1b03c8-62fd-4640-941a-60b8f8e529af","model":"gpt-5.4","input":32,"cached":8,"output":16,"total":48}"#
private let logStart = """
{"type":"session_meta","payload":{"id":"4b1b03c8-62fd-4640-941a-60b8f8e529af"}}
{"type":"turn_context","payload":{"model":"gpt-5.4"}}

"""

private func event(_ n: Int, date: Date = now) -> String {
    let stamp = ISO8601DateFormatter().string(from: date)
    return #"{"type":"event_msg","timestamp":"\#(stamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\#(n * 4),"cached_input_tokens":\#(n),"output_tokens":\#(n * 2),"total_tokens":\#(n * 6)}}}}"# + "\n"
}

private func write(_ contents: String, to url: URL) throws -> UInt64 {
    try Data(contents.utf8).write(to: url)
    return UInt64(contents.utf8.count)
}

private func append(_ contents: String, to url: URL) throws {
    let file = try FileHandle(forWritingTo: url)
    defer { try? file.close() }
    _ = try file.seekToEnd()
    try file.write(contentsOf: Data(contents.utf8))
}

private func makeLedger(_ stats: StatsStore) async -> UsageLedger {
    #if BASELINE
    UsageLedger(stats: stats, progress: await stats.aiFileProgress())
    #else
    UsageLedger(stats: stats)
    #endif
}

private func account(_ folder: URL) -> UsageLedger.Account {
    .init(id: "codex", tool: .codex, folder: folder)
}

private func scan(_ ledger: UsageLedger, folder: URL) -> [UsageLedger.LogFile] {
    let pending = ledger.unread([account(folder)], now: now)
    for file in pending {
        guard !ledger.cancelled.withLock({ $0 }) else { break }
        ledger.read(file, now: now)
    }
    return pending
}

private func perDay(_ stats: StatsStore) async -> [Int64] {
    await stats.aiDaily(accounts: ["codex"], days: 2, now: now).map(\.tokens)
}

private func store(_ url: URL) -> StatsStore {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    return StatsStore(url: url, calendar: utc)
}

private func savedOffset(db url: URL, file: URL) -> UInt64 {
    var db: OpaquePointer?
    precondition(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    precondition(sqlite3_prepare_v2(db, "SELECT offset FROM ai_files WHERE path = ?", -1, &statement, nil) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    return file.path.withCString { path in
        precondition(sqlite3_bind_text(statement, 1, path, -1, nil) == SQLITE_OK)
        precondition(sqlite3_step(statement) == SQLITE_ROW)
        return UInt64(sqlite3_column_int64(statement, 0))
    }
}

private func correctness(_ folder: URL) async throws {
    let manager = FileManager.default
    let sessions = folder.appending(path: "sessions")
    let archived = folder.appending(path: "archived_sessions")
    try manager.createDirectory(at: sessions, withIntermediateDirectories: true)
    try manager.createDirectory(at: archived, withIntermediateDirectories: true)
    let file = sessions.appending(path: "rollout-fixture.jsonl")
    let archivedFile = archived.appending(path: file.lastPathComponent)
    let db = folder.appending(path: "stats.sqlite")
    let yesterday = event(1, date: now.addingTimeInterval(-86_400))
    let stats = store(db)
    let ledger = await makeLedger(stats)
    var offsets: [UInt64] = []
    var daily: [[Int64]] = []

    let end = try write(logStart + yesterday, to: file)
    precondition(scan(ledger, folder: folder).map(\.start) == [0])
    offsets.append(savedOffset(db: db, file: file))
    daily.append(await perDay(stats))
    precondition(offsets.last == end && daily.last == [6, 0])

    let extensionText = yesterday + event(2)
    try append(extensionText, to: file)
    let more = scan(ledger, folder: folder)
    precondition(more.map(\.start) == [end] && CodexUsageLog(state: more[0].state).total == 6)
    offsets.append(savedOffset(db: db, file: file))
    daily.append(await perDay(stats))
    precondition(offsets.last == end + UInt64(extensionText.utf8.count) && daily.last == [6, 6])

    try manager.moveItem(at: file, to: archivedFile)
    precondition(scan(ledger, folder: folder).map(\.start) == [0])
    offsets.append(savedOffset(db: db, file: archivedFile))
    daily.append(await perDay(stats))
    precondition(offsets.last == offsets[1] && daily.last == [6, 6])

    // Trim the archive, forcing the old Codex cumulative state to be discarded and replayed.
    let trimmed = try write(logStart + yesterday, to: archivedFile)
    let reset = scan(ledger, folder: folder)
    precondition(reset.map(\.start) == [0] && reset[0].state.isEmpty)
    offsets.append(savedOffset(db: db, file: archivedFile))
    daily.append(await perDay(stats))
    precondition(offsets.last == trimmed && daily.last == [6, 6])

    // Cancel at the handoff from enumeration to reading. The next module instance must resume.
    try append(event(2), to: archivedFile)
    let queued = ledger.unread([account(folder)], now: now)
    precondition(queued.map(\.start) == [trimmed])
    ledger.cancelled.withLock { $0 = true }
    ledger.read(queued[0], now: now)
    offsets.append(savedOffset(db: db, file: archivedFile))
    precondition(offsets.last == trimmed)
    let restarted = await makeLedger(store(db))
    precondition(scan(restarted, folder: folder).map(\.start) == [trimmed])
    offsets.append(savedOffset(db: db, file: archivedFile))
    daily.append(await perDay(stats))
    precondition(offsets.last == trimmed + UInt64(event(2).utf8.count) && daily.last == [6, 6])

    stats.clear()
    stats.waitForWrites()
    let reopened = store(db)
    let afterClear = await makeLedger(reopened)
    precondition(scan(afterClear, folder: folder).isEmpty)
    daily.append(await perDay(reopened))
    precondition(daily.last == [0, 0])
    try append(event(3), to: archivedFile)
    precondition(scan(afterClear, folder: folder).map(\.start) == [offsets.last!])
    offsets.append(savedOffset(db: db, file: archivedFile))
    daily.append(await perDay(reopened))
    precondition(daily.last == [0, 6])

    try printJSON(["offsets": offsets, "daily": daily])
}

private func prepare(_ folder: URL, stored: Int, eligible: Int, appended: Int) throws {
    let sessions = folder.appending(path: "sessions/2025/07/03")
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    let stats = store(folder.appending(path: "stats.sqlite"))
    let log = logStart + event(8)
    let extra = event(9)
    for index in 0..<stored {
        let prefix = index % 3 == 1 ? "8cdfe322-acda-4b27-a2fe" : "3355a7a0-03c3-442a-b300"
        let number = String(format: "%012d", index)
        let url = sessions.appending(path: "rollout-2025-07-03T10-20-31-\(prefix)-\(number).jsonl")
        let size = UInt64(log.utf8.count)
        if index < eligible {
            _ = try write(index < appended ? log + extra : log, to: url)
        }
        let rowState = state.replacingOccurrences(of: "4b1b03c8-62fd-4640-941a-60b8f8e529af", with: "\(prefix)-\(number)")
        stats.recordAIUsage([], file: url.path, progress: AIFileProgress(size: size, offset: size, state: rowState))
    }
    stats.waitForWrites()
}

private func memoryMiB() -> Double {
    #if os(macOS)
    return Double(AppHealth.footprint()!) / 1_048_576
    #else
    let lines = try! String(contentsOfFile: "/proc/self/smaps_rollup", encoding: .utf8).split(separator: "\n")
    let rss = lines.first { $0.hasPrefix("Rss:") }!.split(whereSeparator: \.isWhitespace)[1]
    return Double(rss)! / 1024
    #endif
}

private func printJSON(_ data: [String: Any]) throws {
    let encoded = try JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])
    print(String(decoding: encoded, as: UTF8.self))
}

@main struct CheckpointProbe {
    static func main() async throws {
        let args = CommandLine.arguments
        let folder = URL(filePath: args[2])
        switch args[1] {
        case "prepare":
            try prepare(folder, stored: Int(args[3])!, eligible: Int(args[4])!, appended: Int(args[5])!)
        case "correctness":
            try await correctness(folder)
        case "scan":
            let stats = store(folder.appending(path: "run.sqlite"))
            let before = memoryMiB()
            let start = DispatchTime.now().uptimeNanoseconds
            let ledger = await makeLedger(stats)
            let first = scan(ledger, folder: folder).count
            let finished = DispatchTime.now().uptimeNanoseconds
            let firstSettled = memoryMiB()
            let again = DispatchTime.now().uptimeNanoseconds
            let repeatFiles = scan(ledger, folder: folder).count
            let repeated = DispatchTime.now().uptimeNanoseconds
            let repeatSettled = memoryMiB()
            let daily = await perDay(stats).reduce(0, +)
            withExtendedLifetime(ledger) {}
            try printJSON([
                "firstMs": Double(finished - start) / 1e6, "repeatMs": Double(repeated - again) / 1e6,
                "firstFiles": first, "repeatFiles": repeatFiles, "dailyTokens": daily,
                "startMiB": before, "firstMiB": firstSettled, "repeatMiB": repeatSettled,
            ])
        default:
            fatalError("Unknown action")
        }
    }
}
