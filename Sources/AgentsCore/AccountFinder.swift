import Foundation

/// Finds the AI tools' account folders (ADR-0037): `~/.claude` and `~/.codex`, other Claude/Codex config
/// folders in the home folder (`~/.claude-work`, `~/.codex_personal`), and folders the user added. A
/// folder counts when it holds the tool's own files. Reads names and a couple of small files only.
enum AccountFinder {
    struct Found: Hashable, Sendable {
        let tool: AgentTool
        let folder: URL
    }

    static func find(home: URL, added: [String]) -> [Found] {
        var found: [Found] = []
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        // The standard folders first, then the others by name.
        for name in names.sorted(by: { rank($0) < rank($1) || (rank($0) == rank($1) && $0 < $1) }) {
            guard let tool = tool(forFolderNamed: name) else { continue }
            let folder = home.appending(path: name, directoryHint: .isDirectory)
            if looksLikeAccount(folder, tool: tool, home: home) { found.append(Found(tool: tool, folder: folder)) }
        }
        for path in added {
            let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            guard let tool = AgentTool.allCases.first(where: { looksLikeAccount(folder, tool: $0, home: home) }),
                  !found.contains(where: { $0.folder.standardizedFileURL == folder.standardizedFileURL }) else { continue }
            found.append(Found(tool: tool, folder: folder))
        }
        return found.sorted { ($0.tool == .claude ? 0 : 1) < ($1.tool == .claude ? 0 : 1) }
    }

    /// The tool a folder added with "Add account folder…" belongs to, or nil when it's neither.
    static func tool(of folder: URL, home: URL) -> AgentTool? {
        [AgentTool.claude, .codex].first { looksLikeAccount(folder, tool: $0, home: home) }
    }

    /// `.claude`, `.claude-work`, `.claude_2`; `.codex`, `.codex-work`. Not `.claude.json` or backups.
    static func tool(forFolderNamed name: String) -> AgentTool? {
        for tool in [AgentTool.claude, .codex] {
            let base = "." + tool.rawValue
            if name == base { return tool }
            guard name.hasPrefix(base), name.count > base.count + 1 else { continue }
            let separator = name[name.index(name.startIndex, offsetBy: base.count)]
            let rest = name.dropFirst(base.count + 1)
            if "-_.".contains(separator), !rest.contains("."), !rest.hasPrefix("before"), !rest.hasSuffix("backup") {
                return tool
            }
        }
        return nil
    }

    private static func rank(_ name: String) -> Int {
        name == ".claude" || name == ".codex" ? 0 : 1
    }

    /// Claude: a `projects` or `sessions` folder, or its `.claude.json`. Codex: `auth.json` or `sessions`.
    static func looksLikeAccount(_ folder: URL, tool: AgentTool, home: URL) -> Bool {
        let fm = FileManager.default
        func has(_ name: String) -> Bool { fm.fileExists(atPath: folder.appending(path: name).path) }
        switch tool {
        case .claude: return has("projects") || has("sessions") || has(".claude.json")
        case .codex: return has("auth.json") || has("sessions")
        case .cursor: return false
        }
    }

    /// Claude keeps the default account's `.claude.json` in the home folder, others inside their folder.
    static func claudeConfigFile(for folder: URL, home: URL) -> URL {
        let inside = folder.appending(path: ".claude.json")
        if folder.standardizedFileURL.path == home.appending(path: ".claude").standardizedFileURL.path,
           !FileManager.default.fileExists(atPath: inside.path) {
            return home.appending(path: ".claude.json")
        }
        return inside
    }

    /// Cursor is on this Mac (its app or its settings folder).
    static func hasCursor(home: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: home.appending(path: ".cursor").path)
            || fm.fileExists(atPath: "/Applications/Cursor.app")
            || fm.fileExists(atPath: home.appending(path: "Applications/Cursor.app").path)
    }
}

/// Which supported AI tools are on this Mac, for the "turn on Agents" offer (ADR-0037).
public enum AgentsDetection {
    public static func foundTools(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AgentTool] {
        var tools = Set(AccountFinder.find(home: home, added: []).map(\.tool))
        if AccountFinder.hasCursor(home: home) { tools.insert(.cursor) }
        return AgentTool.allCases.filter(tools.contains)
    }
}
