import AppKit
import Foundation
import Observation

/// Every agent thread PancakeNotch can see, merged from the tools' own files and, after Connect, their
/// hooks (ADR-0037). Event-driven: sources report changes; nothing here runs on a timer. Finished
/// threads are dropped lazily (as long after they were seen as Settings say) whenever something changes
/// or the list is shown.
@MainActor
@Observable
public final class AgentsCenter {
    public let settings: AgentsSettings
    /// Pretend threads for the practice notches (app window, lessons): nothing real is read.
    public let isPractice: Bool

    /// Needs you first (oldest first, so rows with Allow / Deny don't move when another asks), then
    /// working, then finished (newest first). Shown as picked in Settings: its tool not hidden, named the
    /// chosen way, with or without steps and subagents.
    public var threads: [AgentThread] {
        shown.sorted {
            if $0.status.sortRank != $1.status.sortRank { return $0.status.sortRank < $1.status.sortRank }
            if $0.statusSince != $1.statusSince { return $0.status.needsYou ? $0.statusSince < $1.statusSince : $0.statusSince > $1.statusSince }
            return $0.id < $1.id
        }
        .map(presented)
    }

    /// The most urgent thing for the closed notch's ear, or nil when nothing's going on.
    public var attention: AgentsAttention? {
        let values = shown
        let needing = values.count { $0.status.needsYou }
        if needing > 0 { return .needsYou(count: needing) }
        let failed = values.count { $0.status == .failed && !$0.isSeen }
        if failed > 0 { return .failed(count: failed) }
        let unseen = values.count { $0.status.isFinished && !$0.isSeen }
        if unseen > 0 { return .finished(count: unseen) }
        let working = values.count { $0.status == .working }
        return working > 0 ? .working(count: working) : nil
    }

    public var hasFinished: Bool { shown.contains { $0.status.isFinished } }

    /// The threads of the tools not hidden in Settings, without the helpers that show under another.
    private var shown: [AgentThread] {
        let hidden = settings.hiddenTools
        return storage.values.filter { !hidden.contains($0.tool) && ($0.status.needsYou || !isUnderParent($0)) }
    }

    /// A host app's helper whose main conversation is in the list.
    private func isUnderParent(_ thread: AgentThread) -> Bool {
        thread.parentID.map { storage[$0] != nil } ?? false
    }

    /// Told about needs-you and finishes worth a peek (smart rules applied).
    @ObservationIgnored public var onAlert: (@MainActor (AgentAlert) -> Void)?
    /// A user action in the practice notch, for the lessons.
    @ObservationIgnored public var onPracticeEvent: (@MainActor (AgentsPracticeEvent) -> Void)?

    private var storage: [String: AgentThread] = [:]
    @ObservationIgnored private var pendingFinishAlerts: [String: AgentThread] = [:]

    /// File sources finish relationship discovery before deciding whether a completion is a root peek.
    func finishDiscovery() {
        let pending = pendingFinishAlerts
        pendingFinishAlerts = [:]
        for (id, previous) in pending {
            if let thread = storage[id] { alertIfWorthIt(thread, previous: previous) }
        }
    }

    /// Positive host helper boilerplate suppresses finish peeks while its parent record is pending.
    /// It never hides an unresolved conversation or a permission request.
    @ObservationIgnored private var helperEvidence: Set<String> = []

    func noteHelperPrompt(_ prompt: String, for id: String) {
        let header = String(prompt.prefix(100)).components(separatedBy: "\n").first ?? ""
        if header.hasPrefix("Act as the "), header.hasSuffix("sub-agent for this task.") { helperEvidence.insert(id) }
    }

    @ObservationIgnored private var seenAt: [String: Date] = [:]
    /// The process each thread runs in, for "bring its app forward" and "is the user looking at it".
    @ObservationIgnored private var processIDs: [String: pid_t] = [:]
    /// Apps named by the tool when there's no process ID (a Codex rollout's originator).
    @ObservationIgnored private var hostBundleIDs: [String: String] = [:]
    /// Each thread's project folder path, for its branch.
    @ObservationIgnored private var cwds: [String: String] = [:]
    /// Threads whose title came from the tool (not just their project folder).
    @ObservationIgnored private var hasOwnTitle: Set<String> = []
    @ObservationIgnored private var listViewers = 0
    private var listVisible: Bool { listViewers > 0 }
    @ObservationIgnored private var live: LiveAgentSources?
    @ObservationIgnored private var practice: PracticeAgents?

    /// How far back a thread that finished before launch is still shown (and the default time a finished
    /// thread stays after it was seen).
    nonisolated static let keepAfterSeen: TimeInterval = 30 * 60
    /// A finish pops up only after this much work.
    nonisolated static let worthAPeek: TimeInterval = 30

    public init(settings: AgentsSettings) {
        self.settings = settings
        isPractice = false
    }

    private init(practiceSettings: AgentsSettings) {
        settings = practiceSettings
        isPractice = true
    }

    /// Pretend threads (a Claude Code thread working, a Codex one asking to run a command, a finished
    /// Cursor one) that answer Allow / Deny like the real thing.
    public static func practice(now: Date = .now) -> AgentsCenter {
        let center = AgentsCenter(practiceSettings: AgentsSettings(defaults: UserDefaults(suiteName: "PancakeNotch.practice.agents") ?? .standard))
        center.practice = PracticeAgents(center: center)
        center.reset(now: now)
        return center
    }

    /// The practice threads plus one asking to change a file (the off-screen snapshot's review screen).
    public static func practiceWithEdit(now: Date = .now) -> AgentsCenter {
        let center = practice(now: now)
        let thread = PracticeAgents.editingThread(now: now)
        center.storage[thread.id] = thread
        center.hasOwnTitle.insert(thread.id)
        return center
    }

    /// Puts the practice threads back (after a try, or when a lesson starts again).
    public func reset(now: Date = .now) {
        guard isPractice else { return }
        storage = Dictionary(uniqueKeysWithValues: PracticeAgents.threads(now: now).map { ($0.id, $0) })
        seenAt = [:]
        hasOwnTitle = Set(storage.keys)
    }

    // MARK: Running

    /// Starts following the tools (the Agents module was switched on).
    public func start() {
        guard !isPractice, live == nil else { return }
        let sources = LiveAgentSources(center: self)
        live = sources
        sources.start()
        if listVisible { sources.setDetailed(true) }
    }

    /// Stops following them and forgets every thread.
    public func stop() {
        live?.stop()
        live = nil
        storage = [:]
        helperEvidence = []
        pendingFinishAlerts = [:]
        seenAt = [:]
        processIDs = [:]
        hostBundleIDs = [:]
        cwds = [:]
        hasOwnTitle = []
    }

    /// A configured account folder changed. Restart the file sources so both tools follow the new set.
    public func refreshAccounts() {
        guard !isPractice, live != nil else { return }
        live?.stop()
        let sources = LiveAgentSources(center: self)
        live = sources
        sources.start()
        if listVisible { sources.setDetailed(true) }
    }

    /// The list is on screen: finished threads count as seen, and the current steps are read.
    public func listShown() {
        listViewers += 1
        let now = Date()
        for (id, thread) in storage where thread.status.isFinished && !thread.isSeen {
            storage[id]?.isSeen = true
            seenAt[id] = now
        }
        prune(now: now)
        live?.setDetailed(true)
    }

    public func listHidden() {
        listViewers = max(0, listViewers - 1)
        if !listVisible { live?.setDetailed(false) }
    }

    /// "Clear finished": remove completed rows, preserving the ancestors of work still in progress.
    public func clearFinished() {
        let protected = Set(storage.values.filter { !$0.status.isFinished }.flatMap { ancestors(of: $0.id) })
        for (id, thread) in storage where thread.status.isFinished && !protected.contains(id) { forget(id) }
        if isPractice { onPracticeEvent?(.cleared) }
    }

    // MARK: Answering and opening

    /// Allow once / Deny the request `shown` was showing. Nothing happens if it was answered, or another
    /// request took its place, since.
    public func allow(_ shown: AgentThread) { answer(shown, allow: true) }
    public func deny(_ shown: AgentThread) { answer(shown, allow: false) }

    private func answer(_ shown: AgentThread, allow: Bool) {
        let id = shown.id
        guard let approval = storage[id]?.approval, approval == shown.approval else { return }
        if let practice {
            practice.answer(id, allow: allow)
            onPracticeEvent?(allow ? .allowed : .denied)
            return
        }
        live?.answer(threadID: id, requestID: approval.requestID, allow: allow)
    }

    /// Brings the thread's app forward. A pending permission request goes back to the app, so it can
    /// be answered there.
    public func open(_ id: String) {
        guard let thread = storage[id], thread.canOpen else { return }
        if isPractice {
            onPracticeEvent?(.opened)
            return
        }
        live?.handBack(threadID: id)
        hostApp(for: id)?.activate()
    }

    /// The app the thread runs in (Terminal, Ghostty, VS Code, T3 Code, the Codex app…).
    func hostApp(for id: String) -> NSRunningApplication? {
        if let pid = processIDs[id], let app = HostApps.app(containing: pid) { return app }
        if let bundleID = hostBundleIDs[id] {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        }
        return nil
    }

    /// The user is looking at the thread's app (it's in front): no peek, and requests go back to it.
    func isFrontmost(_ id: String) -> Bool {
        guard let app = hostApp(for: id) else { return false }
        return app.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    // MARK: Updates from the sources

    /// What a source learned about one thread. Fields left nil don't change.
    struct Update: Sendable {
        var id: String
        var tool: AgentTool
        var at: Date
        var accountID: String?
        var title: String?
        var lastMessage: String?
        var cwd: String?
        var status: AgentStatus?
        /// `.some(nil)` clears it.
        var step: String??
        /// Ignored while the thread has a pending approval, unless the same update ends it.
        var request: String??
        var approval: PendingApproval??
        var processID: pid_t?
        var hostBundleID: String?
        /// Only adds the thread if it's new (a session seen idle at launch): no alerts.
        var quietly = false
    }

    func apply(_ update: Update, deferFinishAlert: Bool = false) {
        let previous = storage[update.id]
        var thread = previous ?? AgentThread(
            id: update.id, tool: update.tool, title: "", project: "", status: update.status ?? .working,
            statusSince: update.at, isSeen: update.quietly
        )
        if let accountID = update.accountID { thread.accountID = accountID }
        if let cwd = update.cwd, !cwd.isEmpty {
            thread.project = URL(fileURLWithPath: cwd).lastPathComponent
            // The branch can change between turns: look again when one starts.
            if cwd != cwds[update.id] || (update.status == .working && previous?.status != .working) {
                cwds[update.id] = cwd
                thread.branch = GitBranch.name(cwd: cwd)
            }
        }
        if let title = update.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            thread.title = title
            hasOwnTitle.insert(update.id)
        }
        // Until it has a title of its own, it goes by its project folder.
        if !hasOwnTitle.contains(update.id) { thread.title = thread.project.isEmpty ? update.tool.name : thread.project }
        if let message = AgentNames.oneLine(update.lastMessage) { thread.lastMessage = message }
        if let step = update.step { thread.step = step }
        // A pending request's words stay as they arrived until it's answered, handed back or over.
        let endsApproval = update.approval != nil || update.status.map { !$0.needsYou } == true
        if let request = update.request, thread.approval == nil || endsApproval { thread.request = request }
        if let approval = update.approval { thread.approval = approval }
        if let pid = update.processID, pid > 0 { processIDs[update.id] = pid }
        if let bundleID = update.hostBundleID { hostBundleIDs[update.id] = bundleID }

        if let status = update.status, previous == nil || previous?.status != status {
            if status == .working, previous?.status != .working, !(previous?.status.needsYou ?? false) {
                thread.workStarted = update.at
            }
            thread.status = status
            thread.statusSince = update.at
            if !status.needsYou {
                if update.request == nil { thread.request = nil }
                thread.approval = nil
            }
            if status.isFinished {
                thread.subagents = []
                if update.step == nil { thread.step = nil }
                thread.isSeen = update.quietly || listVisible
                if thread.isSeen { seenAt[update.id] = update.at }
            } else {
                thread.isSeen = false
                seenAt[update.id] = nil
            }
        }
        if !isPractice { thread.canOpen = hostApp(for: update.id) != nil }
        storage[update.id] = thread
        if !update.quietly {
            if deferFinishAlert, thread.status.isFinished, let previous, previous.status != thread.status { pendingFinishAlerts[thread.id] = previous }
            else { alertIfWorthIt(thread, previous: previous) }
        }
        prune(now: update.at)
    }

    /// A thread's helpers, all at once (Claude Code's subagent files). Only the working ones are kept.
    func setSubagents(_ subagents: [AgentSubagent], of parentID: String) {
        guard let thread = storage[parentID], !thread.status.isFinished else { return }
        let working = subagents.filter { !$0.status.isFinished }.sorted { $0.statusSince == $1.statusSince ? $0.id < $1.id : $0.statusSince < $1.statusSince }
        if thread.subagents != working { storage[parentID]?.subagents = working }
    }

    /// One helper changed (a Codex spawned agent): kept while it works, dropped once it finishes.
    func updateSubagent(_ subagent: AgentSubagent, of parentID: String) {
        guard var list = storage[parentID]?.subagents else { return }
        list.removeAll { $0.id == subagent.id }
        list.append(subagent)
        setSubagents(list, of: parentID)
    }

    /// The thread's session ended (the tool quit). A working or waiting thread counts as stopped.
    func ended(_ id: String, at date: Date) {
        guard let thread = storage[id] else { return }
        if !thread.subagents.isEmpty { storage[id]?.subagents = [] }
        if thread.status.isFinished { return }
        apply(Update(id: id, tool: thread.tool, at: date, status: .stopped))
    }

    /// Drops a thread without a trace (an idle session that never worked, a practice reset).
    func forget(_ id: String) {
        storage[id] = nil
        helperEvidence.remove(id)
        pendingFinishAlerts[id] = nil
        seenAt[id] = nil
        processIDs[id] = nil
        hostBundleIDs[id] = nil
        cwds[id] = nil
        hasOwnTitle.remove(id)
    }

    func thread(_ id: String) -> AgentThread? { storage[id] }

    /// Every thread, helpers and hidden tools included.
    var allThreads: [AgentThread] { Array(storage.values) }

    /// The thread as Settings say to show it, with retained host descendants among
    /// its subagents (even once its own turn is over: the helpers carry on).
    private func presented(_ thread: AgentThread) -> AgentThread {
        var shown = thread
        shown.title = thread.name(settings.nameStyle)
        shown.byline = thread.byline(settings.detailStyle, name: shown.title)
        if !settings.showsSteps { shown.step = nil }
        if settings.showsSubagents {
            let helpers = storage.values.filter { ancestors(of: $0.id).contains(thread.id) && !$0.status.needsYou }.map { helper in
                AgentSubagent(id: helper.id, title: helper.helperTitle ?? helper.name(settings.nameStyle),
                              status: helper.status, statusSince: helper.statusSince)
            }
            if !helpers.isEmpty {
                shown.subagents = (thread.subagents + helpers).sorted {
                    $0.statusSince == $1.statusSince ? $0.id < $1.id : $0.statusSince < $1.statusSince
                }
            }
        } else {
            shown.subagents = []
        }
        return shown
    }

    /// `childID` is a helper a host app started for `parentID`.
    func setParent(of childID: String, to parentID: String, title: String?) {
        guard childID != parentID, !ancestors(of: parentID).contains(childID), var thread = storage[childID], thread.parentID != parentID else { return }
        thread.parentID = parentID
        thread.helperTitle = title
        storage[childID] = thread
    }

    func clearParent(of id: String) {
        storage[id]?.parentID = nil
        storage[id]?.helperTitle = nil
    }

    /// Ancestor traversal handles descendants consistently and refuses cycles.
    private func ancestors(of id: String) -> [String] {
        var result: [String] = [], seen: Set<String> = [id]
        var next = storage[id]?.parentID
        while let parent = next, seen.insert(parent).inserted {
            result.append(parent)
            next = storage[parent]?.parentID
        }
        return result
    }

    private func alertIfWorthIt(_ thread: AgentThread, previous: AgentThread?) {
        guard thread.status != previous?.status, !settings.hiddenTools.contains(thread.tool), (!isUnderParent(thread) || thread.status.needsYou),
              !isFrontmost(thread.id) else { return }
        switch thread.status {
        case .needsYou where settings.peeksOnNeedsYou:
            onAlert?(AgentAlert(kind: .needsYou, thread: presented(thread)))
        case .done, .failed:
            guard !helperEvidence.contains(thread.id), settings.peeksOnFinish, let previous, !previous.status.isFinished,
                  let started = previous.workStarted ?? thread.workStarted,
                  Date().timeIntervalSince(started) >= Self.worthAPeek else { return }
            onAlert?(AgentAlert(kind: thread.status == .failed ? .failed : .finished, thread: presented(thread)))
        default:
            break
        }
    }

    private func prune(now: Date) {
        guard let keep = settings.keepFinished.interval else { return }
        for (id, seen) in seenAt where now.timeIntervalSince(seen) > keep {
            // Keep every ancestor until its retained descendants have gone, including grandchildren.
            let hasRetainedDescendants = storage.values.contains { $0.id != id && ancestors(of: $0.id).contains(id) }
            if storage[id]?.status.isFinished ?? true, !hasRetainedDescendants { forget(id) }
        }
    }
}

/// What the user did in a practice notch, for the lessons.
public enum AgentsPracticeEvent: Equatable, Sendable {
    case allowed, denied, opened, cleared
}
