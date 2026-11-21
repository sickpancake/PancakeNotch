import Foundation
import CryptoKit

/// Conversations a host app (T3 Code) started as helpers of another conversation. The host runs each
/// helper as a conversation of its own, so the tools' files hold no parent link. The task text is the
/// link: the main conversation's call to the host's delegate tool (`mcp__t3-code__delegate_task`) holds
/// it, and the helper's first message repeats it word for word. Only the tools' own files are read.
/// Touched only on the agents file queue.
final class DelegatedHelpers: @unchecked Sendable {
    struct Delegation: Equatable, Sendable {
        let parentID: String
        /// The title the main conversation gave the task ("Review the parser").
        let title: String?
    }

    /// Compatibility constant for fixtures; history recovery no longer starts at this tail boundary.
    static let firstLook: UInt64 = 4 * 1024 * 1024

    private struct Evidence: Equatable {
        let parent: String
        let identity: String
        let title: String?
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.parent == rhs.parent && lhs.identity == rhs.identity }
    }
    private struct FileState {
        var offset: UInt64 = 0
        var inode: UInt64 = 0
        var modified: Date?
        var matches: [String: [Evidence]] = [:]
        var pending: [String: (expected: Int, matches: [String: [Evidence]])] = [:]
        /// Where the file's delegation records are (offset, length): a new candidate rereads just
        /// those, never the whole history, and no task text stays in memory.
        var records: [(offset: UInt64, length: Int)] = []
    }
    private var files: [String: FileState] = [:]
    private(set) var ambiguousIDs: Set<String> = []
    private var queries: [String: String] = [:]

    /// Streams each file once, then only new complete lines. Changing the candidates rereads just the
    /// delegation records found so far, by position. Retains at most two distinct matches per query/file:
    /// enough to prove ambiguity, without retaining the transcript or every historical task body.
    func resolve(_ prompts: [String: String], among parents: [(id: String, url: URL)]) -> [String: Delegation] {
        let fingerprints = prompts.mapValues { Self.digest($0) }
        let changed = fingerprints != queries
        queries = fingerprints
        if changed {
            for path in Array(files.keys) { files[path]?.matches = [:]; files[path]?.pending = [:] }
        }
        let paths = Set(parents.map { $0.url.path })
        files = files.filter { paths.contains($0.key) }
        var matches: [String: [Evidence]] = [:]
        for parent in parents {
            let attributes = (try? FileManager.default.attributesOfItem(atPath: parent.url.path)) ?? [:]
            let size = attributes[.size] as? UInt64 ?? 0
            let inode = attributes[.systemFileNumber] as? UInt64 ?? 0
            let modified = attributes[.modificationDate] as? Date
            var state = files[parent.url.path] ?? FileState()
            if state.offset > size || state.inode != inode || (size <= state.offset && state.modified != modified) {
                state = FileState()
            }
            state.inode = inode
            state.modified = modified
            func consume(_ line: Data, at offset: UInt64?) {
                guard line.range(of: Data("delegate_task".utf8)) != nil || line.range(of: Data("custom_tool_call_output".utf8)) != nil else { return }
                let wrapper = Self.wrapper(line)
                let tasks = Self.delegatedTasks(line)
                var additions: [String: [Evidence]] = [:]
                for task in tasks {
                    for (id, prompt) in prompts where id != parent.id && prompt.contains(task.text) {
                        let evidence = Evidence(parent: parent.id, identity: task.identity, title: task.title)
                        if additions[id, default: []].count < 2, !(additions[id] ?? []).contains(evidence) {
                            additions[id, default: []].append(evidence)
                        }
                    }
                }
                let relevant = !tasks.isEmpty || wrapper.map { state.pending[$0.id] != nil } == true
                if let offset, relevant { state.records.append((offset, line.count)) }
                if let wrapper, wrapper.isCall {
                    // Script text alone does not prove a call executed (it may be in a dead branch).
                    // Keep only candidate matches until the saved result confirms actual child creation.
                    if !tasks.isEmpty { state.pending[wrapper.id] = (tasks.count, additions) }
                    return
                }
                if let wrapper, let pending = state.pending.removeValue(forKey: wrapper.id),
                   pending.expected > 0, wrapper.children >= pending.expected { additions = pending.matches }
                for (id, values) in additions {
                    for evidence in values where !(state.matches[id] ?? []).contains(evidence) {
                        if state.matches[id, default: []].count < 2 { state.matches[id, default: []].append(evidence) }
                    }
                }
            }
            if changed, !state.records.isEmpty, let handle = JSONLines.open(parent.url) {
                for record in state.records {
                    autoreleasepool {
                        guard (try? handle.seek(toOffset: record.offset)) != nil,
                              let line = try? handle.read(upToCount: record.length), line.count == record.length else { return }
                        consume(line, at: nil)
                    }
                }
                try? handle.close()
            }
            if size > state.offset {
                let offset = state.offset
                state.offset = JSONLines.read(parent.url, from: offset) { line, at in consume(line, at: at) }
            }
            files[parent.url.path] = state
            for (id, values) in state.matches {
                for value in values where !(matches[id] ?? []).contains(value) {
                    if matches[id, default: []].count < 2 { matches[id, default: []].append(value) }
                }
            }
        }
        let unique = matches.filter { $0.value.count == 1 }
        ambiguousIDs = Set(matches.filter { $0.value.count > 1 }.keys)
        for (id, values) in unique where unique.values.filter({ $0.first == values.first }).count > 1 { ambiguousIDs.insert(id) }
        return unique.compactMapValues { values in
            guard let only = values.first,
                  unique.values.filter({ $0.first == only }).count == 1 else { return nil }
            return Delegation(parentID: only.parent, title: only.title)
        }
    }

    func parent(of prompt: String, among parents: [(id: String, url: URL)]) -> Delegation? {
        resolve(["query": prompt], among: parents)["query"]
    }

    func keep(only ids: Set<String>) {
        // File caches are reconciled by path on every resolve; never persist prompt text.
        if ids.isEmpty { files = [:]; queries = [:] }
    }

    private struct Task {
        let text: String
        let title: String?
        let identity: String
    }

    private static func delegatedTasks(_ line: Data) -> [Task] {
        guard line.range(of: Data("delegate_task".utf8)) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return [] }
        var inputs: [(String?, [String: Any])] = []
        if object["type"] as? String == "assistant",
           let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] {
            for block in content where block["type"] as? String == "tool_use" && isDelegate(block["name"] as? String) {
                if let input = block["input"] as? [String: Any] { inputs.append((block["id"] as? String, input)) }
            }
        } else if object["type"] as? String == "response_item", let payload = object["payload"] as? [String: Any] {
            if payload["type"] as? String == "function_call", isDelegate(payload["name"] as? String),
               let arguments = payload["arguments"] as? String,
               let input = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any] {
                inputs.append((payload["call_id"] as? String, input))
            } else if payload["type"] as? String == "custom_tool_call", payload["name"] as? String == "exec",
                      let script = payload["input"] as? String {
                inputs = DelegationScript.inputs(script).enumerated().map { index, input in
                    ((payload["call_id"] as? String).map { "\($0):\(index)" }, input)
                }
            }
        }
        return inputs.compactMap { identity, input in
            guard let text = (input["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let title = (input["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            // A digest deduplicates old records lacking call IDs; no additional task copy is cached.
            let fallback = digest(text + "\u{0}" + (title ?? ""))
            return Task(text: text, title: title?.isEmpty == false ? title : nil, identity: identity ?? fallback)
        }
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func wrapper(_ line: Data) -> (id: String, isCall: Bool, children: Int)? {
        guard line.range(of: Data("custom_tool_call".utf8)) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "response_item", let payload = object["payload"] as? [String: Any],
              let id = payload["call_id"] as? String else { return nil }
        if payload["type"] as? String == "custom_tool_call", payload["name"] as? String == "exec" { return (id, true, 0) }
        guard payload["type"] as? String == "custom_tool_call_output" else { return nil }
        var children: Set<String> = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 12 else { return }
            if let dict = value as? [String: Any] {
                if let child = dict["childThreadId"] as? String, dict["taskId"] is String { children.insert(child) }
                for key in ["structuredContent", "content", "text"] {
                    if let nested = dict[key] { visit(nested, depth: depth + 1) }
                }
            } else if let array = value as? [Any] {
                for member in array { visit(member, depth: depth + 1) }
            } else if let string = value as? String, let data = string.data(using: .utf8),
                      let decoded = try? JSONSerialization.jsonObject(with: data) { visit(decoded, depth: depth + 1) }
        }
        if let output = payload["output"] { visit(output, depth: 0) }
        return (id, false, children.count)
    }

    private static func isDelegate(_ name: String?) -> Bool {
        name == "delegate_task" || name == "mcp__t3-code__delegate_task" || name == "mcp__t3_code__delegate_task"
    }

    private var historyFiles: [String: (id: String, url: URL)] = [:]
    /// Files whose complete first line names no conversation (or a native helper): not read again.
    private var notParents: Set<String> = []

    /// Enumerates tool-owned JSONL history; only previously unseen files need a metadata read.
    /// No database and no task text is written. Large histories are streamed by JSONLines.read.
    func history(in accounts: [AccountFinder.Found]) -> [(id: String, url: URL)] {
        var present: Set<String> = []
        for account in accounts {
            let root = account.folder.appending(path: account.tool == .codex ? "sessions" : "projects")
            guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in entries where url.pathExtension == "jsonl" {
                present.insert(url.path)
                guard historyFiles[url.path] == nil, !notParents.contains(url.path), !url.path.contains("/subagents/") else { continue }
                // Codex's first line can be megabytes: let each one go before the next file.
                autoreleasepool {
                    guard let first = JSONLines.firstLine(of: url),
                          let object = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any] else { return }
                    let raw: String?
                    if account.tool == .codex {
                        let payload = object["payload"] as? [String: Any]
                        // Native helpers and reviewers belong to the provider-native path only.
                        if let source = payload?["source"] as? [String: Any], source["subagent"] != nil { notParents.insert(url.path); return }
                        raw = payload?["id"] as? String
                    } else { raw = object["sessionId"] as? String }
                    if let raw, !raw.isEmpty { historyFiles[url.path] = ("\(account.tool.rawValue):\(raw)", url) }
                    else { notParents.insert(url.path) }
                }
            }
        }
        historyFiles = historyFiles.filter { present.contains($0.key) }
        notParents = notParents.filter(present.contains)
        return Array(historyFiles.values)
    }

    static func parentDetails(_ url: URL, codex: Bool) -> (cwd: String?, title: String?) {
        var cwd: String?
        var lines = 0
        JSONLines.read(url, from: 0, shouldContinue: { cwd == nil && lines < 64 }) { line in
            lines += 1
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
            cwd = codex ? (object["payload"] as? [String: Any])?["cwd"] as? String : object["cwd"] as? String
        }
        return (cwd, codex ? nil : ClaudeTranscript.details(at: url, wantsStep: false).title)
    }

    /// A conversation's first message from the user (or the host), from the head of its file.
    static func firstPrompt(of url: URL) -> String? {
        var prompt: String?
        JSONLines.read(url, from: 0, shouldContinue: { prompt == nil }) { line in
            guard prompt == nil, let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
            if object["type"] as? String == "user", object["isMeta"] as? Bool != true,
               let message = object["message"] as? [String: Any] {
                // Claude Code: a typed message, not a tool's result.
                let text = message["content"] as? String
                    ?? (message["content"] as? [[String: Any]])?.first { $0["type"] as? String == "text" }?["text"] as? String
                if let text, !text.hasPrefix("<") { prompt = text }
            } else if let payload = object["payload"] as? [String: Any] {
                // Codex: the first user message that isn't context it added.
                let text: String? = payload["type"] as? String == "user_message" ? payload["message"] as? String
                    : payload["role"] as? String == "user"
                    ? (payload["content"] as? [[String: Any]])?.first { $0["type"] as? String == "input_text" }?["text"] as? String : nil
                if let text, !text.hasPrefix("<"), !text.hasPrefix("#") { prompt = text }
            }
        }
        return prompt
    }
}
