import Foundation
import Observation
import os

/// Connect and Disconnect (ADR-0037): adds PancakeNotch's hook helper to a tool's hook settings, or takes
/// exactly those entries out again. Claude Code: every Claude account folder's `settings.json`. Codex:
/// every Codex folder's `hooks.json`. Cursor: `~/.cursor/hooks.json`. Whether a tool is connected is read
/// from those files, never stored separately, so editing them by hand stays in charge.
@MainActor
@Observable
public final class AgentConnector {
    public enum State: Equatable, Sendable {
        /// The tool isn't on this Mac.
        case notFound
        case notConnected
        case connected
    }

    public private(set) var states: [AgentTool: State] = [:]
    /// Why the last Connect or Disconnect didn't work, in plain words.
    public private(set) var problem: String?

    private let home: URL
    private let settings: AgentsSettings
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "agents")
    /// Pretend tools (app-window snapshots): Connect and Disconnect only change what's shown.
    private var isPreview = false

    public init(settings: AgentsSettings, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.settings = settings
        self.home = home
        refresh()
    }

    /// Shows these states without reading or writing any file.
    public static func preview(_ states: [AgentTool: State], settings: AgentsSettings) -> AgentConnector {
        let connector = AgentConnector(settings: settings, home: URL(fileURLWithPath: "/var/empty"))
        connector.isPreview = true
        connector.states = states
        return connector
    }

    public func state(_ tool: AgentTool) -> State { states[tool] ?? .notFound }

    /// Reads the hook files again. A tool connected in one account folder is connected in all of them,
    /// so an account folder found later gets the hooks too.
    public func refresh() {
        guard !isPreview else { return }
        var next: [AgentTool: State] = [:]
        for tool in AgentTool.allCases {
            let files = hookFiles(for: tool)
            guard !files.isEmpty else {
                next[tool] = .notFound
                continue
            }
            let connected = files.filter { HookFile.read($0.url)?.contains(HookHelper.marker) ?? false }
            if connected.isEmpty {
                next[tool] = .notConnected
            } else {
                if connected.count < files.count { _ = write(tool, connect: true) }
                next[tool] = .connected
            }
        }
        if states != next { states = next }
    }

    /// Copies the helper into place and adds it to the tool's hooks. Returns whether it worked.
    @discardableResult
    public func connect(_ tool: AgentTool) -> Bool {
        problem = nil
        if isPreview {
            states[tool] = .connected
            return true
        }
        guard HookHelper.install() else {
            problem = String(localized: "PancakeNotch couldn't set up its helper. Try again, or reinstall PancakeNotch.")
            return false
        }
        let done = write(tool, connect: true)
        refresh()
        return done
    }

    @discardableResult
    public func disconnect(_ tool: AgentTool) -> Bool {
        problem = nil
        if isPreview {
            states[tool] = .notConnected
            return true
        }
        let done = write(tool, connect: false)
        refresh()
        return done
    }

    /// Keeps the installed helper current (a newer PancakeNotch may bring a newer one).
    public func updateHelperIfConnected() {
        if !isPreview, states.values.contains(.connected) { _ = HookHelper.install() }
    }

    // MARK: Files

    struct Target {
        let url: URL
        let kind: HookFile.Kind
    }

    func hookFiles(for tool: AgentTool) -> [Target] {
        switch tool {
        case .claude, .codex:
            return AccountFinder.find(home: home, added: settings.addedFolders)
                .filter { $0.tool == tool }
                .map { found in
                    tool == .claude
                        ? Target(url: found.folder.appending(path: "settings.json"), kind: .claude)
                        : Target(url: found.folder.appending(path: "hooks.json"), kind: .codex)
                }
        case .cursor:
            guard AccountFinder.hasCursor(home: home) else { return [] }
            return [Target(url: home.appending(path: ".cursor/hooks.json"), kind: .cursor)]
        }
    }

    private func write(_ tool: AgentTool, connect: Bool) -> Bool {
        var allDone = true
        for target in hookFiles(for: tool) {
            do {
                try HookFile.update(target.url, kind: target.kind, connect: connect)
            } catch {
                allDone = false
                logger.error("Hooks \(connect ? "connect" : "disconnect", privacy: .public) failed for \(target.kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                problem = (error as? HookFile.Problem)?.message ?? String(localized: "PancakeNotch couldn't change \(target.url.lastPathComponent). Check that it isn't locked, then try again.")
            }
        }
        return allDone
    }
}

/// Reads and edits one hook settings file, keeping everything that isn't PancakeNotch's.
enum HookFile {
    enum Kind: String {
        case claude, codex, cursor
    }

    struct Problem: Error {
        let message: String
    }

    /// The events each tool reports to the helper, and whether the tool waits for its answer.
    /// Waiting events are the permission requests answered from the notch; everything else runs in the
    /// background so the tool never slows down.
    static func events(for kind: Kind) -> [(name: String, waits: Bool)] {
        switch kind {
        case .claude:
            [("SessionStart", false), ("UserPromptSubmit", false), ("PermissionRequest", true), ("Notification", false),
             ("Stop", false), ("StopFailure", false), ("SessionEnd", false)]
        case .codex:
            [("SessionStart", false), ("UserPromptSubmit", false), ("PermissionRequest", true), ("Stop", false),
             ("Interrupt", false), ("SessionEnd", false)]
        case .cursor:
            [("sessionStart", false), ("beforeSubmitPrompt", false), ("afterShellExecution", false),
             ("afterFileEdit", false), ("stop", false), ("sessionEnd", false)]
        }
    }

    static func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    static func update(_ url: URL, kind: Kind, connect: Bool) throws {
        let fm = FileManager.default
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Problem(message: String(localized: "\(url.path(percentEncoded: false)) isn't valid JSON, so PancakeNotch left it alone. Fix it first, then try again."))
            }
            root = object
            // One copy of the file as it was before PancakeNotch first touched it.
            let backup = url.appendingPathExtension("before-pancakenotch")
            if connect, !fm.fileExists(atPath: backup.path) { try? data.write(to: backup) }
        } else if !connect {
            return
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (event, waits) in events(for: kind) {
            var groups = (hooks[event] as? [Any] ?? []).compactMap(removingOurs)
            if connect { groups.append(entry(kind: kind, event: event, waits: waits)) }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        if kind == .cursor, root["version"] == nil, !hooks.isEmpty { root["version"] = 1 }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    /// A matcher group (Claude, Codex) or a plain hook (Cursor) without PancakeNotch's entries; nil when
    /// nothing else was in it.
    private static func removingOurs(_ value: Any) -> Any? {
        guard var group = value as? [String: Any] else { return value }
        if let command = group["command"] as? String { return command.contains(HookHelper.marker) ? nil : group }
        guard let handlers = group["hooks"] as? [Any] else { return group }
        let kept = handlers.filter { (($0 as? [String: Any])?["command"] as? String)?.contains(HookHelper.marker) != true }
        if kept.isEmpty { return nil }
        group["hooks"] = kept
        return group
    }

    private static func entry(kind: Kind, event: String, waits: Bool) -> [String: Any] {
        let command = "'\(HookHelper.installedURL.path)' \(kind.rawValue) \(event)"
        switch kind {
        case .cursor:
            return ["command": command]
        case .claude, .codex:
            var handler: [String: Any] = ["type": "command", "command": command]
            if waits {
                handler["timeout"] = HookHelper.answerTimeout
            } else if event != "SessionEnd" {
                handler["async"] = true
            }
            return ["hooks": [handler]]
        }
    }
}
