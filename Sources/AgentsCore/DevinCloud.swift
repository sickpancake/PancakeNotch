import AppKit
import Foundation
import Observation

/// Devin's cloud sessions in Agents and AI Usage (issue #55). They run on Devin's servers, so nothing on
/// this Mac hears about them: after the user connects with a personal access token, PancakeNotch asks
/// Devin's API. Off until connected, and it asks only when there's a reason to:
/// - when connecting, when the Agents list or AI Usage comes on screen, and when the user comes back to
///   the Mac or switches apps (at most every two minutes);
/// - and, only while a session works or waits for the user, once a minute (one sleeping Task).
/// With every session finished and nobody looking, it doesn't ask at all.
@MainActor
@Observable
public final class DevinCloud {
    public enum Phase: Equatable, Sendable {
        case notConnected
        /// Checking a new key.
        case connecting
        case connected
    }

    public private(set) var phase: Phase
    /// Something to tell the user in Settings (the key stopped working, Devin couldn't be reached).
    public private(set) var problem: String?
    /// The account's name on Devin, once known.
    public private(set) var userName: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: any DevinTokenStore
    @ObservationIgnored private let send: DevinCloudAPI.Send
    @ObservationIgnored private weak var agents: AgentsCenter?
    @ObservationIgnored private weak var usage: UsageCenter?
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var identity: DevinCloudIdentity?
    /// The threads it put in the Agents list, and whether the last check saw each one still going.
    @ObservationIgnored private var shownIDs: Set<String> = []
    @ObservationIgnored private var hasCheckedOnce = false
    @ObservationIgnored private var lastCheck: Date?
    @ObservationIgnored private var checking: Task<Void, Never>?
    @ObservationIgnored private var again = false
    @ObservationIgnored private var next: Task<Void, Never>?
    @ObservationIgnored private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    /// While a session works.
    nonisolated static let workingGap: TimeInterval = 60
    /// While sessions only wait for the user.
    nonisolated static let waitingGap: TimeInterval = 120
    /// After Devin asked to slow down, or couldn't be reached while something runs.
    nonisolated static let slowGap: TimeInterval = 300
    /// The least time between checks caused by switching apps or waking.
    nonisolated static let activityGap: TimeInterval = 120
    /// The least time between checks caused by the list or AI Usage coming on screen.
    nonisolated static let lookGap: TimeInterval = 15
    /// How far back sessions are read (AI Usage's longest range).
    nonisolated static let history: TimeInterval = 31 * 86_400
    nonisolated static let idPrefix = "devin-cloud:"
    private static let connectedKey = "devinCloud.connected"

    public convenience init() {
        self.init(defaults: .standard, store: DevinKeychain(), send: DevinCloudAPI.ephemeralSend)
    }

    /// Not connected, and never asks anything (app-window snapshots).
    public static func preview() -> DevinCloud {
        DevinCloud(defaults: UserDefaults(suiteName: "PancakeNotch.preview.devinCloud") ?? .standard, store: NoStore(),
                   send: { _ in throw URLError(.notConnectedToInternet) })
    }

    private struct NoStore: DevinTokenStore {
        func read() -> String? { nil }
        func save(_ token: String) -> Bool { false }
        func delete() {}
    }

    init(defaults: UserDefaults, store: any DevinTokenStore, send: @escaping DevinCloudAPI.Send) {
        self.defaults = defaults
        self.store = store
        self.send = send
        phase = defaults.bool(forKey: Self.connectedKey) ? .connected : .notConnected
    }

    // MARK: Connecting

    /// Checks the key with Devin, then keeps it in the Keychain. Returns why it didn't work, or nil.
    @discardableResult
    public func connect(token raw: String) async -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("cog_"), key.count > 8, !key.contains(where: \.isWhitespace) else {
            return String(localized: "That isn't a personal access token. It starts with cog_.", comment: "Devin cloud: the pasted key has the wrong form")
        }
        phase = .connecting
        problem = nil
        do throws(DevinCloudAPI.Failure) {
            let found = try await DevinCloudAPI(token: key, send: send).identity()
            guard found.sessionsOrg != nil else {
                phase = .notConnected
                return String(localized: "Devin didn't say which organization this token belongs to.", comment: "Devin cloud: connect failed")
            }
            guard store.save(key) else {
                phase = .notConnected
                return String(localized: "The token couldn't be saved in the Keychain.", comment: "Devin cloud: connect failed")
            }
            token = key
            identity = found
            userName = found.userName
            defaults.set(true, forKey: Self.connectedKey)
            phase = .connected
            lastCheck = nil
            resume()
            return nil
        } catch {
            phase = .notConnected
            return switch error {
            case .rejected: String(localized: "Devin didn't accept this token. Check it hasn't expired.", comment: "Devin cloud: connect failed")
            case .slowDown, .unavailable: String(localized: "Couldn't reach Devin. Check your connection and try again.", comment: "Devin cloud: connect failed")
            }
        }
    }

    /// Forgets the key and every cloud session it showed.
    public func disconnect() {
        store.delete()
        defaults.removeObject(forKey: Self.connectedKey)
        phase = .notConnected
        problem = nil
        userName = nil
        token = nil
        identity = nil
        pause()
        forgetShown()
        usage?.setDevinUsage(nil)
    }

    // MARK: Following

    /// What it feeds: the Agents list while Agents is on, AI Usage while that's on (nil: off).
    public func follow(agents: AgentsCenter?, usage: UsageCenter?) {
        if agents !== self.agents {
            forgetShown()
            self.agents?.onListShown = nil
            self.agents = agents
            agents?.onListShown = { [weak self] in self?.checkIfOlder(than: Self.lookGap) }
        }
        if usage !== self.usage {
            self.usage?.setDevinUsage(nil)
            self.usage?.onViewShown = nil
            self.usage = usage
            usage?.onViewShown = { [weak self] in self?.checkIfOlder(than: Self.lookGap) }
        }
        resume()
    }

    private var isFollowing: Bool { phase == .connected && (agents != nil || usage != nil) }

    private func resume() {
        guard isFollowing else { pause(); return }
        // New sessions matter to the Agents list; AI Usage looks again whenever it's opened.
        if agents != nil { watchActivity() } else { stopWatchingActivity() }
        checkIfOlder(than: Self.lookGap)
    }

    private func stopWatchingActivity() {
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }

    private func pause() {
        next?.cancel()
        next = nil
        checking?.cancel()
        checking = nil
        stopWatchingActivity()
    }

    /// Coming back to the Mac, or to another app, is a good moment to look (no timer while idle).
    private func watchActivity() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkIfOlder(than: Self.activityGap) }
            }
            observers.append((workspace, token))
        }
    }

    func checkIfOlder(than gap: TimeInterval, now: Date = .now) {
        guard isFollowing else { return }
        if let lastCheck, now.timeIntervalSince(lastCheck) < gap { return }
        check()
    }

    /// Asks Devin now (or right after the check already on its way).
    func check() {
        guard isFollowing else { return }
        guard checking == nil else { again = true; return }
        next?.cancel()
        next = nil
        checking = Task { [weak self] in
            await self?.run()
            guard let self, !Task.isCancelled else { return }
            self.checking = nil
            if self.again {
                self.again = false
                self.check()
            }
        }
    }

    /// Waits for the check in progress (tests).
    func settle() async {
        while let task = checking { await task.value }
    }

    private func run() async {
        if token == nil { token = store.read() }
        guard let token else {
            problem = String(localized: "The Devin token is missing from the Keychain. Connect again.", comment: "Devin cloud")
            disconnectKeepingProblem()
            return
        }
        let api = DevinCloudAPI(token: token, send: send)
        let now = Date()
        lastCheck = now
        do throws(DevinCloudAPI.Failure) {
            if identity == nil {
                let found = try await api.identity()
                identity = found
                userName = found.userName
            }
            guard let org = identity?.sessionsOrg else { throw DevinCloudAPI.Failure.unavailable }
            let (items, complete) = try await api.sessions(org: org, since: now.addingTimeInterval(-Self.history))
            guard !Task.isCancelled, isFollowing else { return }
            problem = nil
            let mine = items.filter { $0.isArchived != true && ($0.userId == nil || identity?.userId == nil || $0.userId == identity?.userId) }
            show(mine, complete: complete, now: Date())
        } catch {
            guard !Task.isCancelled else { return }
            switch error {
            case .rejected:
                problem = String(localized: "Devin stopped accepting the token. Connect again with a new one.", comment: "Devin cloud")
                disconnectKeepingProblem()
            case .slowDown:
                schedule(after: Self.slowGap)
            case .unavailable:
                problem = String(localized: "Couldn't reach Devin. It tries again when you're back.", comment: "Devin cloud")
                if shownIDs.contains(where: { agents?.thread($0)?.status.isFinished == false }) { schedule(after: Self.slowGap) }
            }
        }
    }

    private func disconnectKeepingProblem() {
        let reason = problem
        disconnect()
        problem = reason
    }

    /// Puts the sessions in the Agents list and AI Usage, then plans the next check.
    func show(_ sessions: [DevinCloudSession], complete: Bool, now: Date) {
        usage?.setDevinUsage(DevinCloudUsage(sessions: sessions.compactMap { session in
            guard let started = session.createdAt else { return nil }
            return .init(id: session.sessionId, title: Self.title(session), started: started, acus: session.acusConsumed ?? 0)
        }, updatedAt: now))

        var stillGoing = false, working = false
        if let agents {
            var seen: Set<String> = []
            for session in sessions {
                guard let mapped = session.agentStatus else { continue }
                let (status, reason) = mapped
                let id = Self.idPrefix + session.sessionId
                let known = agents.thread(id) != nil
                let changed = (session.updatedAt ?? now)
                // A session that finished a while before it was first seen isn't news.
                if !known, status.isFinished, now.timeIntervalSince(changed) > AgentsCenter.keepAfterSeen { continue }
                seen.insert(id)
                if !status.isFinished { stillGoing = true }
                if status == .working { working = true }
                let at = known ? min(now, changed) : (status.isFinished ? changed : (session.createdAt ?? changed))
                agents.apply(.init(
                    id: id, tool: .devin, at: at, title: Self.title(session),
                    status: status, request: .some(status.needsYou ? reason : nil),
                    project: Self.byline(session, reason: status.needsYou ? nil : reason),
                    hostName: String(localized: "the cloud", comment: "Where a cloud agent runs, after 'Devin in'"),
                    link: .some(session.link),
                    // The first look shows what's going on without popping up, except for what needs you.
                    quietly: !hasCheckedOnce && !status.needsYou
                ))
            }
            // A session gone from the list (archived, deleted) while it still ran is over.
            if complete {
                for id in shownIDs.subtracting(seen) {
                    if agents.thread(id)?.status.isFinished == false { agents.ended(id, at: now) }
                }
            }
            shownIDs.formUnion(seen)
        }
        hasCheckedOnce = true
        if working { schedule(after: Self.workingGap) }
        else if stillGoing { schedule(after: Self.waitingGap) }
    }

    /// A check is planned (something runs or waits).
    var hasScheduledCheck: Bool { next != nil }

    private func schedule(after seconds: TimeInterval) {
        next?.cancel()
        next = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.check()
        }
    }

    private func forgetShown() {
        if let agents { for id in shownIDs { agents.forget(id) } }
        shownIDs = []
        hasCheckedOnce = false
    }

    private static func title(_ session: DevinCloudSession) -> String {
        let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? String(localized: "Devin session", comment: "A Devin cloud session without a title") : title
    }

    /// "Devin cloud", then the pull request or why it stopped: "Devin cloud · PR #128 · Merged".
    private static func byline(_ session: DevinCloudSession, reason: String?) -> String {
        [String(localized: "Devin cloud", comment: "Under a Devin cloud session's name"), session.pullRequestLabel, reason]
            .compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Pages

    /// Where to make a personal access token: Devin's Settings › Devin API.
    public static let tokenPage = URL(string: "https://app.devin.ai/settings")!
    /// Devin's own usage page (plan limits and credits live there, not in its API).
    public static let usagePage = URL(string: "https://app.devin.ai/settings/usage")!
}
