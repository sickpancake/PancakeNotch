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
        // Only a name the user gave it (/rename). The others are the folder's ("pancakenotch-5a") or made
        // from what was asked last; the transcript's title is better.
        name = object["nameSource"] as? String != "user" ? nil
            : (object["name"] as? String).flatMap { $0.isEmpty || $0.lowercased() == "untitled session" ? nil : $0 }
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

/// The current step, the title and the last message of a Claude Code session, from the end of its
/// transcript: the last tool call of the newest assistant message, the newest title line (a name the user
/// gave it, else Claude's own, both rewritten every so often) and the newest prompt. Reads at most the
/// last 256 KB, when a session appears or starts a turn, and while the Agents list is on screen.
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

    static func details(at url: URL, wantsStep: Bool) -> (step: String?, title: String?, lastMessage: String?) {
        guard let tail = JSONLines.tail(of: url, bytes: 256 * 1024) else { return (nil, nil, nil) }
        var step: String?
        var customTitle: String?
        var aiTitle: String?
        var lastMessage: String?
        for line in tail.reversed() where customTitle == nil || lastMessage == nil || (wantsStep && step == nil) {
            if line.contains("\"custom-title\"") {
                customTitle = customTitle ?? title(line, key: "customTitle")
            } else if line.contains("\"ai-title\"") {
                aiTitle = aiTitle ?? title(line, key: "aiTitle")
            } else if line.contains("\"last-prompt\"") {
                lastMessage = lastMessage ?? title(line, key: "lastPrompt").flatMap { AgentNames.oneLine($0) }
            } else if lastMessage == nil, line.contains("\"type\":\"user\""), !line.contains("\"tool_result\"") {
                lastMessage = prompt(line)
            } else if wantsStep, step == nil {
                step = currentStep(line)
            }
        }
        return (step, customTitle ?? aiTitle, lastMessage)
    }

    /// What the user typed, from a user message line (not a tool's result or a line the tool added).
    private static func prompt(_ line: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              object["isMeta"] as? Bool != true, let message = object["message"] as? [String: Any] else { return nil }
        let text = message["content"] as? String
            ?? (message["content"] as? [[String: Any]])?.first { $0["type"] as? String == "text" }?["text"] as? String
        return AgentNames.oneLine(text)
    }

    private static func title(_ line: String, key: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let title = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return title
    }

    /// The last tool call of an assistant message line.
    private static func currentStep(_ line: String) -> String? {
        guard line.contains("\"tool_use\""), line.contains("\"assistant\""),
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]],
              let call = content.last(where: { $0["type"] as? String == "tool_use" }), let name = call["name"] as? String else { return nil }
        return AgentSteps.step(tool: name, input: call["input"] as? [String: Any] ?? [:])
    }
}

/// A Claude Code session's subagents: `<transcript without .jsonl>/subagents/agent-<id>.jsonl`, each with
/// a small `.meta.json` holding what it was asked to do, and `"finished": true` once it's done. Read only
/// while the Agents list is on screen.
enum ClaudeSubagents {
    /// A subagent whose transcript hasn't changed for this long is taken as gone (stopped mid-task).
    static let quietLimit: TimeInterval = 15 * 60

    static func working(transcript: URL, now: Date = .now) -> [AgentSubagent] {
        let folder = transcript.deletingPathExtension().appending(path: "subagents", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix("agent-") && $0.hasSuffix(".jsonl") }.compactMap { name in
            let log = folder.appending(path: name)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: log.path),
                  let modified = attributes[.modificationDate] as? Date, now.timeIntervalSince(modified) < quietLimit,
                  let data = FileManager.default.contents(atPath: log.deletingPathExtension().path + ".meta.json"),
                  let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  meta["finished"] as? Bool != true else { return nil }
            let title = [meta["description"], meta["agentType"]].lazy.compactMap { $0 as? String }.first { !$0.isEmpty }
                ?? String(localized: "Subagent", comment: "A Claude Code subagent with no description")
            return AgentSubagent(id: "claude:" + name.dropLast(".jsonl".count), title: title, status: .working,
                                 statusSince: attributes[.creationDate] as? Date ?? modified)
        }
    }

    /// The session a changed transcript file belongs to: its own (`<id>.jsonl`) or a subagent's
    /// (`<id>/subagents/agent-….jsonl` or `.meta.json`).
    static func sessionID(changed path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent == "subagents" { return parent.deletingLastPathComponent().lastPathComponent }
        return url.pathExtension == "jsonl" ? url.deletingPathExtension().lastPathComponent : nil
    }
}

/// Reading JSON Lines files a piece at a time, so big logs never sit in memory.
enum JSONLines {
    /// Opens `url` only if it's an ordinary file. Paths come from other apps' files and hook messages:
    /// a pipe or a device there would otherwise stall the read or never end.
    static func open(_ url: URL) -> FileHandle? {
        let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            close(fd)
            return nil
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    /// A small ordinary file's text (Git's HEAD and the like), or nil if it's bigger than `limit`.
    static func smallText(_ url: URL, limit: Int = 4096) -> String? {
        guard let handle = open(url), let data = try? handle.read(upToCount: limit + 1),
              data.count <= limit else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The complete lines in the last `bytes` of a file.
    static func tail(of url: URL, bytes: Int) -> [String]? {
        guard let handle = open(url) else { return nil }
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

    /// Just past the file's last newline (0 without one), looking back from its end 64 KB at a time.
    static func endOfLastLine(of url: URL) -> UInt64 {
        guard let handle = open(url) else { return 0 }
        defer { try? handle.close() }
        guard var end = try? handle.seekToEnd() else { return 0 }
        while end > 0 {
            let start = end > 64 * 1024 ? end - 64 * 1024 : 0
            try? handle.seek(toOffset: start)
            guard let chunk = try? handle.read(upToCount: Int(end - start)), !chunk.isEmpty else { return 0 }
            if let newline = chunk.lastIndex(of: UInt8(ascii: "\n")) { return start + UInt64(newline - chunk.startIndex + 1) }
            end = start
        }
        return 0
    }

    /// The file's first line, read in pieces (Codex's first line can be large).
    static func firstLine(of url: URL, limit: Int = 4 * 1024 * 1024) -> String? {
        guard let handle = open(url) else { return nil }
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
        guard let handle = open(url) else { return offset }
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
