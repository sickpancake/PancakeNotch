import Foundation
import os
import Stats

/// A token count from decoded JSON (0 when it's missing).
private func count(_ value: Any?) -> Int64 {
    (value as? NSNumber)?.int64Value ?? 0
}

/// Token counts from Claude Code's transcripts (`projects/**/*.jsonl`): one record per assistant message
/// (ADR-0037). Claude writes a message once per content block, each time with the same ID and usage;
/// the ledger keeps one. Only the counts, the model's name and the time are taken.
enum ClaudeUsageLog {
    private static let usageMark = Array(#""usage""#.utf8)
    private static let assistantMark = Array(#""type":"assistant""#.utf8)

    static func record(_ line: Data, account: String) -> AIUsageRecord? {
        guard line.contains(usageMark), line.contains(assistantMark),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              // "<synthetic>": a message Claude Code wrote itself, not the model.
              let model = message["model"] as? String, !model.hasPrefix("<"),
              let id = message["id"] as? String ?? object["requestId"] as? String,
              let date = (object["timestamp"] as? String).flatMap(CodexRollout.date) else { return nil }
        let input = count(usage["input_tokens"]), output = count(usage["output_tokens"])
        let read = count(usage["cache_read_input_tokens"]), written = count(usage["cache_creation_input_tokens"])
        guard input + output + read + written > 0 else { return nil }
        // Writes kept for an hour cost more than the usual five minutes.
        let split = usage["cache_creation"] as? [String: Any]
        let hour = split.map { count($0["ephemeral_1h_input_tokens"]) } ?? 0
        let fiveMinutes = split.map { count($0["ephemeral_5m_input_tokens"]) } ?? written
        let cost = ModelPrices.claudeCost(model: model, input: input, output: output, cacheWrite5m: fiveMinutes,
                                          cacheWrite1h: hour, cacheRead: read, fast: usage["speed"] as? String == "fast")
        return AIUsageRecord(account: account, id: id, date: date, model: ModelPrices.normalized(model), input: input,
                             output: output, cacheWrite: written, cacheRead: read, cost: cost)
    }
}

/// Token counts from a Codex rollout. Its `token_count` events carry the thread's running total, so a
/// record is what one request added, named by the thread and the total it reached (the same request
/// read again, from an archived copy, is the same record). The running total is the reader's place,
/// saved with the file's progress.
struct CodexUsageLog: Codable, Equatable {
    var thread: String?
    var model: String?
    var input: Int64 = 0
    var cached: Int64 = 0
    var output: Int64 = 0
    var total: Int64 = 0

    init() {}

    init(state: String) {
        self = (try? JSONDecoder().decode(Self.self, from: Data(state.utf8))) ?? Self()
    }

    var state: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// - Parameter fallbackThread: the thread ID in the file's name, for a file whose first line went missing.
    mutating func record(_ line: Data, account: String, fallbackThread: String) -> AIUsageRecord? {
        let head = String(decoding: line.prefix(200), as: UTF8.self)
        if head.contains(#""type":"session_meta""#) {
            if thread == nil, let payload = Self.payload(line)?.payload {
                thread = payload["id"] as? String ?? payload["session_id"] as? String
            }
            return nil
        }
        if head.contains(#""type":"turn_context""#) {
            if let name = Self.payload(line)?.payload["model"] as? String { model = name }
            return nil
        }
        guard head.contains(#""type":"event_msg""#), head.contains(#""token_count""#),
              let decoded = Self.payload(line),
              let info = decoded.payload["info"] as? [String: Any],
              let totals = info["total_token_usage"] as? [String: Any] else { return nil }
        let new = (input: count(totals["input_tokens"]), cached: count(totals["cached_input_tokens"]),
                   output: count(totals["output_tokens"]), total: count(totals["total_tokens"]))
        defer { (input, cached, output, total) = (new.input, new.cached, new.output, new.total) }
        // The same total again (a limits-only update), or a total that went down (start over from it).
        guard new.total > total, let date = (decoded.object["timestamp"] as? String).flatMap(CodexRollout.date) else { return nil }
        let addedInput = max(0, new.input - input), addedCached = min(addedInput, max(0, new.cached - cached))
        let addedOutput = max(0, new.output - output)
        let fresh = addedInput - addedCached
        let prompt = count((info["last_token_usage"] as? [String: Any])?["input_tokens"])
        let cost = model.flatMap { ModelPrices.codexCost(model: $0, input: fresh, cached: addedCached, output: addedOutput, prompt: prompt) }
        return AIUsageRecord(account: account, id: "\(thread ?? fallbackThread):\(new.total)", date: date,
                             model: model.map(ModelPrices.normalized) ?? "codex", input: fresh, output: addedOutput,
                             cacheWrite: 0, cacheRead: addedCached, cost: cost)
    }

    private static func payload(_ line: Data) -> (object: [String: Any], payload: [String: Any])? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return nil }
        return (object, payload)
    }

    /// "rollout-2026-10-17T19-41-40-0199….jsonl" → "0199…" (the thread's UUID).
    static func thread(inFileName name: String) -> String {
        let base = name.hasSuffix(".jsonl") ? String(name.dropLast(6)) : name
        return base.count > 36 ? String(base.suffix(36)) : base
    }
}

/// Codex's plan limits, from the newest rollouts' last `token_count` lines.
enum CodexLimitsLog {
    /// The newest limits in the account's most recently written rollouts.
    static func latest(in folder: URL, files: Int = 4) -> CodexRateLimits? {
        newestRollouts(in: folder.appending(path: "sessions"), count: files).lazy.compactMap(read).first
    }

    /// The last limits in one rollout's last 256 KB.
    static func read(_ url: URL) -> CodexRateLimits? {
        for line in (JSONLines.tail(of: url, bytes: 256 * 1024) ?? []).reversed()
        where line.contains(#""token_count""#) && line.contains(#""rate_limits""#) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let limits = (object["payload"] as? [String: Any])?["rate_limits"] as? [String: Any],
                  let date = (object["timestamp"] as? String).flatMap(CodexRollout.date),
                  let found = CodexRateLimits(limits, at: date) else { continue }
            return found
        }
        return nil
    }

    /// `sessions/YYYY/MM/DD/rollout-*.jsonl`, newest day first, then newest written first.
    static func newestRollouts(in sessions: URL, count: Int) -> [URL] {
        let fm = FileManager.default
        func children(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.allSatisfy(\.isNumber) }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        var found: [URL] = []
        for year in children(sessions) {
            for month in children(year) {
                for day in children(month) {
                    let files = ((try? fm.contentsOfDirectory(at: day, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                        .filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
                        .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
                        .sorted { $0.1 > $1.1 }
                    found += files.map(\.0)
                    if found.count >= count { return Array(found.prefix(count)) }
                }
            }
        }
        return found
    }
}

/// Reads the token history out of the tools' logs into the statistics file, from where each file's last
/// read stopped, so a file is only ever read once (ADR-0037). Only touched on the usage queue.
final class UsageLedger: @unchecked Sendable {
    struct Account: Sendable {
        let id: String
        let tool: AgentTool
        let folder: URL
    }

    struct LogFile: Sendable {
        let url: URL
        let account: Account
        let size: UInt64
        let start: UInt64
        let state: String

        var unread: UInt64 { size - start }
    }

    private let stats: StatsStore
    private var progress: [String: AIFileProgress]
    /// Set from the main actor to stop a long first read early (AI Usage was switched off).
    let cancelled = OSAllocatedUnfairLock(initialState: false)
    private let discardedBefore = OSAllocatedUnfairLock<Date?>(initialState: nil)

    init(stats: StatsStore, progress: [String: AIFileProgress]) {
        self.stats = stats
        self.progress = progress
    }

    /// The user cleared Statistics during an import. Finish advancing file offsets, but keep only
    /// requests made after that click. The lock orders each batch before or after the database clear.
    func discardHistory(before date: Date) {
        discardedBefore.withLock { $0 = date }
    }

    /// The log files with something unread. Files untouched for longer than the history is kept are skipped.
    func unread(_ accounts: [Account], now: Date = .now) -> [LogFile] {
        let oldest = now.addingTimeInterval(-Double(StatsStore.retentionDays) * 86_400)
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        var files: [LogFile] = []
        for account in accounts {
            let roots = account.tool == .claude ? ["projects"] : ["sessions", "archived_sessions"]
            for root in roots {
                guard let walker = FileManager.default.enumerator(at: account.folder.appending(path: root),
                                                                  includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles]) else { continue }
                for case let url as URL in walker where url.pathExtension == "jsonl" {
                    guard account.tool == .claude || url.lastPathComponent.hasPrefix("rollout-"),
                          let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                          let size = values.fileSize.map(UInt64.init), (values.contentModificationDate ?? now) >= oldest
                    else { continue }
                    let saved = progress[url.path]
                    if saved?.size == size, saved?.offset == size { continue }
                    // A file that got shorter was replaced: read it again (records already saved stay single).
                    let resumes = saved.map { $0.offset <= size } ?? false
                    let start = resumes ? saved?.offset ?? 0 : 0
                    guard start < size else { continue }
                    files.append(LogFile(url: url, account: account, size: size, start: start, state: resumes ? saved?.state ?? "" : ""))
                }
            }
        }
        return files
    }

    /// Reads a file's new lines and saves its records with where reading stopped.
    func read(_ file: LogFile, now: Date = .now) {
        let oldest = now.addingTimeInterval(-Double(StatsStore.retentionDays) * 86_400)
        var records: [String: AIUsageRecord] = [:]
        var codex = file.account.tool == .codex ? CodexUsageLog(state: file.state) : nil
        let fallback = CodexUsageLog.thread(inFileName: file.url.lastPathComponent)
        func flush(_ next: AIFileProgress) {
            let batch = Array(records.values)
            discardedBefore.withLock { cutoff in
                let kept = batch.filter { record in cutoff.map { record.date >= $0 } ?? true }
                stats.recordAIUsage(kept, file: file.url.path, progress: next)
            }
            // Bound both this batch and the database's pending writes during a large first import.
            stats.waitForWrites()
            records.removeAll(keepingCapacity: true)
        }
        let initial = AIFileProgress(size: file.size, offset: file.start, state: file.state)
        let offset = JSONLines.read(file.url, from: file.start, shouldContinue: { !self.cancelled.withLock { $0 } }) { line in
            // Each line's decoded objects go right away, so a big log never piles up in memory.
            autoreleasepool {
                let record = codex != nil
                    ? codex?.record(line, account: file.account.id, fallbackThread: fallback)
                    : ClaudeUsageLog.record(line, account: file.account.id)
                guard let record, record.date >= oldest else { return }
                if record.output >= records[record.id]?.output ?? -1 { records[record.id] = record }
            }
            if records.count >= 256 { flush(initial) }
        }
        let next = AIFileProgress(size: file.size, offset: offset, state: codex?.state ?? "")
        progress[file.url.path] = next
        flush(next)
    }
}

extension Data {
    /// Whether these bytes appear anywhere in the data (a quick look before decoding a line).
    func contains(_ needle: [UInt8]) -> Bool {
        guard !isEmpty, !needle.isEmpty, needle.count <= count else { return false }
        return withUnsafeBytes { haystack in
            needle.withUnsafeBytes { memmem(haystack.baseAddress, haystack.count, $0.baseAddress, $0.count) != nil }
        }
    }
}
