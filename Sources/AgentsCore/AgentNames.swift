import Foundation

/// What names a thread in the Agents list (Settings → Agents).
public enum AgentNameStyle: String, CaseIterable, Sendable {
    /// The conversation's title, as the tool keeps it.
    case title
    /// The last message the user sent it.
    case lastMessage
    /// The git branch of its project folder.
    case branch

    public var label: String {
        switch self {
        case .title: String(localized: "Title", comment: "Agent name setting: the conversation's title")
        case .lastMessage: String(localized: "Last message", comment: "Agent name setting: the last message sent")
        case .branch: String(localized: "Branch", comment: "Agent name setting: the git branch")
        }
    }
}

/// What shows under a thread's name in the Agents list (Settings → Agents).
public enum AgentDetailStyle: String, CaseIterable, Sendable {
    /// Its project folder.
    case folder
    /// The last message the user sent it.
    case lastMessage
    /// The git branch of its project folder.
    case branch

    public var label: String {
        switch self {
        case .folder: String(localized: "Folder", comment: "Agent detail setting: the project folder")
        case .lastMessage: String(localized: "Last message", comment: "Agent detail setting: the last message sent")
        case .branch: String(localized: "Branch", comment: "Agent detail setting: the git branch")
        }
    }
}

enum AgentNames {
    /// The first line, at most `limit` characters. Nil for text the tool added itself, which starts with
    /// a tag or a heading ("<environment_context>", "# AGENTS.md instructions…").
    static func oneLine(_ text: String?, limit: Int = 80) -> String? {
        guard let text, limit > 0 else { return nil }
        // Bound the scan too: a tool can send megabytes of whitespace or one enormous line.
        let prefix = String(decoding: text.utf8.prefix(640), as: UTF8.self)
        guard let line = prefix.split(whereSeparator: \.isNewline).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("<"), !trimmed.hasPrefix("#") else { return nil }
        let collapsed = trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit - 1)) + "…" : collapsed
    }
}

/// The branch checked out in a project folder, from `.git/HEAD` (a worktree's `.git` file points to its
/// own HEAD). Nil outside a repository or on a detached HEAD.
enum GitBranch {
    static func name(cwd: String) -> String? {
        guard cwd.hasPrefix("/") else { return nil }
        // Plain paths: on macOS 15 the parent of the URL "/" is "/..", which never ends the climb.
        var folder = (cwd as NSString).standardizingPath
        // A folder can't be nested deeper than this; the cap is a safety net.
        for _ in 0..<256 {
            let git = (folder as NSString).appendingPathComponent(".git")
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: git, isDirectory: &isFolder) {
                return branch(git: URL(fileURLWithPath: git), isFolder: isFolder.boolValue)
            }
            if folder == "/" { return nil }
            folder = (folder as NSString).deletingLastPathComponent
        }
        return nil
    }

    private static func branch(git: URL, isFolder: Bool) -> String? {
        var gitFolder = git
        if !isFolder {
            guard let link = JSONLines.smallText(git),
                  let path = link.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces),
                  path.hasPrefix("gitdir:") else { return nil }
            let target = path.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            gitFolder = target.hasPrefix("/") ? URL(fileURLWithPath: target)
                : git.deletingLastPathComponent().appending(path: target)
        }
        guard let head = JSONLines.smallText(gitFolder.appending(path: "HEAD")) else { return nil }
        let ref = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ref.hasPrefix("ref: refs/heads/") else { return nil }
        let name = String(ref.dropFirst("ref: refs/heads/".count))
        return name.isEmpty ? nil : name
    }
}
