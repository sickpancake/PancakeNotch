import Foundation
import Observation
import Stats

/// AI Usage's data: the accounts on this Mac, their plan limits, and what the chosen range adds up to
/// (ADR-0037). Limits follow the tools' own files as they change. The token history is read only
/// while AI Usage or Statistics is on screen, from where the last read stopped.
@MainActor
@Observable
public final class UsageCenter {
    public let settings: AgentsSettings
    public let isPractice: Bool

    /// Grouped by tool (Claude Code, then Codex), the standard folder first.
    public private(set) var accounts: [AgentAccount] = []
    /// By account ID.
    public private(set) var limits: [String: AccountLimits] = [:]
    /// The selected account and range.
    public private(set) var totals: UsageTotals = .zero
    /// Reading the history for the first time (0…1), or nil.
    public private(set) var firstReadProgress: Double?
    /// Changes even when an import only affects days outside the selected notch range.
    public private(set) var historyRevision = 0

    /// The account shown (falls back to all accounts when the saved one is gone).
    public var selection: AccountSelection {
        get {
            if case .account(let id) = settings.selection, !accounts.contains(where: { $0.id == id }) { return .all }
            return settings.selection
        }
        set {
            settings.selection = newValue
            refreshTotals()
        }
    }

    public var range: UsageRange {
        get { settings.range }
        set {
            settings.range = newValue
            refreshTotals()
        }
    }

    /// The account shown, or nil for all of them. With only one account, "all" is that one.
    public var selectedAccount: AgentAccount? {
        guard case .account(let id) = selection else { return accounts.count == 1 ? accounts.first : nil }
        return accounts.first { $0.id == id }
    }

    /// The accounts shown with `selection`: one, or every account.
    public var shownAccounts: [AgentAccount] {
        selectedAccount.map { [$0] } ?? accounts
    }

    /// A tool has two or more accounts: the pill and rows show initials.
    public func hasSeveralAccounts(_ tool: AgentTool) -> Bool {
        accounts.count { $0.tool == tool } > 1
    }

    /// Every shown account pays per token, so the money is a real cost, not what a plan's tokens would cost.
    public var paysPerToken: Bool {
        let shown = shownAccounts
        return !shown.isEmpty && shown.allSatisfy { $0.billing == .apiKey }
    }

    /// "API value", or "Cost" when every shown account pays per token.
    public var moneyLabel: String {
        if paysPerToken { return shownAccounts[0].moneyLabel }
        return AgentAccount(tool: .claude, folder: URL(fileURLWithPath: "/")).moneyLabel
    }

    /// What the closed notch's ear shows, as picked in Settings: the followed limit of the followed
    /// account (of all of them, the one with the least left), always or only while under 10% left.
    public var earReading: NearLimit? {
        _ = limitsRevision
        guard settings.earMode != .never else { return nil }
        let now = Date()
        return followedAccounts.compactMap { account -> NearLimit? in
            guard let limit = limits[account.id]?.followed(settings.earLimit, now: now),
                  settings.earMode == .always || limit.leftPercent(now: now) < Self.nearLimitPercent else { return nil }
            return NearLimit(account: account, limit: limit)
        }
        .min { $0.limit.leftPercent(now: now) < $1.limit.leftPercent(now: now) }
    }

    /// The account picked in Settings for the closed notch, or every account (also when it's gone).
    private var followedAccounts: [AgentAccount] {
        if case .account(let id) = settings.earAccount, let account = accounts.first(where: { $0.id == id }) { return [account] }
        return accounts
    }

    /// Told once when a followed account drops under 10% left on the followed limit (peek); again only
    /// after it resets.
    @ObservationIgnored public var onNearLimit: (@MainActor (NearLimit) -> Void)?
    /// A user action in the practice notch, for the lessons.
    @ObservationIgnored public var onPracticeEvent: (@MainActor (UsagePracticeEvent) -> Void)?

    public nonisolated static let nearLimitPercent: Double = 10

    @ObservationIgnored private var live: LiveUsageSources?
    @ObservationIgnored private var warned: Set<String> = []
    private var limitsRevision = 0
    @ObservationIgnored private var resetTask: Task<Void, Never>?
    /// Where the token history is kept; nil keeps none (snapshots).
    @ObservationIgnored private let stats: StatsStore?
    /// How many views showing the history are on screen (AI Usage and Statistics can both be).
    @ObservationIgnored private var viewers = 0

    public init(settings: AgentsSettings, stats: StatsStore?) {
        self.settings = settings
        self.stats = stats
        isPractice = false
    }

    private init(practiceSettings: AgentsSettings) {
        settings = practiceSettings
        stats = nil
        isPractice = true
    }

    // MARK: Running

    /// Finds the accounts and follows their limits (AI Usage or Agents was switched on).
    public func start() {
        guard !isPractice, live == nil else { return }
        let sources = LiveUsageSources(center: self, stats: stats)
        live = sources
        sources.start()
        if viewers > 0 { sources.setVisible(true) }
    }

    public func stop() {
        resetTask?.cancel()
        resetTask = nil
        live?.stop()
        live = nil
        accounts = []
        limits = [:]
        totals = .zero
        firstReadProgress = nil
        warned = []
    }

    /// AI Usage (or Statistics) is on screen: catch up on the token history and keep it live.
    public func viewShown() {
        viewers += 1
        live?.setVisible(true)
    }

    public func viewHidden() {
        viewers = max(0, viewers - 1)
        if viewers == 0 { live?.setVisible(false) }
    }

    /// Looks for account folders again (one was added or removed in Settings).
    public func refreshAccounts() {
        live?.refreshAccounts()
    }

    /// Tokens and money per day for the last `days` days, oldest first (the Statistics chart).
    public func daily(days: Int) async -> [DailyUsage] {
        guard let live else { return isPractice ? PracticeUsage.daily(days: days, selection: selection) : [] }
        return await live.daily(days: days, accountIDs: shownAccounts.map(\.id))
    }

    /// Tokens and money per model for the last `days` days, biggest first (the Statistics page's top
    /// models, which follow its own range rather than AI Usage's).
    public func models(days: Int) async -> [ModelUsage] {
        guard let live else { return isPractice ? PracticeUsage.totals(for: selection, days: days).models : [] }
        return await live.models(days: days, accountIDs: shownAccounts.map(\.id))
    }

    // MARK: Updates from the sources

    func setAccounts(_ found: [AgentAccount]) {
        accounts = found.map { account in
            var named = account
            if let nickname = settings.nicknames[account.id] { named.name = nickname }
            return named
        }
        limits = limits.filter { id, _ in accounts.contains { $0.id == id } }
        refreshTotals()
    }

    func setLimits(_ value: AccountLimits, for accountID: String) {
        guard limits[accountID] != value else { return }
        limits[accountID] = value
        checkNearLimit(accountID)
        scheduleReset()
    }

    /// A single wake-up at the next known reset removes an expired ear without polling while idle.
    private func scheduleReset() {
        resetTask?.cancel()
        let now = Date()
        guard !isPractice, let next = limits.values.flatMap(\.limits).compactMap(\.resetsAt).filter({ $0 > now }).min() else {
            resetTask = nil
            return
        }
        resetTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(next.timeIntervalSince(now))) } catch { return }
            guard let self else { return }
            self.limitsRevision += 1
            for account in self.accounts { self.checkNearLimit(account.id) }
            self.scheduleReset()
        }
    }

    func setTotals(_ value: UsageTotals) {
        if totals != value { totals = value }
    }

    func setFirstReadProgress(_ value: Double?) {
        if firstReadProgress != value { firstReadProgress = value }
    }

    func historyChanged() { historyRevision += 1 }

    /// Statistics was cleared; reload the visible totals after the database finishes its queued clear.
    public func statisticsCleared() {
        historyChanged()
        refreshTotals()
    }

    /// Stop an in-progress first import from bringing cleared history back.
    public func statisticsWillClear() {
        let now = Date()
        settings.historyClearedAt = now
        live?.discardHistory(before: now)
    }

    /// Asks for the selected range's totals again (selection, range or history changed).
    func refreshTotals() {
        if isPractice {
            totals = PracticeUsage.totals(for: selection, range: range)
            return
        }
        live?.refreshTotals(accountIDs: shownAccounts.map(\.id), days: range.days)
    }

    /// The nickname changed in Settings.
    public func renamed() {
        setAccounts(accounts.map { account in
            var plain = account
            plain.name = account.email ?? account.tool.shortName
            return plain
        })
    }

    private func checkNearLimit(_ accountID: String) {
        guard let account = followedAccounts.first(where: { $0.id == accountID }),
              let limit = limits[accountID]?.followed(settings.earLimit) else { return }
        if limit.leftPercent() >= Self.nearLimitPercent {
            warned.remove(accountID)
        } else if settings.warnsNearLimit, warned.insert(accountID).inserted {
            onNearLimit?(NearLimit(account: account, limit: limit))
        }
    }

    // MARK: Practice

    /// Two pretend Claude accounts and a Codex one, with limits and a month of pretend history.
    public static func practice(now: Date = .now) -> UsageCenter {
        let center = UsageCenter(practiceSettings: AgentsSettings(defaults: UserDefaults(suiteName: "PancakeNotch.practice.usage") ?? .standard))
        center.accounts = PracticeUsage.accounts
        for (id, limits) in PracticeUsage.limits(now: now) { center.limits[id] = limits }
        center.settings.selection = .account(PracticeUsage.accounts[0].id)
        center.settings.range = .today
        center.refreshTotals()
        return center
    }

    /// Picks an account in the practice notch (for the lesson), like the dropdown does.
    public func choose(_ selection: AccountSelection) {
        self.selection = selection
        if isPractice { onPracticeEvent?(.choseAccount) }
    }

    /// The account dropdown opened (for the lesson).
    public func accountsMenuOpened() {
        if isPractice { onPracticeEvent?(.openedAccounts) }
    }

    /// Picks a range, like the switch does.
    public func choose(_ range: UsageRange) {
        self.range = range
        if isPractice { onPracticeEvent?(.choseRange) }
    }
}

/// What the user did in the practice notch, for the lessons.
public enum UsagePracticeEvent: Equatable, Sendable {
    case openedAccounts, choseAccount, choseRange
}
