import AppKit
import Foundation
import Observation

/// Every agent thread PancakeNotch can see, merged from the tools' own files and, after Connect, their
/// hooks (ADR-0037). Event-driven: sources report changes; nothing here runs on a timer. Finished
/// threads are dropped lazily (30 minutes after they were seen) whenever something changes or the list
/// is shown.
@MainActor
@Observable
public final class AgentsCenter {
    public let settings: AgentsSettings
    /// Pretend threads for the practice notches (app window, lessons): nothing real is read.
    public let isPractice: Bool

    /// Needs you first, then working, then finished; newest first within each.
    public var threads: [AgentThread] {
        storage.values.sorted {
            if $0.status.sortRank != $1.status.sortRank { return $0.status.sortRank < $1.status.sortRank }
            return $0.statusSince > $1.statusSince
        }
    }

    /// The most urgent thing for the closed notch's ear, or nil when nothing's going on.
    public var attention: AgentsAttention? {
        let values = storage.values
        let needing = values.count { $0.status.needsYou }
        if needing > 0 { return .needsYou(count: needing) }
        let unseen = values.count { $0.status.isFinished && !$0.isSeen }
        if unseen > 0 { return .finished(count: unseen) }
        let working = values.count { $0.status == .working }
        return working > 0 ? .working(count: working) : nil
    }

    public var hasFinished: Bool { storage.values.contains { $0.status.isFinished } }

    /// Told about needs-you and finishes worth a peek (smart rules applied).
    @ObservationIgnored public var onAlert: (@MainActor (AgentAlert) -> Void)?
    /// A user action in the practice notch, for the lessons.
    @ObservationIgnored public var onPracticeEvent: (@MainActor (AgentsPracticeEvent) -> Void)?

    private var storage: [String: AgentThread] = [:]
    @ObservationIgnored private var seenAt: [String: Date] = [:]
    /// The process each thread runs in, for "bring its app forward" and "is the user looking at it".
    @ObservationIgnored private var processIDs: [String: pid_t] = [:]
    /// Apps named by the tool when there's no process ID (a Codex rollout's originator).
    @ObservationIgnored private var hostBundleIDs: [String: String] = [:]
    @ObservationIgnored private var listVisible = false
    @ObservationIgnored private var live: LiveAgentSources?
    @ObservationIgnored private var practice: PracticeAgents?

    /// How long a finished thread stays after it was seen.
    static let keepAfterSeen: TimeInterval = 30 * 60
    /// A finish pops up only after this much work.
    static let worthAPeek: TimeInterval = 30

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

    /// Puts the practice threads back (after a try, or when a lesson starts again).
    public func reset(now: Date = .now) {
        guard isPractice else { return }
        storage = Dictionary(uniqueKeysWithValues: PracticeAgents.threads(now: now).map { ($0.id, $0) })
        seenAt = [:]
    }

    // MARK: Running

    /// Starts following the tools (the Agents module was switched on).
    public func start() {
        guard !isPractice, live == nil else { return }
        let sources = LiveAgentSources(center: self)
        live = sources
        sources.start()
    }

    /// Stops following them and forgets every thread.
    public func stop() {
        live?.stop()
        live = nil
        storage = [:]
        seenAt = [:]
        processIDs = [:]
        hostBundleIDs = [:]
    }

    /// The list is on screen: finished threads count as seen, and the current steps are read.
    public func listShown() {
        listVisible = true
        let now = Date()
        for (id, thread) in storage where thread.status.isFinished && !thread.isSeen {
            storage[id]?.isSeen = true
            seenAt[id] = now
        }
        prune(now: now)
        live?.setDetailed(true)
    }

    public func listHidden() {
        listVisible = false
        live?.setDetailed(false)
    }

    /// "Clear finished": every finished thread goes now.
    public func clearFinished() {
        for (id, thread) in storage where thread.status.isFinished { forget(id) }
        if isPractice { onPracticeEvent?(.cleared) }
    }

    // MARK: Answering and opening

    public func allow(_ id: String) { answer(id, allow: true) }
    public func deny(_ id: String) { answer(id, allow: false) }

    private func answer(_ id: String, allow: Bool) {
        guard let thread = storage[id], thread.canAnswer else { return }
        if let practice {
            practice.answer(id, allow: allow)
            onPracticeEvent?(allow ? .allowed : .denied)
            return
        }
        live?.answer(threadID: id, allow: allow)
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
    struct Update {
        var id: String
        var tool: AgentTool
        var at: Date
        var accountID: String?
        var title: String?
        var cwd: String?
        var status: AgentStatus?
        /// `.some(nil)` clears it.
        var step: String??
        var request: String??
        var canAnswer: Bool?
        var processID: pid_t?
        var hostBundleID: String?
        /// Only adds the thread if it's new (a session seen idle at launch): no alerts.
        var quietly = false
    }

    func apply(_ update: Update) {
        let previous = storage[update.id]
        var thread = previous ?? AgentThread(
            id: update.id, tool: update.tool, title: "", project: "", status: update.status ?? .working,
            statusSince: update.at, isSeen: update.quietly
        )
        if let accountID = update.accountID { thread.accountID = accountID }
        if let cwd = update.cwd, !cwd.isEmpty { thread.project = URL(fileURLWithPath: cwd).lastPathComponent }
        if let title = update.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { thread.title = title }
        if thread.title.isEmpty { thread.title = thread.project.isEmpty ? update.tool.name : thread.project }
        if let step = update.step { thread.step = step }
        if let request = update.request { thread.request = request }
        if let canAnswer = update.canAnswer { thread.canAnswer = canAnswer }
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
                thread.canAnswer = false
            }
            if status.isFinished {
                if update.step == nil { thread.step = nil }
                thread.isSeen = update.quietly || listVisible
                if thread.isSeen { seenAt[update.id] = update.at }
            } else {
                thread.isSeen = false
                seenAt[update.id] = nil
            }
        }
        thread.canOpen = hostApp(for: update.id) != nil
        storage[update.id] = thread
        if !update.quietly { alertIfWorthIt(thread, previous: previous) }
        prune(now: update.at)
    }

    /// The thread's session ended (the tool quit). A working or waiting thread counts as stopped.
    func ended(_ id: String, at date: Date) {
        guard let thread = storage[id] else { return }
        if thread.status.isFinished { return }
        apply(Update(id: id, tool: thread.tool, at: date, status: thread.status.needsYou ? .stopped : .done))
    }

    /// Drops a thread without a trace (an idle session that never worked, a practice reset).
    func forget(_ id: String) {
        storage[id] = nil
        seenAt[id] = nil
        processIDs[id] = nil
        hostBundleIDs[id] = nil
    }

    func thread(_ id: String) -> AgentThread? { storage[id] }

    private func alertIfWorthIt(_ thread: AgentThread, previous: AgentThread?) {
        guard thread.status != previous?.status, !isFrontmost(thread.id) else { return }
        switch thread.status {
        case .needsYou where settings.peeksOnNeedsYou:
            onAlert?(AgentAlert(kind: .needsYou, thread: thread))
        case .done, .failed:
            guard settings.peeksOnFinish, let previous, !previous.status.isFinished,
                  let started = previous.workStarted ?? thread.workStarted,
                  Date().timeIntervalSince(started) >= Self.worthAPeek else { return }
            onAlert?(AgentAlert(kind: thread.status == .failed ? .failed : .finished, thread: thread))
        default:
            break
        }
    }

    private func prune(now: Date) {
        for (id, seen) in seenAt where now.timeIntervalSince(seen) > Self.keepAfterSeen {
            if storage[id]?.status.isFinished ?? true { forget(id) }
        }
    }
}

/// What the user did in a practice notch, for the lessons.
public enum AgentsPracticeEvent: Equatable, Sendable {
    case allowed, denied, opened, cleared
}
