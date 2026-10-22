import Foundation
import os
import Stats

/// Follows the real accounts for `UsageCenter` (ADR-0037):
/// - limits always, from the files the tools rewrite when they learn them (`.claude.json`, Codex rollouts);
/// - the token history only while AI Usage or Statistics is on screen, into the statistics file.
/// All event-driven. Files are read on a background queue; the center is updated on the main actor.
@MainActor
final class LiveUsageSources {
    private unowned let center: UsageCenter
    private let stats: StatsStore?
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let queue = DispatchQueue(label: "io.github.sickpancake.PancakeNotch.usage.files", qos: .utility)
    /// Asking Codex for its limits can take seconds: it waits here, not in front of the file reading.
    private let askQueue = DispatchQueue(label: "io.github.sickpancake.PancakeNotch.usage.codex", qos: .utility)

    private var accounts: [AgentAccount] = []
    /// Each Claude account's settings file, where Claude Code keeps its last-known limits.
    private var configFiles: [String: URL] = [:]
    /// When Codex was last asked for each account's limits.
    private var askedCodex: [String: Date] = [:]
    /// Codex isn't asked again sooner than this.
    private static let askAgainAfter: TimeInterval = 60
    private var limitWatchers: [FolderWatcher] = []
    private var configWatchers: [FileChangeWatcher] = []
    private var historyWatcher: FolderWatcher?
    private var ledger: UsageLedger?
    private var visible = false
    private var scanning = false
    private var scanAgain = false
    /// Keep Codex's temporary process apart from the initial history import.
    private var refreshCodexAfterScan = false
    /// Drops totals that arrive after a newer question.
    private var totalsAsked = 0
    private var stopped = false
    private var discardedBefore: Date?

    /// A first read this big shows its progress.
    nonisolated private static let bigRead: UInt64 = 32 * 1024 * 1024

    init(center: UsageCenter, stats: StatsStore?) {
        self.center = center
        self.stats = stats
    }

    func start() {
        discardedBefore = center.settings.historyClearedAt
        refreshAccounts()
    }

    func stop() {
        stopped = true
        ledger?.cancelled.withLock { $0 = true }
        stopWatchingLimits()
        stopWatchingHistory()
    }

    // MARK: Accounts and limits

    func refreshAccounts() {
        let found = AccountFinder.find(home: home, added: center.settings.addedFolders).filter(\.tool.hasUsage)
        let home = home
        queue.async { [weak self] in
            let read = found.map { Self.read($0, home: home) }
            Task { @MainActor in self?.accountsRead(read) }
        }
    }

    private struct ReadAccount: Sendable {
        let account: AgentAccount
        let limits: AccountLimits
        let configFile: URL?
    }

    private nonisolated static func read(_ found: AccountFinder.Found, home: URL) -> ReadAccount {
        switch found.tool {
        case .claude:
            let file = AccountFinder.claudeConfigFile(for: found.folder, home: home)
            let identity = AccountIdentity.claude(configFile: file)
            return ReadAccount(account: AgentAccount(tool: .claude, folder: found.folder, email: identity?.email,
                                                     plan: identity?.plan, billing: identity?.billing ?? .unknown),
                               limits: identity?.limits ?? .notYet, configFile: file)
        default:
            let identity = AccountIdentity.codex(folder: found.folder)
            let rates = identity.billing == .apiKey ? nil : CodexLimitsLog.latest(in: found.folder)
            return ReadAccount(account: AgentAccount(tool: .codex, folder: found.folder, email: identity.email,
                                                     plan: identity.plan ?? rates?.plan.map(AccountIdentity.codexPlan),
                                                     billing: identity.billing),
                               limits: codexLimits(rates, billing: identity.billing), configFile: nil)
        }
    }

    private nonisolated static func codexLimits(_ rates: CodexRateLimits?, billing: AgentAccount.Billing) -> AccountLimits {
        if billing == .apiKey { return AccountLimits(state: .noLimits) }
        guard let rates else { return .notYet }
        return AccountLimits(state: .available, limits: rates.limits, updatedAt: rates.seenAt)
    }

    private func accountsRead(_ read: [ReadAccount]) {
        guard !stopped else { return }
        accounts = read.map(\.account)
        configFiles = Dictionary(uniqueKeysWithValues: read.compactMap { item in item.configFile.map { (item.account.id, $0) } })
        center.setAccounts(accounts)
        for item in read { center.setLimits(item.limits, for: item.account.id) }
        watchLimits(read)
        if visible { watchHistory() }
        // One initial import, even before the history view is opened.
        scan()
    }

    private func watchLimits(_ read: [ReadAccount]) {
        stopWatchingLimits()
        for item in read {
            let id = item.account.id
            if let file = item.configFile {
                // Claude Code rewrites its settings file whenever it learns the limits again.
                configWatchers.append(FileChangeWatcher(path: file.path, queue: queue) { [weak self] in
                    guard let identity = AccountIdentity.claude(configFile: file) else { return }
                    Task { @MainActor in self?.claudeIdentityChanged(identity, accountID: id) }
                })
            } else {
                let folder = item.account.folder
                let billing = item.account.billing
                guard billing != .apiKey else { continue }
                // Codex reports its limits with every answer: look at the rollouts it just wrote.
                let sessions = folder.appending(path: "sessions").path
                if let watcher = FolderWatcher(paths: [sessions], latency: 5, queue: queue, onChange: { [weak self] paths in
                    let rates = paths.filter { $0.hasSuffix(".jsonl") }.compactMap { CodexLimitsLog.read(URL(fileURLWithPath: $0)) }
                        .max { $0.seenAt < $1.seenAt }
                    guard let rates else { return }
                    Task { @MainActor in self?.codexLimitsChanged(rates, accountID: id) }
                }) {
                    limitWatchers.append(watcher)
                }
            }
        }
    }

    private func stopWatchingLimits() {
        let folders = limitWatchers
        limitWatchers = []
        queue.async { for watcher in folders { watcher.stop() } }
        for watcher in configWatchers { watcher.stop() }
        configWatchers = []
    }

    private func claudeIdentityChanged(_ identity: AccountIdentity.Claude, accountID: String) {
        guard !stopped, let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        let old = accounts[index]
        let account = AgentAccount(tool: .claude, folder: old.folder, email: identity.email, plan: identity.plan, billing: identity.billing)
        if account.email != old.email || account.plan != old.plan || account.billing != old.billing {
            accounts[index] = account
            center.setAccounts(accounts)
        }
        center.setLimits(identity.limits, for: accountID)
    }

    private func codexLimitsChanged(_ rates: CodexRateLimits, accountID: String) {
        guard !stopped, let account = accounts.first(where: { $0.id == accountID }) else { return }
        // A rollout read late (an old thread written to again) mustn't replace newer limits.
        if let shown = center.limits[accountID]?.updatedAt, shown > rates.seenAt { return }
        center.setLimits(Self.codexLimits(rates, billing: account.billing), for: accountID)
    }

    /// AI Usage was opened: read Claude's saved limits again, and ask Codex for its current ones. Claude
    /// Code only learns new limits when it sends a request, so its show "as of" when they're old.
    private func refreshLimits() {
        let now = Date()
        if scanning { refreshCodexAfterScan = true }
        for account in accounts {
            let id = account.id
            if let file = configFiles[id] {
                queue.async { [weak self] in
                    guard let identity = AccountIdentity.claude(configFile: file) else { return }
                    Task { @MainActor in self?.claudeIdentityChanged(identity, accountID: id) }
                }
            } else if !scanning, account.tool == .codex, account.billing != .apiKey,
                      now.timeIntervalSince(askedCodex[id] ?? .distantPast) > Self.askAgainAfter {
                askedCodex[id] = now
                let folder = account.folder, home = home
                askQueue.async { [weak self] in
                    guard let rates = CodexLimitsRequest.read(folder: folder, home: home) else { return }
                    Task { @MainActor in self?.codexLimitsChanged(rates, accountID: id) }
                }
            }
        }
    }

    // MARK: Token history

    /// AI Usage or Statistics appeared (catch up and follow the logs) or went away (stop following).
    func setVisible(_ value: Bool) {
        guard value != visible, !stopped else { return }
        visible = value
        if value {
            watchHistory()
            scan()
            refreshLimits()
        } else {
            refreshCodexAfterScan = false
            stopWatchingHistory()
        }
    }

    private func watchHistory() {
        stopWatchingHistory()
        let paths = accounts.flatMap { account in
            (account.tool == .claude ? ["projects"] : ["sessions", "archived_sessions"]).map { account.folder.appending(path: $0).path }
        }
        historyWatcher = FolderWatcher(paths: paths, latency: 2, queue: queue) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    private func stopWatchingHistory() {
        guard let watcher = historyWatcher else { return }
        historyWatcher = nil
        queue.async { watcher.stop() }
    }

    /// Reads whatever the logs gained since last time, then asks for the totals again. One read at a time;
    /// changes during a read start another after it.
    private func scan() {
        guard let stats, !stopped else { return }
        guard !scanning else {
            scanAgain = true
            return
        }
        scanning = true
        guard let ledger else {
            // The first time: learn how far each file was read before.
            Task { [weak self] in
                let progress = await stats.aiFileProgress()
                guard let self, !self.stopped else { return }
                self.ledger = UsageLedger(stats: stats, progress: progress)
                if let date = self.discardedBefore { self.ledger?.discardHistory(before: date) }
                self.scanning = false
                self.scan()
            }
            return
        }
        let shown = accounts.map { UsageLedger.Account(id: $0.id, tool: $0.tool, folder: $0.folder) }
        queue.async { [weak self] in
            let files = ledger.unread(shown)
            let total = files.reduce(0) { $0 + $1.unread }
            var done: UInt64 = 0
            var reported = -1
            for file in files {
                guard !ledger.cancelled.withLock({ $0 }) else { break }
                ledger.read(file)
                done += file.unread
                // Every 2%, for a read big enough to take a moment.
                let percent = Int(Double(done) / Double(max(total, 1)) * 50)
                if total >= Self.bigRead, percent != reported {
                    reported = percent
                    let progress = Double(percent) / 50
                    Task { @MainActor [weak self] in
                        guard let self, !self.stopped else { return }
                        self.center.setFirstReadProgress(progress)
                    }
                }
            }
            Task { @MainActor [weak self] in self?.scanned() }
        }
    }

    private func scanned() {
        scanning = false
        guard !stopped else { return }
        center.setFirstReadProgress(nil)
        center.historyChanged()
        center.refreshTotals()
        if scanAgain, visible {
            scanAgain = false
            scan()
        } else if visible, refreshCodexAfterScan {
            refreshCodexAfterScan = false
            refreshLimits()
        }
    }

    func refreshTotals(accountIDs: [String], days: Int) {
        guard let stats else {
            center.setTotals(.zero)
            return
        }
        totalsAsked += 1
        let asked = totalsAsked
        Task { [weak self] in
            let rows = await stats.aiTotals(accounts: accountIDs, days: days)
            guard let self, self.totalsAsked == asked, !self.stopped else { return }
            self.center.setTotals(Self.totals(rows))
        }
    }

    /// Rows per stored model name → one per model as shown ("claude-opus-5-5" and its dated name are one).
    nonisolated static func totals(_ rows: [AIModelTotal]) -> UsageTotals {
        var models: [String: ModelUsage] = [:]
        var totals = UsageTotals()
        for row in rows {
            let name = ModelPrices.displayName(row.model)
            models[name, default: ModelUsage(name: name, tokens: 0, cost: 0)].tokens += row.tokens
            models[name]?.cost += row.cost
            totals.tokens += row.tokens
            totals.cost += row.cost
            totals.unpricedTokens += row.unpricedTokens
        }
        totals.models = models.values.sorted { $0.tokens > $1.tokens }
        return totals
    }

    func daily(days: Int, accountIDs: [String]) async -> [DailyUsage] {
        guard let stats else { return [] }
        return await stats.aiDaily(accounts: accountIDs, days: days).map { DailyUsage(day: $0.day, tokens: $0.tokens, cost: $0.cost) }
    }

    func models(days: Int, accountIDs: [String]) async -> [ModelUsage] {
        guard let stats else { return [] }
        return Self.totals(await stats.aiTotals(accounts: accountIDs, days: days)).models
    }

    func discardHistory(before date: Date) {
        discardedBefore = date
        ledger?.discardHistory(before: date)
    }
}
