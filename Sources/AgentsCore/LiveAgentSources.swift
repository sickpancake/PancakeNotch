import AppKit
import Foundation
import os

/// Follows the real tools for `AgentsCenter` (ADR-0037):
/// - Claude Code's live session list (`<config>/sessions/*.json`), for every Claude account folder;
/// - Codex's rollouts (`<CODEX_HOME>/sessions/…/rollout-*.jsonl`), for every Codex account folder;
/// - after Connect, the hook helper's socket (needs-you, Allow / Deny, Cursor).
/// All event-driven. Files are read on a background queue; the center is updated on the main actor.
@MainActor
final class LiveAgentSources {
    private unowned let center: AgentsCenter
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let queue = DispatchQueue(label: "io.github.sickpancake.PancakeNotch.agents.files", qos: .utility)
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "agents")

    private var accounts: [AccountFinder.Found] = []
    private var server: HookServer?
    private var watchers: [FolderWatcher] = []
    private var transcriptWatchers: [FolderWatcher] = []
    private var activationObserver: NSObjectProtocol?
    private let codex = CodexReader()

    /// Claude sessions as last read from their list, by thread ID.
    private var claudeSessions: [String: (folder: URL, session: ClaudeSession)] = [:]
    /// Permission requests waiting for Allow / Deny, by thread ID.
    private var pending: [String: Int] = [:]
    /// The last hook event per thread: the session list only overrides what's newer than it.
    private var lastHookEvent: [String: Date] = [:]
    /// The last sign of life per Codex and Cursor thread, for spotting ones that quit without a word.
    private var lastActivity: [String: Date] = [:]
    /// Whether a Codex hook's sender is one of its helpers, and the helper's own thread ID, by the hook's
    /// transcript path (or session ID without one).
    private var codexHelpers: [String: (isHelper: Bool, id: String?)] = [:]
    /// Spawned agents seen in their rollouts, by their own thread ID.
    private var codexSpawned: Set<String> = []
    /// Helpers may be read before their parent, or spawn helpers of their own.
    private var codexSubagents: [String: (parentID: String, agent: AgentSubagent)] = [:]
    private var detailed = false
    private var stopped = false

    /// A thread with no sign of life for this long counts as stopped when the list is shown.
    static let quietLimit: TimeInterval = 60 * 60

    init(center: AgentsCenter) {
        self.center = center
    }

    func start() {
        accounts = AccountFinder.find(home: home, added: center.settings.addedFolders)
        let server = HookServer(path: HookHelper.socketPath, onEvent: { [weak self] event in self?.handle(event) },
                                onGone: { [weak self] requestID in self?.helperGone(requestID) })
        if server.start() { self.server = server }
        watchClaudeSessions()
        watchCodex()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handBackToFrontmostApp() }
        }
    }

    func stop() {
        stopped = true
        for id in Array(pending.keys) { handBack(threadID: id) }
        server?.stop()
        server = nil
        stopWatching(&watchers)
        stopWatching(&transcriptWatchers)
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        claudeSessions = [:]
        pending = [:]
        lastHookEvent = [:]
        lastActivity = [:]
        codexHelpers = [:]
        codexSpawned = []
        codexSubagents = [:]
    }

    private func stopWatching(_ list: inout [FolderWatcher]) {
        let stopping = list
        list = []
        queue.async { for watcher in stopping { watcher.stop() } }
    }

    // MARK: Allow / Deny

    func answer(threadID: String, allow: Bool) {
        guard let thread = center.thread(threadID), let requestID = pending.removeValue(forKey: threadID) else { return }
        server?.answer(requestID, with: Self.decision(allow: allow, tool: thread.tool))
        // Either way the agent carries on: with the command, or with the news that it was denied.
        center.apply(.init(id: threadID, tool: thread.tool, at: .now, status: .working, request: .some(nil), canAnswer: false))
    }

    /// The tools' own answer format (Claude Code and Codex share it).
    nonisolated static func decision(allow: Bool, tool: AgentTool) -> String {
        var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if !allow { decision["message"] = "Denied from PancakeNotch." }
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        let data = (try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The request goes back to the tool's own window (Open, or the user switched to that app).
    func handBack(threadID: String) {
        guard let requestID = pending.removeValue(forKey: threadID) else { return }
        server?.answer(requestID, with: nil)
        if let thread = center.thread(threadID) {
            center.apply(.init(id: threadID, tool: thread.tool, at: thread.statusSince, canAnswer: false, quietly: true))
        }
    }

    private func handBackToFrontmostApp() {
        for threadID in pending.keys where center.isFrontmost(threadID) { handBack(threadID: threadID) }
    }

    /// The helper stopped waiting (the tool's own time limit): the question is in the tool's window now.
    private func helperGone(_ requestID: Int) {
        guard let threadID = pending.first(where: { $0.value == requestID })?.key else { return }
        pending[threadID] = nil
        if let thread = center.thread(threadID) {
            center.apply(.init(id: threadID, tool: thread.tool, at: thread.statusSince, canAnswer: false, quietly: true))
        }
    }

    /// Something else happened in the thread: a waiting request was answered elsewhere (T3 Code's own
    /// buttons, the terminal), so drop it.
    private func requestSettled(_ threadID: String) {
        guard let requestID = pending.removeValue(forKey: threadID) else { return }
        server?.answer(requestID, with: nil)
        if let thread = center.thread(threadID), thread.canAnswer {
            center.apply(.init(id: threadID, tool: thread.tool, at: thread.statusSince, canAnswer: false, quietly: true))
        }
    }

    // MARK: Hooks

    func handle(_ event: HookEvent) {
        guard !stopped else { return }
        guard let session = event.sessionID, !session.isEmpty else {
            if let requestID = event.requestID { server?.answer(requestID, with: nil) }
            return
        }
        // Codex's own helpers (its automatic reviewer, spawned agents) aren't threads of their own. Their
        // hooks can carry their parent's session ID: only the helper's own ID is ever touched.
        if event.tool == .codex, case let helper = codexHelper(event, session: session), helper.isHelper {
            if let own = helper.id, case let id = "codex:\(own)", var entry = codexSubagents[id] {
                switch event.name {
                case "Stop": entry.agent.status = .done
                case "Interrupt", "SessionEnd": entry.agent.status = .stopped
                default: break
                }
                codexSubagents[id] = entry
                codexRead([])
            }
            if let own = helper.id { center.forget("codex:\(own)") }
            if let requestID = event.requestID { server?.answer(requestID, with: nil) }
            if event.name == "SessionEnd" { codexHelpers[event.transcriptPath ?? session] = nil }
            return
        }
        let id = "\(event.tool.rawValue):\(session)"
        let now = Date()
        lastHookEvent[id] = now
        lastActivity[id] = now
        var update = AgentsCenter.Update(id: id, tool: event.tool, at: now, accountID: accountID(for: event),
                                         title: event.title, cwd: event.cwd, processID: event.parentPID)
        switch (event.tool, event.name) {
        case (_, "UserPromptSubmit"), (.cursor, "beforeSubmitPrompt"):
            requestSettled(id)
            update.status = .working
            update.lastMessage = event.prompt
        case (_, "PermissionRequest"):
            update.status = .needsYou(.permission)
            update.request = .some(event.summary)
            if let requestID = event.requestID {
                requestSettled(id)
                center.apply(update)
                // Already looking at its app: ask there right away.
                if center.isFrontmost(id) {
                    server?.answer(requestID, with: nil)
                } else {
                    pending[id] = requestID
                    center.apply(.init(id: id, tool: event.tool, at: now, canAnswer: true, quietly: true))
                }
                return
            }
        case (.claude, "Notification"):
            switch event.notificationType {
            case "permission_prompt":
                guard pending[id] == nil else { return }
                update.status = .needsYou(.permission)
                update.request = .some(event.message)
            case "elicitation_dialog", "agent_needs_input":
                update.status = .needsYou(.input)
                update.request = .some(event.message)
            case "agent_completed":
                update.status = .done
            default:
                return
            }
        case (_, "Stop"):
            requestSettled(id)
            update.status = .done
        case (.claude, "StopFailure"):
            requestSettled(id)
            update.status = .failed
            update.request = .some(event.message)
        case (.codex, "Interrupt"):
            requestSettled(id)
            update.status = .stopped
        case (.cursor, "stop"):
            update.status = switch event.status {
            case "error": .failed
            case "aborted": .stopped
            default: .done
            }
        case (.cursor, "afterShellExecution"), (.cursor, "afterFileEdit"):
            update.status = .working
            update.step = .some(event.summary)
        case (_, "SessionEnd"), (.cursor, "sessionEnd"):
            requestSettled(id)
            center.ended(id, at: now)
            lastHookEvent[id] = nil
            lastActivity[id] = nil
            codexHelpers[event.transcriptPath ?? session] = nil
            return
        default:
            return
        }
        center.apply(update)
    }

    /// From the hook's rollout (its first line, read once per rollout), else the session's model or a
    /// spawned agent's ID. A session without a rollout yet is taken as a real thread until it has one.
    private func codexHelper(_ event: HookEvent, session: String) -> (isHelper: Bool, id: String?) {
        let key = event.transcriptPath ?? session
        if let known = codexHelpers[key] { return known }
        var rollout = CodexRollout()
        if let path = event.transcriptPath, let first = JSONLines.firstLine(of: URL(fileURLWithPath: path)) {
            _ = rollout.consume(Data(first.utf8))
        }
        let isReviewer = event.model?.hasPrefix("codex-auto-review") == true
        guard let threadID = rollout.threadID else {
            return codexSpawned.contains(session) ? (true, session) : (isReviewer, nil)
        }
        let result = (isHelper: rollout.isHelper || isReviewer, id: rollout.isHelper || isReviewer ? threadID : nil)
        codexHelpers[key] = result
        return result
    }

    /// The account folder a hook event's transcript lives in (else the tool's standard folder).
    private func accountID(for event: HookEvent) -> String? {
        guard event.tool.hasUsage else { return nil }
        let candidates = accounts.filter { $0.tool == event.tool }
        let folder = event.transcriptPath.flatMap { path in
            candidates.first { path.hasPrefix($0.folder.standardizedFileURL.path + "/") }?.folder
        } ?? candidates.first?.folder
        return folder.map { AgentAccount(tool: event.tool, folder: $0).id }
    }

    // MARK: Claude Code's session list

    private func watchClaudeSessions() {
        let folders = accounts.filter { $0.tool == .claude }.map(\.folder)
        for folder in folders {
            readClaudeSessions(folder, initial: true)
            let sessions = folder.appending(path: "sessions").path
            if let watcher = FolderWatcher(paths: [sessions], latency: 0.25, queue: queue, onChange: { [weak self] _ in
                Task { @MainActor in self?.readClaudeSessions(folder, initial: false) }
            }) {
                watchers.append(watcher)
            }
        }
    }

    private func readClaudeSessions(_ folder: URL, initial: Bool) {
        queue.async { [weak self] in
            let sessions = ClaudeSession.read(folder: folder)
            // A session idle at launch shows as done only if it has a transcript (it actually worked).
            let worked: Set<String> = initial ? Set(sessions.filter { session in
                session.agentStatus == nil && Date().timeIntervalSince(session.statusUpdated) < AgentsCenter.keepAfterSeen
                    && ClaudeTranscript.url(folder: folder, sessionID: session.sessionID, cwd: session.cwd) != nil
            }.map(\.sessionID)) : []
            Task { @MainActor in self?.claudeSessionsRead(sessions, folder: folder, worked: worked) }
        }
    }

    private func claudeSessionsRead(_ sessions: [ClaudeSession], folder: URL, worked: Set<String>) {
        guard !stopped else { return }
        let accountID = AgentAccount(tool: .claude, folder: folder).id
        var seen: Set<String> = []
        for session in sessions {
            let id = "claude:\(session.sessionID)"
            seen.insert(id)
            let previous = claudeSessions[id]?.session
            claudeSessions[id] = (folder, session)
            var update = AgentsCenter.Update(id: id, tool: .claude, at: session.statusUpdated, accountID: accountID,
                                             title: session.name, cwd: session.cwd, processID: session.pid)
            let existing = center.thread(id)
            // Hooks know better than an older entry in the list.
            let stale = lastHookEvent[id].map { session.statusUpdated < $0 } ?? false
            if let status = session.agentStatus {
                if pending[id] != nil {
                    // A request waits for the notch; the list's "busy" is the request itself.
                    if previous?.status != session.status, session.status != "waiting", previous != nil { requestSettled(id) }
                    else { center.apply(update); continue }
                }
                if !stale {
                    update.status = status
                    if status.needsYou, existing?.request == nil { update.request = .some(session.request) }
                }
            } else {
                requestSettled(id)
                if let existing, !existing.status.isFinished, !stale {
                    update.status = .done
                } else if existing == nil {
                    guard worked.contains(session.sessionID) else { continue }
                    update.status = .done
                    update.quietly = true
                }
            }
            if existing == nil, update.status == nil { continue }
            center.apply(update)
            // A new session or a new turn gets its title and last message right away; steps and subagents
            // only while the list shows.
            let turnStarted = update.status == .working && existing?.status != .working
            if existing == nil || turnStarted || (detailed && update.status == .working) { readClaudeDetails(id) }
        }
        // Sessions that left the list quit.
        for (id, entry) in claudeSessions where entry.folder == folder && !seen.contains(id) {
            claudeSessions[id] = nil
            requestSettled(id)
            center.ended(id, at: .now)
        }
    }

    // MARK: Current steps (while the list is on screen)

    func setDetailed(_ value: Bool) {
        guard detailed != value else { return }
        detailed = value
        guard value else {
            stopWatching(&transcriptWatchers)
            return
        }
        markQuietThreadsStopped()
        refreshCodexTitles()
        for id in claudeSessions.keys { readClaudeDetails(id) }
        for found in accounts where found.tool == .claude {
            let projects = found.folder.appending(path: "projects").path
            if let watcher = FolderWatcher(paths: [projects], latency: 1, queue: queue, onChange: { [weak self] paths in
                let sessionIDs = Set(paths.compactMap(ClaudeSubagents.sessionID(changed:)))
                Task { @MainActor in
                    guard let self else { return }
                    for sessionID in sessionIDs { self.readClaudeDetails("claude:\(sessionID)") }
                }
            }) {
                transcriptWatchers.append(watcher)
            }
        }
    }

    /// The current step (while it works) and the working subagents of a live session.
    private func readClaudeDetails(_ id: String) {
        guard let entry = claudeSessions[id], let thread = center.thread(id) else { return }
        let wantsStep = detailed && thread.status == .working && center.settings.showsSteps
        let wantsSubagents = detailed && !thread.status.isFinished && center.settings.showsSubagents
        queue.async { [weak self] in
            let url = ClaudeTranscript.url(folder: entry.folder, sessionID: entry.session.sessionID, cwd: entry.session.cwd)
            let details = url.map { ClaudeTranscript.details(at: $0, wantsStep: wantsStep) }
            let subagents = wantsSubagents ? (url.map { ClaudeSubagents.working(transcript: $0) } ?? []) : []
            Task { @MainActor in
                guard let self, !self.stopped, let thread = self.center.thread(id) else { return }
                let step = self.detailed && thread.status == .working ? details?.step : nil
                // A name the user gave the session in Claude Code wins over the transcript's title.
                let title = entry.session.name == nil ? details?.title : nil
                let lastMessage = details?.lastMessage
                if step != nil || title != nil || lastMessage != nil {
                    self.center.apply(.init(id: id, tool: .claude, at: .now, title: title, lastMessage: lastMessage,
                                            step: step.map { .some($0) }, quietly: true))
                }
                if self.detailed { self.center.setSubagents(subagents, of: id) }
            }
        }
    }

    /// Codex and Cursor threads that went quiet for an hour quit without saying so.
    private func markQuietThreadsStopped() {
        let now = Date()
        for thread in center.threads where thread.tool != .claude && !thread.status.isFinished {
            let last = lastActivity[thread.id] ?? thread.statusSince
            if now.timeIntervalSince(last) > Self.quietLimit {
                requestSettled(thread.id)
                center.apply(.init(id: thread.id, tool: thread.tool, at: now, status: .stopped, quietly: true))
            }
        }
    }

    // MARK: Codex

    private func watchCodex() {
        let folders = accounts.filter { $0.tool == .codex }.map(\.folder)
        guard !folders.isEmpty else { return }
        let reader = codex
        queue.async { [weak self] in
            let updates = reader.catchUp(folders: folders)
            Task { @MainActor in self?.codexRead(updates) }
        }
        let paths = folders.map { $0.appending(path: "sessions").path }
        if let watcher = FolderWatcher(paths: paths, latency: 0.5, queue: queue, onChange: { [weak self] changed in
            let updates = reader.read(changed: changed, folders: folders)
            guard !updates.isEmpty else { return }
            Task { @MainActor in self?.codexRead(updates) }
        }) {
            watchers.append(watcher)
        }
    }

    func codexRead(_ updates: [CodexReader.ThreadUpdate]) {
        guard !stopped else { return }
        // Threads first, so a subagent seen in the same read finds its parent.
        for item in updates.sorted(by: { $0.parentThreadID == nil && $1.parentThreadID != nil }) {
            let id = "codex:\(item.threadID)"
            if let parent = item.parentThreadID {
                codexSubagentRead(item, id: id, parentID: "codex:\(parent)")
                continue
            }
            lastActivity[id] = item.modified
            var update = AgentsCenter.Update(id: id, tool: .codex, at: item.statusAt ?? item.modified,
                                             accountID: AgentAccount(tool: .codex, folder: item.folder).id,
                                             title: item.title, lastMessage: item.lastMessage, cwd: item.cwd, hostBundleID: item.hostBundleID)
            let existing = center.thread(id)
            if pending[id] != nil {
                // Waiting for Allow / Deny: only a finished turn changes that (answered elsewhere).
                guard let status = item.status, status.isFinished else {
                    update.step = .some(item.step)
                    update.quietly = true
                    center.apply(update)
                    continue
                }
                requestSettled(id)
            }
            let stale = lastHookEvent[id].map { (item.statusAt ?? item.modified) < $0 } ?? false
            if let status = item.status, !stale, !(existing?.status.needsYou == true && status == .working && item.isCatchUp) {
                update.status = status
            }
            if item.status == .working { update.step = .some(item.step) }
            if existing == nil {
                guard let status = item.status else { continue }
                // At launch, a finished thread shows (seen) only if it finished in the last half hour.
                if item.isCatchUp, status.isFinished, Date().timeIntervalSince(item.statusAt ?? item.modified) > AgentsCenter.keepAfterSeen { continue }
                // Still "working" in a rollout untouched for an hour: it quit without a word (a crash).
                if item.isCatchUp, !status.isFinished, Date().timeIntervalSince(item.modified) > Self.quietLimit { continue }
                update.quietly = item.isCatchUp
            }
            center.apply(update)
        }
        // Resolve the tree after every batch; parent and child files needn't arrive together.
        var grouped: [String: [AgentSubagent]] = [:]
        for (id, entry) in codexSubagents where !entry.agent.status.isFinished {
            var parent = entry.parentID
            var visited: Set<String> = [id]
            while let ancestor = codexSubagents[parent], visited.insert(parent).inserted { parent = ancestor.parentID }
            guard !visited.contains(parent) else { continue }
            grouped[parent, default: []].append(entry.agent)
        }
        for thread in center.threads where thread.tool == .codex {
            center.setSubagents(grouped[thread.id] ?? [], of: thread.id)
        }
    }

    /// Reopening the list also picks up names changed while a thread wasn't writing its rollout.
    private func refreshCodexTitles() {
        let threads = center.threads.filter { $0.tool == .codex }
        let folders = accounts.filter { $0.tool == .codex }.map(\.folder)
        let reader = codex
        queue.async { [weak self] in
            let titles = threads.compactMap { thread -> (String, String)? in
                let id = String(thread.id.dropFirst("codex:".count))
                guard let title = folders.lazy.compactMap({ reader.refreshTitle(folder: $0, threadID: id) }).first else { return nil }
                return (thread.id, title)
            }
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                for (id, title) in titles where self.center.thread(id) != nil {
                    self.center.apply(.init(id: id, tool: .codex, at: .now, title: title, quietly: true))
                }
            }
        }
    }
}

extension LiveAgentSources {
    /// A spawned subagent: under its parent while it works. One that went quiet before launch is gone.
    fileprivate func codexSubagentRead(_ item: CodexReader.ThreadUpdate, id: String, parentID: String) {
        // Its hooks may have come in before its rollout said what it is.
        codexSpawned.insert(item.threadID)
        if center.thread(id) != nil { center.forget(id) }
        guard let status = item.status,
              !(item.isCatchUp && Date().timeIntervalSince(item.modified) > ClaudeSubagents.quietLimit) else { return }
        codexSubagents[id] = (parentID, AgentSubagent(id: id, title: item.title ?? String(localized: "Subagent", comment: "A Codex spawned agent with no name"),
                                                    status: status, statusSince: item.statusAt ?? item.modified))
    }
}

/// Codex rollouts as read so far, by path. Only touched on the agents file queue.
final class CodexReader: @unchecked Sendable {
    struct ThreadUpdate: Sendable {
        let threadID: String
        let folder: URL
        let cwd: String?
        let title: String?
        let lastMessage: String?
        let status: AgentStatus?
        let statusAt: Date?
        let step: String?
        let hostBundleID: String?
        /// A spawned subagent's parent thread.
        let parentThreadID: String?
        let modified: Date
        /// From the first look at a file (at launch), not something that just happened.
        let isCatchUp: Bool
    }

    private var rollouts: [String: CodexRollout] = [:]
    private var titles: [String: String] = [:]
    /// When a title was last looked up (new titles and renames arrive after the first rollout line).
    private var titleCheckedAt: [String: Date] = [:]
    /// The newest rate limits seen, by account folder path.
    private(set) var rateLimits: [String: CodexRateLimits] = [:]

    /// Threads active in the last two hours, from their files' heads and tails.
    func catchUp(folders: [URL]) -> [ThreadUpdate] {
        let recent = Date().addingTimeInterval(-2 * 3600)
        var updates: [ThreadUpdate] = []
        for folder in folders {
            for url in Self.recentRollouts(in: folder, since: recent) {
                var rollout = CodexRollout()
                rollout.readTail(url)
                rollouts[url.path] = rollout
                if let update = threadUpdate(rollout, folder: folder, url: url, catchUp: true) { updates.append(update) }
            }
        }
        return updates
    }

    func read(changed paths: [String], folders: [URL]) -> [ThreadUpdate] {
        var updates: [ThreadUpdate] = []
        for path in Set(paths) where path.hasSuffix(".jsonl") && (path as NSString).lastPathComponent.hasPrefix("rollout-") {
            guard let folder = folders.first(where: { path.hasPrefix($0.standardizedFileURL.path + "/") }) else { continue }
            let url = URL(fileURLWithPath: path)
            var rollout = rollouts[path] ?? CodexRollout()
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
            if size < rollout.offset { rollout = CodexRollout() }
            guard rollout.read(url) else {
                rollouts[path] = rollout
                continue
            }
            rollouts[path] = rollout
            if let update = threadUpdate(rollout, folder: folder, url: url, catchUp: false) { updates.append(update) }
        }
        return updates
    }

    private func threadUpdate(_ rollout: CodexRollout, folder: URL, url: URL, catchUp: Bool) -> ThreadUpdate? {
        if let limits = rollout.rateLimits, limits.seenAt > (rateLimits[folder.path]?.seenAt ?? .distantPast) {
            rateLimits[folder.path] = limits
        }
        // Automatic reviews aren't shown at all; spawned subagents show under their thread.
        guard let threadID = rollout.threadID, !rollout.isHelper || rollout.parentThreadID != nil else { return nil }
        if rollout.parentThreadID != nil {
            titles[threadID] = rollout.subagentTitle ?? ""
        } else if titles[threadID] == nil || Date().timeIntervalSince(titleCheckedAt[threadID] ?? .distantPast) > 30 {
            _ = refreshTitle(folder: folder, threadID: threadID)
        }
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .now
        return ThreadUpdate(threadID: threadID, folder: folder, cwd: rollout.cwd, title: titles[threadID].flatMap { $0.isEmpty ? nil : $0 },
                            lastMessage: rollout.lastMessage,
                            status: rollout.status, statusAt: rollout.statusAt, step: rollout.step,
                            hostBundleID: rollout.hostBundleID, parentThreadID: rollout.parentThreadID,
                            modified: modified, isCatchUp: catchUp)
    }

    func refreshTitle(folder: URL, threadID: String) -> String? {
        let title = CodexThreadTitles.title(folder: folder, threadID: threadID)
        titles[threadID] = title ?? ""
        titleCheckedAt[threadID] = .now
        return title
    }

    /// Rollouts changed since `date`, in today's and yesterday's day folders (`sessions/YYYY/MM/DD`).
    static func recentRollouts(in folder: URL, since date: Date) -> [URL] {
        let calendar = Calendar(identifier: .gregorian)
        let days = [Date(), Date().addingTimeInterval(-86_400)].map { calendar.dateComponents([.year, .month, .day], from: $0) }
        var urls: [URL] = []
        for day in Set(days.map { String(format: "%04d/%02d/%02d", $0.year ?? 0, $0.month ?? 0, $0.day ?? 0) }) {
            let dayFolder = folder.appending(path: "sessions/\(day)", directoryHint: .isDirectory)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dayFolder.path)) ?? []
            for name in names where name.hasPrefix("rollout-") && name.hasSuffix(".jsonl") {
                let url = dayFolder.appending(path: name)
                if let modified = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, modified > date {
                    urls.append(url)
                }
            }
        }
        return urls
    }
}
