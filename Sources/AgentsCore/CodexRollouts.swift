import Foundation
import SQLite3

/// Codex's plan limits as one rollout last reported them (`token_count` → `rate_limits`).
struct CodexRateLimits: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let usedPercent: Double
        let windowMinutes: Double?
        let resetsAt: Date?
    }

    let primary: Window?
    let secondary: Window?
    let plan: String?
    let seenAt: Date

    init?(_ object: [String: Any], at date: Date) {
        func window(_ key: String) -> Window? {
            guard let value = object[key] as? [String: Any], let used = AccountIdentity.number(value["used_percent"]) else { return nil }
            return Window(usedPercent: used, windowMinutes: AccountIdentity.number(value["window_minutes"]),
                          resetsAt: AccountIdentity.number(value["resets_at"]).map { Date(timeIntervalSince1970: $0) })
        }
        primary = window("primary")
        secondary = window("secondary")
        guard primary != nil || secondary != nil else { return nil }
        plan = object["plan_type"] as? String
        seenAt = date
    }

    /// Session (the 5-hour window) and Weekly, whichever way round Codex reports them.
    var limits: [UsageLimit] {
        [primary, secondary].compactMap { $0 }.map { window in
            let minutes = window.windowMinutes ?? 0
            let kind: UsageLimit.Kind = minutes >= 24 * 60 ? .weekly : .session
            return UsageLimit(kind: kind, usedPercent: window.usedPercent, resetsAt: window.resetsAt,
                              window: minutes > 0 ? minutes * 60 : nil)
        }
        .sorted { $0.kind == .session && $1.kind != .session }
    }
}

/// What one Codex rollout (`sessions/YYYY/MM/DD/rollout-…jsonl`) says about its thread, kept up to date
/// as lines are added (ADR-0037). Only short lines and the first line are decoded; long tool output is
/// skipped by looking at each line's start.
struct CodexRollout: Sendable {
    var offset: UInt64 = 0
    var threadID: String?
    var cwd: String?
    var originator: String?
    /// A helper thread (a spawned subagent, an automatic review): not shown on its own.
    var isHelper = false
    var status: AgentStatus?
    var statusAt: Date?
    var step: String?
    var rateLimits: CodexRateLimits?

    /// Reads the lines from `offset` on. Returns whether anything about the thread changed.
    mutating func read(_ url: URL) -> Bool {
        var changed = false
        offset = JSONLines.read(url, from: offset) { line in
            if consume(line) { changed = true }
        }
        return changed
    }

    /// Catches up on a file seen for the first time from its head and its last 512 KB, without reading
    /// the whole thing.
    mutating func readTail(_ url: URL) {
        if let first = JSONLines.firstLine(of: url) { _ = consume(Data(first.utf8)) }
        for line in JSONLines.tail(of: url, bytes: 512 * 1024) ?? [] { _ = consume(Data(line.utf8)) }
        offset = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }

    mutating func consume(_ line: Data) -> Bool {
        let head = String(decoding: line.prefix(200), as: UTF8.self)
        let kind: LineKind
        if head.contains("\"type\":\"session_meta\"") {
            kind = .meta
        } else if head.contains("\"type\":\"event_msg\"") {
            guard let event = ["task_started", "task_complete", "turn_aborted", "token_count", "\"error\""]
                .first(where: { head.contains($0) }) else { return false }
            kind = .event(event)
        } else if head.contains("\"type\":\"response_item\""),
                  head.contains("\"function_call\"") || head.contains("\"custom_tool_call\"") || head.contains("\"local_shell_call\"") {
            kind = .call
        } else {
            return false
        }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return false }
        let date = (object["timestamp"] as? String).flatMap(CodexRollout.date) ?? .now
        switch kind {
        case .meta:
            threadID = payload["id"] as? String ?? payload["session_id"] as? String
            cwd = payload["cwd"] as? String
            originator = payload["originator"] as? String
            isHelper = (payload["source"] as? [String: Any])?["subagent"] != nil
            return true
        case .event:
            switch payload["type"] as? String {
            case "task_started": set(.working, at: date)
            case "task_complete": set(.done, at: date)
            case "turn_aborted": set(.stopped, at: date)
            case "error": set(.failed, at: date)
            case "token_count":
                if let limits = (payload["rate_limits"] as? [String: Any]).flatMap({ CodexRateLimits($0, at: date) }) {
                    rateLimits = limits
                }
                return false
            default: return false
            }
            return true
        case .call:
            guard status == .working else { return false }
            step = Self.step(payload)
            return true
        }
    }

    private enum LineKind {
        case meta, event(String), call
    }

    private mutating func set(_ value: AgentStatus, at date: Date) {
        status = value
        statusAt = date
        if value != .working { step = nil }
    }

    private static func step(_ payload: [String: Any]) -> String? {
        let name = payload["name"] as? String ?? (payload["type"] as? String == "local_shell_call" ? "shell" : "tool")
        var input: [String: Any] = [:]
        if let arguments = payload["arguments"] as? String,
           let decoded = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any] {
            input = decoded
        } else if let action = payload["action"] as? [String: Any] {
            input = action
        } else if let raw = payload["input"] as? String {
            input = ["input": raw, "command": raw]
        }
        // Code-mode calls carry a title, or run a command from inside a script.
        if let title = input["title"] as? String, !title.isEmpty { return title }
        if name == "exec", let raw = input["input"] as? String {
            if let command = raw.firstMatch(of: /cmd:\s*"([^"]{1,80})"/)?.1 {
                return AgentSteps.step(tool: "shell", input: ["command": String(command)])
            }
            return String(localized: "Running code", comment: "Agent step")
        }
        return AgentSteps.step(tool: name, input: input)
    }

    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(_ text: String) -> Date? {
        fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// The app a rollout's thread runs in, by its originator (CLI threads are found through hooks).
    var hostBundleID: String? {
        switch originator {
        case "Codex Desktop": "com.openai.codex"
        case "T3 Code": "com.t3tools.t3code"
        case "codex_vscode": "com.microsoft.VSCode"
        default: nil
        }
    }
}

/// Codex keeps a thread list in `state_<n>.sqlite`; its `title` is what the Codex app shows. Read once
/// per new thread, read-only (Codex may be writing; SQLite lets readers in alongside).
enum CodexThreadTitles {
    static func title(folder: URL, threadID: String) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        // The newest schema: state_5.sqlite beats state_4.sqlite.
        guard let file = names.filter({ $0.hasPrefix("state_") && $0.hasSuffix(".sqlite") })
            .max(by: { $0.localizedStandardCompare($1) == .orderedAscending }) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(folder.appending(path: file).path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return nil
        }
        defer { sqlite3_close_v2(db) }
        sqlite3_busy_timeout(db, 200)
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COALESCE(NULLIF(name, ''), title) FROM threads WHERE id = ?", -1, &statement, nil) != SQLITE_OK {
            // Older schemas have a title but no separate name.
            guard sqlite3_prepare_v2(db, "SELECT title FROM threads WHERE id = ?", -1, &statement, nil) == SQLITE_OK else { return nil }
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, threadID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) else { return nil }
        let title = String(cString: raw).split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !title.isEmpty, !title.hasPrefix("<"), !title.hasPrefix("#") else { return nil }
        return title.count > 60 ? String(title.prefix(59)) + "…" : title
    }
}
