import Foundation

/// A plan limit's window that ended after the account had used some of it: the limit is full again.
/// AI Usage tells the user about it with a pop-up under the notch (ADR-0037, 2026-10-31 amendment).
public struct LimitReset: Equatable, Sendable, Codable {
    public let accountID: String
    public let kind: UsageLimit.Kind
    /// When the window ended (its saved reset time).
    public let endedAt: Date
    /// Stable window identity: timestamp corrections move `endedAt`, never this value.
    public let identityAt: Date
    /// What was left (0…100) when it was last seen, before it filled up again.
    public let leftBefore: Double

    public init(accountID: String, kind: UsageLimit.Kind, endedAt: Date, leftBefore: Double, identityAt: Date? = nil) {
        self.accountID = accountID
        self.kind = kind
        self.endedAt = endedAt
        self.identityAt = identityAt ?? endedAt
        self.leftBefore = min(100, max(0, leftBefore))
    }

    /// One limit of one account.
    public var key: String { LimitResetTracker.key(accountID: accountID, kind: kind) }
}

/// Everything that reset and waits to be shown, as one pop-up: one account's limits on one line, several
/// accounts' as a count.
public struct LimitResetNotice: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public let account: AgentAccount
        public let reset: LimitReset

        public init(account: AgentAccount, reset: LimitReset) {
            self.account = account
            self.reset = reset
        }
    }

    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    /// The accounts, in the order their first reset came.
    public var accounts: [AgentAccount] {
        var seen: Set<String> = []
        return items.map(\.account).filter { seen.insert($0.id).inserted }
    }

    /// How many limits reset (an account's session and weekly limit count as two).
    public var limitCount: Int { items.count }

    /// The ring sweeps up from whichever limit had the least left.
    public var lowestLeftBefore: Double { items.map(\.reset.leftBefore).min() ?? 0 }
}

/// Follows each limit's current window to notice when one that was used has ended. The tools' files can
/// be hours old (they only change while the tool runs), so a window ends when the clock reaches its reset
/// time; a file that later shows a newer window also proves the old one ended. Nothing here polls: the
/// caller asks again when the clock reaches `nextEnd` and whenever limits change.
struct LimitResetTracker: Codable {
    /// A saved reset time that moves by less than this is the same window (the tools round it differently).
    static let sameWindow: TimeInterval = 60
    /// At least this much used (in percent) counts as "used some of it".
    static let usedAtLeast: Double = 1

    struct Window: Equatable, Codable {
        let accountID: String
        let kind: UsageLimit.Kind
        var endsAt: Date
        let identityAt: Date
        var peakUsed: Double
        /// The end was already reported (or ignored): it must not be reported again.
        var ended: Bool

        var reset: LimitReset? {
            guard peakUsed >= LimitResetTracker.usedAtLeast else { return nil }
            return LimitReset(accountID: accountID, kind: kind, endedAt: endsAt, leftBefore: 100 - peakUsed, identityAt: identityAt)
        }
    }

    private(set) var windows: [String: Window] = [:]
    /// A newer file can arrive just before the old window's deadline. Keep that used window until
    /// its own deadline instead of losing it when we follow the next one.
    private(set) var retiring: [Window] = []

    static func key(accountID: String, kind: UsageLimit.Kind) -> String {
        "\(accountID)|\(kind.storageKey)"
    }

    /// The limits as just read. Returns the windows they prove have ended.
    mutating func observe(accountID: String, limits: AccountLimits, now: Date) -> [LimitReset] {
        if limits.state == .noLimits {
            windows = windows.filter { $0.value.accountID != accountID }
            retiring.removeAll { $0.accountID == accountID }
            return []
        }
        guard limits.state == .available else { return [] }
        var resets: [LimitReset] = []
        for limit in limits.limits {
            guard let endsAt = limit.resetsAt, limit.usedPercent.isFinite else { continue }
            let key = Self.key(accountID: accountID, kind: limit.kind)
            var seen = Window(accountID: accountID, kind: limit.kind, endsAt: endsAt, identityAt: endsAt, peakUsed: limit.usedPercent, ended: false)
            guard var window = windows[key] else {
                // First sight: a window that already ended is reported if it was used (a reset since the
                // app last ran), else it is just remembered.
                if endsAt <= now {
                    seen.ended = true
                    if let reset = seen.reset { resets.append(reset) }
                }
                windows[key] = seen
                continue
            }
            let shift = endsAt.timeIntervalSince(window.endsAt)
            if abs(shift) <= Self.sameWindow {
                // The same window, read again.
                window.peakUsed = max(window.peakUsed, limit.usedPercent)
                window.endsAt = max(window.endsAt, endsAt)
                if window.endsAt > now { window.ended = false }
            } else if shift > 0 {
                // A later window. Report the previous used window now if due; otherwise retain it
                // until its original deadline even though the tool has already moved on.
                if !window.ended {
                    if window.endsAt <= now, let reset = window.reset { resets.append(reset) }
                    else if window.reset != nil, !retiring.contains(where: { $0.accountID == window.accountID && $0.kind == window.kind && $0.identityAt == window.identityAt }) {
                        retiring.append(window)
                    }
                }
                if endsAt <= now {
                    seen.ended = true
                    if let reset = seen.reset { resets.append(reset) }
                }
                window = seen
            }
            // An older window than the one we follow is stale data from before: ignored.
            if !window.ended, window.endsAt <= now {
                window.ended = true
                if let reset = window.reset { resets.append(reset) }
            }
            windows[key] = window
        }
        return resets.sorted { $0.endedAt < $1.endedAt }
    }

    /// The clock reached some windows' ends. Returns the used ones.
    mutating func check(now: Date) -> [LimitReset] {
        var resets: [LimitReset] = []
        for (key, window) in windows where !window.ended && window.endsAt <= now {
            windows[key]?.ended = true
            if let reset = window.reset { resets.append(reset) }
        }
        for window in retiring where window.endsAt <= now {
            if let reset = window.reset { resets.append(reset) }
        }
        retiring.removeAll { $0.endsAt <= now }
        return resets.sorted { $0.endedAt < $1.endedAt }
    }

    /// The next time a followed window ends, or nil.
    func nextEnd(after now: Date) -> Date? {
        (Array(windows.values) + retiring).filter { !$0.ended && $0.endsAt > now }.map(\.endsAt).min()
    }

    /// Forgets every account that is gone.
    mutating func keep(accountIDs: Set<String>) {
        windows = windows.filter { accountIDs.contains($0.value.accountID) }
        retiring.removeAll { !accountIDs.contains($0.accountID) }
    }

    mutating func removeAll() {
        windows = [:]
        retiring = []
    }
}
