import AppKit
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
    @ObservationIgnored private var discoveredAccounts: [AgentAccount] = []
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

    @ObservationIgnored public var onResetsPending: (@MainActor () -> Void)?
    @ObservationIgnored public private(set) var pendingResets: [LimitReset] = []
    public nonisolated static let resetFreshness: TimeInterval = 30 * 60
    public nonisolated static let resetGrouping: TimeInterval = 60
    private struct SavedResetState: Codable {
        let tracker: LimitResetTracker
        let pending: [LimitReset]
    }
    @ObservationIgnored private var resetTracker = LimitResetTracker()
    @ObservationIgnored private var clockObservers: [(NotificationCenter, any NSObjectProtocol)] = []

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
        if let saved = settings.resetWindows,
           let restored = try? JSONDecoder().decode(SavedResetState.self, from: saved) {
            resetTracker = restored.tracker
            let now = Date()
            noteResets(restored.pending + resetTracker.check(now: now), now: now)
        }
        settings.onResetPreferenceChange = { [weak self] wasAllowed in
            guard let self else { return }
            // A sleeping task may be delivered late. Settle elapsed windows under the previous
            // preference, so turning notices back on cannot revive a reset that happened while off.
            self.noteResets(self.resetTracker.check(now: Date()), now: Date(), allowed: wasAllowed)
            if !self.settings.peeksOnReset || !self.settings.usageEnabled { self.discardPendingResets() }
            self.saveResetWindows()
            self.scheduleReset()
        }
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
        watchClock()
        sources.start()
        if viewers > 0 { sources.setVisible(true) }
    }

    public func stop() {
        resetTask?.cancel()
        resetTask = nil
        for (center, token) in clockObservers { center.removeObserver(token) }
        clockObservers = []
        // Pending resets remain recoverable in the saved windows until displayed or discarded.
        pendingResets = []
        live?.stop()
        live = nil
        accounts = []
        discoveredAccounts = []
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
        discoveredAccounts = found
        accounts = AgentAccount.named(found, nicknames: settings.nicknames)
        limits = limits.filter { id, _ in accounts.contains { $0.id == id } }
        let ids = Set(accounts.map(\.id))
        resetTracker.keep(accountIDs: ids)
        pendingResets.removeAll { !ids.contains($0.accountID) }
        saveResetWindows()
        refreshTotals()
    }

    func setLimits(_ value: AccountLimits, for accountID: String, now: Date = .now) {
        guard accounts.contains(where: { $0.id == accountID }), limits[accountID] != value else { return }
        limits[accountID] = value
        if value.state == .noLimits {
            pendingResets.filter { $0.accountID == accountID }.forEach(markHandled)
            pendingResets.removeAll { $0.accountID == accountID }
        }
        let resets = resetTracker.observe(accountID: accountID, limits: value, now: now)
        // A provider may correct a window's end after it was queued. Keep that correction, including
        // when it moves back into the future, without confusing it with the next real window.
        pendingResets = pendingResets.map { reset in
            guard let window = resetTracker.windows[reset.key], window.identityAt == reset.identityAt,
                  let corrected = window.reset else { return reset }
            return corrected
        }.sorted { $0.endedAt < $1.endedAt }
        noteResets(resets, now: now)
        saveResetWindows()
        checkNearLimit(accountID)
        scheduleReset()
        onResetsPending?()
    }

    /// One sleeping task for the next window end or the end of a 60-second grouping interval.
    private func scheduleReset() {
        resetTask?.cancel()
        let now = Date()
        let known = limits.values.flatMap(\.limits).compactMap(\.resetsAt).filter { $0 > now }
        let expires = pendingResets.first?.endedAt.addingTimeInterval(Self.resetFreshness + 0.01)
        let candidates = known + [resetTracker.nextEnd(after: now), nextResetDelivery, expires].compactMap { $0 }.filter { $0 > now }
        guard !isPractice, let next = candidates.min() else { resetTask = nil; return }
        resetTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(next.timeIntervalSince(now))) } catch { return }
            self?.timeMayHaveChanged()
        }
    }

    func timeMayHaveChanged(now: Date = .now) {
        limitsRevision += 1
        noteResets(resetTracker.check(now: now), now: now)
        saveResetWindows()
        for account in accounts { checkNearLimit(account.id) }
        scheduleReset()
        onResetsPending?()
    }

    private func watchClock() {
        guard clockObservers.isEmpty else { return }
        for (center, name) in [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (NotificationCenter.default, Notification.Name.NSSystemClockDidChange),
            (NotificationCenter.default, Notification.Name.NSSystemTimeZoneDidChange)
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.timeMayHaveChanged() }
            }
            clockObservers.append((center, token))
        }
    }

    private func saveResetWindows() {
        settings.resetWindows = try? JSONEncoder().encode(SavedResetState(tracker: resetTracker, pending: pendingResets))
    }

    private func noteResets(_ resets: [LimitReset], now: Date, allowed: Bool? = nil) {
        for reset in resets {
            guard reset.identityAt.timeIntervalSince1970 > (settings.handledResets[reset.key] ?? 0) + LimitResetTracker.sameWindow else { continue }
            guard allowed ?? (settings.peeksOnReset && settings.usageEnabled),
                  reset.endedAt > (settings.resetNoticesEnabledAfter ?? .distantPast),
                  now.timeIntervalSince(reset.endedAt) <= Self.resetFreshness else { markHandled(reset); continue }
            if !pendingResets.contains(where: { $0.key == reset.key && abs($0.identityAt.timeIntervalSince(reset.identityAt)) <= LimitResetTracker.sameWindow }) {
                pendingResets.append(reset)
            }
        }
        pendingResets.sort { $0.endedAt == $1.endedAt ? $0.key < $1.key : $0.endedAt < $1.endedAt }
    }

    public var nextResetDelivery: Date? {
        pendingResets.first?.endedAt.addingTimeInterval(Self.resetGrouping)
    }

    /// Resets within a minute share one strip. Later groups wait for the previous strip to finish.
    public func nextResetNotice(now: Date = .now) -> LimitResetNotice? {
        guard settings.peeksOnReset, settings.usageEnabled else { discardPendingResets(); return nil }
        let stale = pendingResets.filter { now.timeIntervalSince($0.endedAt) > Self.resetFreshness }
        stale.forEach(markHandled)
        pendingResets.removeAll { stale.contains($0) }
        if !stale.isEmpty { saveResetWindows() }
        guard let first = pendingResets.first, now >= first.endedAt.addingTimeInterval(Self.resetGrouping) else { return nil }
        let items = pendingResets.filter { $0.endedAt.timeIntervalSince(first.endedAt) <= Self.resetGrouping && $0.endedAt <= now }.compactMap { reset in
            accounts.first { $0.id == reset.accountID }.map { LimitResetNotice.Item(account: $0, reset: reset) }
        }
        return items.isEmpty ? nil : LimitResetNotice(items: items)
    }

    /// Called only after the notch accepts the strip, never merely when it was requested.
    public func resetNoticeStarted(_ notice: LimitResetNotice) {
        notice.items.forEach { markHandled($0.reset) }
        pendingResets.removeAll { reset in notice.items.contains { $0.reset == reset } }
        saveResetWindows()
        scheduleReset()
    }

    private func discardPendingResets() {
        pendingResets.forEach(markHandled)
        pendingResets = []
        saveResetWindows()
        scheduleReset()
    }

    private func markHandled(_ reset: LimitReset) {
        // This per-limit high-water mark must not expire: a later wall-clock rollback can make an
        // old provider file look fresh again. At most one number is stored for each known limit.
        settings.handledResets[reset.key] = max(settings.handledResets[reset.key] ?? 0, reset.identityAt.timeIntervalSince1970)
    }

    public func exampleResetNotice(now: Date = .now) -> LimitResetNotice? {
        guard isPractice, let account = accounts.first(where: { $0.plan == "Max" }) ?? accounts.first else { return nil }
        return LimitResetNotice(items: [.init(account: account, reset: LimitReset(accountID: account.id, kind: .session, endedAt: now, leftBefore: 8))])
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
        setAccounts(discoveredAccounts)
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
