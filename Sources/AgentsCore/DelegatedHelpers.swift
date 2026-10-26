import Foundation

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

    /// A delegated task: its whole text (tasks often start alike), and its title.
    private struct Task {
        let text: String
        let title: String?
    }

    /// A transcript or rollout is first read from this far before its end; then from where it stopped.
    static let firstLook: UInt64 = 4 * 1024 * 1024

    /// By conversation ID.
    private var offsets: [String: UInt64] = [:]
    private var tasks: [String: [Task]] = [:]

    /// The main conversation that delegated `prompt` (a helper's first message), from the calls in the
    /// conversations' files read so far plus any new lines.
    func parent(of prompt: String, among parents: [(id: String, url: URL)]) -> Delegation? {
        for parent in parents { scan(parent.id, url: parent.url) }
        for parent in parents {
            if let task = tasks[parent.id]?.last(where: { prompt.contains($0.text) }) {
                return Delegation(parentID: parent.id, title: task.title)
            }
        }
        return nil
    }

    /// Drops what was read from the conversations no longer followed.
    func keep(only ids: Set<String>) {
        offsets = offsets.filter { ids.contains($0.key) }
        tasks = tasks.filter { ids.contains($0.key) }
    }

    /// Picks up the delegate calls added to a conversation's file since the last look.
    private func scan(_ id: String, url: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        var offset = offsets[id] ?? (size > Self.firstLook ? size - Self.firstLook : 0)
        if offset > size { offset = 0 }
        offsets[id] = JSONLines.read(url, from: offset) { line in
            guard let task = Self.delegatedTask(line) else { return }
            tasks[id, default: []].append(task)
        }
    }

    /// The task in a delegate call: a Claude Code `tool_use`, or a Codex `function_call` whose
    /// arguments are JSON text.
    private static func delegatedTask(_ line: Data) -> Task? {
        guard line.range(of: Data("delegate_task".utf8)) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        var input: [String: Any]?
        if let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] {
            input = content.first { $0["type"] as? String == "tool_use" && ($0["name"] as? String)?.hasSuffix("delegate_task") == true }?["input"] as? [String: Any]
        } else if let payload = object["payload"] as? [String: Any], (payload["name"] as? String)?.hasSuffix("delegate_task") == true,
                  let arguments = payload["arguments"] as? String {
            input = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any]
        }
        guard let text = (input?["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let title = (input?["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Task(text: text, title: title?.isEmpty == false ? title : nil)
    }

    /// A conversation's first message from the user (or the host), from the head of its file.
    static func firstPrompt(of url: URL) -> String? {
        var prompt: String?
        var read = 0
        JSONLines.read(url, from: 0, shouldContinue: { prompt == nil && read < 2 * 1024 * 1024 }) { line in
            read += line.count
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
