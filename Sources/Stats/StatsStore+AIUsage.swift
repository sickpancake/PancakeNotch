import Foundation

/// Token counts for one AI message or request (ADR-0037). Only numbers and the model's name: never what
/// was written.
public struct AIUsageRecord: Sendable, Equatable {
    /// The account it belongs to (`AgentAccount.id`).
    public let account: String
    /// Claude: the message ID; Codex: the thread and its running total. A record seen again (Claude
    /// writes a message several times while it streams) replaces the old one if it has more output.
    public let id: String
    public let date: Date
    public let model: String
    public let input: Int64
    public let output: Int64
    public let cacheWrite: Int64
    public let cacheRead: Int64
    /// Pay-per-use price in US dollars; nil when the model has no known price.
    public let cost: Double?

    public init(account: String, id: String, date: Date, model: String, input: Int64, output: Int64,
                cacheWrite: Int64, cacheRead: Int64, cost: Double?) {
        self.account = account
        self.id = id
        self.date = date
        self.model = model
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
        self.cost = cost
    }
}

/// How far one log file has been read.
public struct AIFileProgress: Sendable, Equatable {
    public var size: UInt64
    public var offset: UInt64
    /// Whatever the reader needs to carry on mid-file (Codex: the thread, model and running total).
    public var state: String

    public init(size: UInt64, offset: UInt64, state: String = "") {
        self.size = size
        self.offset = offset
        self.state = state
    }
}

/// One model's share of a range.
public struct AIModelTotal: Sendable, Equatable {
    public let model: String
    public let tokens: Int64
    /// Priced tokens only.
    public let cost: Double
    public let unpricedTokens: Int64
}

public struct AIDayTotal: Sendable, Equatable {
    public let day: Date
    public let tokens: Int64
    public let cost: Double
}

extension StatsStore {
    /// Every log file's progress, read once before catching up.
    public func aiFileProgress() async -> [String: AIFileProgress] {
        await withCheckedContinuation { continuation in
            queue.async { [database] in
                var files: [String: AIFileProgress] = [:]
                database.query("SELECT path, size, offset, state FROM ai_files") { row in
                    files[row.text(0)] = AIFileProgress(size: UInt64(max(0, row.integer(1))), offset: UInt64(max(0, row.integer(2))), state: row.text(3))
                }
                continuation.resume(returning: files)
            }
        }
    }

    /// Saves a file's records and where its reading stopped, together.
    public func recordAIUsage(_ records: [AIUsageRecord], file path: String, progress: AIFileProgress) {
        let keyed = records.map { ($0, dayKey($0.date)) }
        queue.async { [database] in
            database.execute("BEGIN")
            for (record, day) in keyed {
                database.run("""
                    INSERT INTO ai_usage (account, id, day, model, input, output, cache_write, cache_read, cost)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (account, id) DO UPDATE SET
                        day = excluded.day, model = excluded.model, input = excluded.input, output = excluded.output,
                        cache_write = excluded.cache_write, cache_read = excluded.cache_read, cost = excluded.cost
                    WHERE excluded.output > ai_usage.output
                    """, [
                        .text(record.account), .text(record.id), .text(day), .text(record.model),
                        .integer(record.input), .integer(record.output), .integer(record.cacheWrite), .integer(record.cacheRead),
                        record.cost.map(SQLValue.real) ?? .null,
                    ])
            }
            database.run("INSERT OR REPLACE INTO ai_files (path, size, offset, state) VALUES (?, ?, ?, ?)", [
                .text(path), .integer(Int64(clamping: progress.size)), .integer(Int64(clamping: progress.offset)), .text(progress.state),
            ])
            database.execute("COMMIT")
        }
    }

    /// Tokens and money per model over the last `days` local days, for these accounts. Biggest first.
    public func aiTotals(accounts: [String], days: Int, now: Date = .now) async -> [AIModelTotal] {
        guard !accounts.isEmpty else { return [] }
        let from = dayKey(firstDay(of: max(days, 1), now: now))
        let marks = Array(repeating: "?", count: accounts.count).joined(separator: ",")
        return await withCheckedContinuation { continuation in
            queue.async { [database] in
                var totals: [AIModelTotal] = []
                database.query("""
                    SELECT model, SUM(input + output + cache_write + cache_read),
                           COALESCE(SUM(cost), 0),
                           SUM(CASE WHEN cost IS NULL THEN input + output + cache_write + cache_read ELSE 0 END)
                    FROM ai_usage WHERE day >= ? AND account IN (\(marks))
                    GROUP BY model ORDER BY 2 DESC
                    """, [.text(from)] + accounts.map(SQLValue.text)) { row in
                    totals.append(AIModelTotal(model: row.text(0), tokens: row.integer(1), cost: row.real(2), unpricedTokens: row.integer(3)))
                }
                continuation.resume(returning: totals)
            }
        }
    }

    /// Tokens and money for each of the last `days` local days (oldest first, empty days included).
    public func aiDaily(accounts: [String], days: Int, now: Date = .now) async -> [AIDayTotal] {
        let starts = dayStarts(count: max(days, 1), now: now)
        let keys = starts.map(dayKey)
        guard !accounts.isEmpty, let from = keys.first else { return starts.map { AIDayTotal(day: $0, tokens: 0, cost: 0) } }
        let marks = Array(repeating: "?", count: accounts.count).joined(separator: ",")
        return await withCheckedContinuation { continuation in
            queue.async { [database] in
                var byDay: [String: (Int64, Double)] = [:]
                database.query("""
                    SELECT day, SUM(input + output + cache_write + cache_read), COALESCE(SUM(cost), 0)
                    FROM ai_usage WHERE day >= ? AND account IN (\(marks)) GROUP BY day
                    """, [.text(from)] + accounts.map(SQLValue.text)) { row in
                    byDay[row.text(0)] = (row.integer(1), row.real(2))
                }
                continuation.resume(returning: zip(starts, keys).map { start, key in
                    AIDayTotal(day: start, tokens: byDay[key]?.0 ?? 0, cost: byDay[key]?.1 ?? 0)
                })
            }
        }
    }
}
