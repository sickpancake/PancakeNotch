import Foundation

/// Claude Code's own list of live sessions: one small `<config>/sessions/<pid>.json` per running
/// session, removed when it quits (ADR-0037). Status is busy / shell / idle / waiting.
struct ClaudeSession: Equatable, Sendable {
    let pid: pid_t
    let sessionID: String
    let cwd: String
    let name: String?
    let status: String
    let waitingFor: String?
    let statusUpdated: Date

    init?(data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = object["pid"] as? Int, let sessionID = object["sessionId"] as? String,
              let status = object["status"] as? String else { return nil }
        self.pid = pid_t(pid)
        self.sessionID = sessionID
        cwd = object["cwd"] as? String ?? ""
        name = (object["name"] as? String).flatMap { $0.isEmpty || $0.lowercased() == "untitled session" ? nil : $0 }
        self.status = status
        waitingFor = (object["waitingFor"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let millis = object["statusUpdatedAt"] as? Double ?? object["updatedAt"] as? Double ?? 0
        statusUpdated = millis > 0 ? Date(timeIntervalSince1970: millis / 1000) : .now
    }

    /// Working, needing you, or nil for idle (finished its turn, or never started).
    var agentStatus: AgentStatus? {
        switch status {
        case "busy", "shell": .working
        case "waiting": .needsYou(waitingFor?.localizedCaseInsensitiveContains("permission") == true ? .permission : .input)
        default: nil
        }
    }

    /// "Input needed" from "input needed".
    var request: String? {
        guard let waitingFor else { return nil }
        return waitingFor.prefix(1).uppercased() + waitingFor.dropFirst()
    }

    /// Every live session in a config folder. Files of sessions whose process is gone (a crash) are
    /// skipped.
    static func read(folder: URL) -> [ClaudeSession] {
        let sessions = folder.appending(path: "sessions", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: sessions.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            guard let data = FileManager.default.contents(atPath: sessions.appending(path: name).path),
                  let session = ClaudeSession(data: data), HostApps.isAlive(session.pid) else { return nil }
            return session
        }
    }
}

/// The current step of a Claude Code session, from the end of its transcript: the last tool call of
/// the newest assistant message. Reads at most the last 256 KB, only while the Agents list is on screen.
enum ClaudeTranscript {
    /// `<config>/projects/<folder>/<session id>.jsonl`. The folder is the cwd with `/` and `.` as `-`,
    /// but rather than rely on that, look for the file name in each project folder.
    static func url(folder: URL, sessionID: String, cwd: String) -> URL? {
        let projects = folder.appending(path: "projects", directoryHint: .isDirectory)
        let guess = projects.appending(path: cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { $0.append($1) })
            .appending(path: sessionID + ".jsonl")
        if FileManager.default.fileExists(atPath: guess.path) { return guess }
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        return folders.lazy.map { projects.appending(path: $0).appending(path: sessionID + ".jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func currentStep(at url: URL) -> String? {
        guard let tail = JSONLines.tail(of: url, bytes: 256 * 1024) else { return nil }
        for line in tail.reversed() {
            guard line.contains("\"tool_use\""), line.contains("\"assistant\""),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { continue }
            if let call = content.last(where: { $0["type"] as? String == "tool_use" }), let name = call["name"] as? String {
                return AgentSteps.step(tool: name, input: call["input"] as? [String: Any] ?? [:])
            }
        }
        return nil
    }
}

/// Reading JSON Lines files a piece at a time, so big logs never sit in memory.
enum JSONLines {
    /// The complete lines in the last `bytes` of a file.
    static func tail(of url: URL, bytes: Int) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        var lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        // A tail that starts mid-file starts mid-line.
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    /// The file's first line, read in pieces (Codex's first line can be large).
    static func firstLine(of url: URL, limit: Int = 4 * 1024 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var data = Data()
        while data.count < limit, let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            if let newline = chunk.firstIndex(of: UInt8(ascii: "\n")) {
                data.append(chunk[chunk.startIndex..<newline])
                return String(decoding: data, as: UTF8.self)
            }
            data.append(chunk)
        }
        return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
    }

    /// Calls `line` for each complete line from `offset` on, reading 256 KB at a time. Returns the offset
    /// after the last complete line (a line still being written is read next time). Lines over
    /// `maxLine` are skipped.
    @discardableResult
    static func read(_ url: URL, from offset: UInt64, maxLine: Int = 16 * 1024 * 1024,
                     shouldContinue: () -> Bool = { true }, line: (Data) -> Void) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > offset else { return offset }
        try? handle.seek(toOffset: offset)
        var position = offset
        var chunkOffset = offset
        var pending = Data()
        var skipping = false
        while shouldContinue(), let chunk = try? handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            var start = chunk.startIndex
            while let newline = chunk[start...].firstIndex(of: UInt8(ascii: "\n")) {
                guard shouldContinue() else { return position }
                if !skipping, pending.count + newline - start <= maxLine {
                    if pending.isEmpty {
                        line(Data(chunk[start..<newline]))
                    } else {
                        pending.append(chunk[start..<newline])
                        line(pending)
                    }
                }
                pending.removeAll(keepingCapacity: true)
                skipping = false
                position = chunkOffset + UInt64(newline + 1)
                start = chunk.index(after: newline)
            }
            let rest = chunk[start...]
            if skipping {
                // Keep the last complete-line offset until the oversized line ends.
            } else if pending.count + rest.count > maxLine {
                skipping = true
                pending.removeAll()
            } else {
                pending.append(rest)
            }
            chunkOffset += UInt64(chunk.count)
        }
        // Just after the last newline. An unfinished line, even an oversized one, is retried intact.
        return position
    }
}
