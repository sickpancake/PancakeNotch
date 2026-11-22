import AppKit
import Foundation
import Observation

/// Codex cloud tasks and GitHub's coding agent in the Agents list (issue #55), read through each
/// service's own command-line tool after the user turns it on in Settings. Also the CI checks of the
/// pull requests finished cloud agents made (Devin's too), read with the GitHub CLI.
///
/// Like Devin cloud: nothing runs until a service is turned on, and then only while the Agents list
/// is in use: when it's shown, when the Mac or another app comes back, and once a minute while a task
/// works. PancakeNotch never sees the tools' sign-ins.
@MainActor
@Observable
public final class CloudAgents {
    public enum State: Equatable, Sendable {
        case off
        case checking
        case on
        /// Turned on, but the tool isn't there or isn't signed in.
        case unavailable
    }

    public private(set) var states: [CloudService: State] = [:]
    /// Why the last turn-on or check failed, in a few words.
    public private(set) var problems: [CloudService: String] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let run: CloudCommand.Run
    @ObservationIgnored private weak var agents: AgentsCenter?
    @ObservationIgnored private var shownIDs: [CloudService: Set<String>] = [:]
    @ObservationIgnored private var hasCheckedOnce: Set<CloudService> = []
    @ObservationIgnored private var checks: [URL: (checks: PullRequestChecks?, at: Date)] = [:]
    @ObservationIgnored private var lastCheck: Date?
    @ObservationIgnored private var checking: Task<Void, Never>?
    @ObservationIgnored private var again = false
    @ObservationIgnored private var next: Task<Void, Never>?
    @ObservationIgnored private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    nonisolated static let workingGap: TimeInterval = 60
    nonisolated static let waitingGap: TimeInterval = 120
    nonisolated static let activityGap: TimeInterval = 120
    nonisolated static let lookGap: TimeInterval = 15
    /// A tool that went missing or signed out is tried again this often (and when the list is shown).
    nonisolated static let unavailableGap: TimeInterval = 300
    /// Passed or failed checks don't change by themselves: looked at again after this.
    nonisolated static let settledChecksGap: TimeInterval = 600
    private static let enabledKey = "cloudAgents.services"

    public convenience init() { self.init(defaults: .standard, run: CloudCommand.live) }

    init(defaults: UserDefaults, run: @escaping CloudCommand.Run) {
        self.defaults = defaults
        self.run = run
        let enabled = Set((defaults.stringArray(forKey: Self.enabledKey) ?? []).compactMap(CloudService.init))
        for service in CloudService.allCases { states[service] = enabled.contains(service) ? .on : .off }
    }

    public static func preview() -> CloudAgents {
        CloudAgents(defaults: UserDefaults(suiteName: "PancakeNotch.preview.cloudAgents") ?? .standard, run: { _, _ in nil })
    }

    public func state(_ service: CloudService) -> State { states[service] ?? .off }
    public func isOn(_ service: CloudService) -> Bool { state(service) != .off }

    private var enabled: [CloudService] { CloudService.allCases.filter(isOn) }

    // MARK: Turning on and off

    /// Tries the service's tool once; on success it's followed from now on. Returns what went wrong.
    @discardableResult
    public func turnOn(_ service: CloudService) async -> String? {
        states[service] = .checking
        problems[service] = nil
        let output = await run(service.program, service.listArguments)
        guard let output else {
            states[service] = .off
            return problem(service, Self.missing(service))
        }
        guard output.status == 0, service.tasks(from: output.data) != nil else {
            states[service] = .off
            return problem(service, Self.signedOut(service))
        }
        states[service] = .on
        save()
        lastCheck = nil
        resume()
        return nil
    }

    public func turnOff(_ service: CloudService) {
        states[service] = .off
        problems[service] = nil
        save()
        forget(service)
        if service == .github { forgetChecks() }
        if enabled.isEmpty { pause() }
    }

    private func save() {
        defaults.set(CloudService.allCases.filter { states[$0] != .off }.map(\.rawValue), forKey: Self.enabledKey)
    }

    @discardableResult
    private func problem(_ service: CloudService, _ text: String) -> String {
        problems[service] = text
        return text
    }

    static func missing(_ service: CloudService) -> String {
        switch service {
        case .codex: String(localized: "Install Codex, then sign in with ChatGPT", comment: "Codex cloud in Settings: the Codex CLI or app isn't on this Mac")
        case .github: String(localized: "Install the GitHub CLI (gh) first", comment: "GitHub coding agent in Settings: gh isn't on this Mac")
        }
    }

    static func signedOut(_ service: CloudService) -> String {
        switch service {
        case .codex: String(localized: "Sign in to Codex with ChatGPT first", comment: "Codex cloud in Settings: codex cloud list failed")
        case .github: String(localized: "Sign in with gh auth login first", comment: "GitHub coding agent in Settings: gh agent-task list failed")
        }
    }

    // MARK: Following

    /// The Agents list to fill, or nil while the Agents module is off.
    public func follow(agents: AgentsCenter?) {
        if agents !== self.agents {
            for service in CloudService.allCases { forget(service) }
            forgetChecks()
            self.agents?.listShownWatchers["cloud"] = nil
            self.agents = agents
            agents?.listShownWatchers["cloud"] = { [weak self] in self?.checkIfOlder(than: Self.lookGap) }
            lastCheck = nil
        }
        resume()
    }

    private var isFollowing: Bool { agents != nil && !enabled.isEmpty }

    private func resume() {
        guard isFollowing else { pause(); return }
        watchActivity()
        checkIfOlder(than: Self.lookGap)
    }

    private func pause() {
        next?.cancel()
        next = nil
        checking?.cancel()
        checking = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }

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

    func check() {
        guard isFollowing else { return }
        guard checking == nil else { again = true; return }
        next?.cancel()
        next = nil
        checking = Task { [weak self] in
            await self?.look()
            guard let self, !Task.isCancelled else { return }
            self.checking = nil
            if self.again {
                self.again = false
                self.checkIfOlder(than: Self.lookGap)
            }
        }
    }

    /// Waits for the check in progress (tests).
    func settle() async {
        while let task = checking { await task.value }
    }

    /// A check is planned (something works or waits).
    var hasScheduledCheck: Bool { next != nil }

    private func look() async {
        lastCheck = .now
        var gap: TimeInterval?
        for service in enabled {
            let output = await run(service.program, service.listArguments)
            guard !Task.isCancelled, isOn(service) else { return }
            guard let output, output.status == 0, let tasks = service.tasks(from: output.data) else {
                lost(service, because: output == nil ? Self.missing(service) : Self.signedOut(service))
                gap = min(gap ?? Self.unavailableGap, Self.unavailableGap)
                continue
            }
            states[service] = .on
            problems[service] = nil
            if let wanted = show(tasks, from: service, now: .now) { gap = min(gap ?? wanted, wanted) }
        }
        if state(.github) == .on, let wanted = await lookAtChecks(now: .now) { gap = min(gap ?? wanted, wanted) }
        if let gap { schedule(after: gap) }
    }

    /// The tool went missing or signed out: its rows can't be trusted any more, so they go (they come
    /// back with the next good read), and it's tried again now and then until it works.
    private func lost(_ service: CloudService, because text: String) {
        states[service] = .unavailable
        problem(service, text)
        forget(service)
        if service == .github { forgetChecks() }
    }

    /// Puts `tasks` in the list; returns how soon to look again, nil when nothing works or waits.
    func show(_ tasks: [CloudTask], from service: CloudService, now: Date) -> TimeInterval? {
        guard let agents else { return nil }
        var seen: Set<String> = []
        var working = false, going = false
        for task in tasks {
            let id = service.idPrefix + task.id
            let previous = agents.thread(id)
            let changed = min(now, task.changed ?? now)
            if previous == nil, task.status.isFinished, now.timeIntervalSince(changed) > AgentsCenter.keepAfterSeen { continue }
            seen.insert(id)
            if task.status == .working { working = true }
            if !task.status.isFinished { going = true }
            let at = previous == nil && task.status == .working ? (task.started ?? changed) : changed
            agents.apply(.init(
                id: id, tool: service.tool, at: at, title: task.title,
                status: task.status, request: .some(task.status.needsYou ? task.reason : nil),
                project: task.byline ?? service.name,
                hostName: String(localized: "the cloud", comment: "Where a cloud agent runs, after 'Devin in'"),
                link: .some(task.link), pullRequest: .some(task.status.isFinished ? task.pullRequest : nil),
                quietly: !hasCheckedOnce.contains(service) && !task.status.needsYou
            ))
        }
        // A task gone from the list while it still ran is over.
        for id in (shownIDs[service] ?? []).subtracting(seen) where agents.thread(id)?.status.isFinished == false {
            agents.ended(id, at: now)
        }
        shownIDs[service, default: []].formUnion(seen)
        hasCheckedOnce.insert(service)
        return working ? Self.workingGap : going ? Self.waitingGap : nil
    }

    /// Reads the checks of every finished cloud agent's GitHub pull request that may have changed.
    /// Returns how soon to look again, nil when none still run.
    func lookAtChecks(now: Date) async -> TimeInterval? {
        guard let agents else { return nil }
        var running = false
        for thread in agents.cloudPullRequests() {
            guard let pr = thread.pullRequest, pr.host()?.lowercased() == "github.com" else { continue }
            if let known = checks[pr], known.checks != .running, now.timeIntervalSince(known.at) < Self.settledChecksGap {
                agents.setChecks(known.checks, for: thread.id)
                continue
            }
            guard let output = await run(.gh, ["pr", "checks", pr.absoluteString, "--json", "bucket"]) else { return nil }
            guard !Task.isCancelled, isOn(.github) else { return nil }
            // `gh pr checks` exits with 8 while checks run and 1 when one failed; the JSON tells.
            let found = PullRequestChecks.from(output.data)
            checks[pr] = (found, now)
            agents.setChecks(found, for: thread.id)
            if found == .running { running = true }
        }
        return running ? Self.workingGap : nil
    }

    private func schedule(after seconds: TimeInterval) {
        next?.cancel()
        next = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.check()
        }
    }

    private func forget(_ service: CloudService) {
        for id in shownIDs[service] ?? [] { agents?.forget(id) }
        shownIDs[service] = nil
        hasCheckedOnce.remove(service)
    }

    private func forgetChecks() {
        checks = [:]
        agents?.clearChecks()
    }
}
