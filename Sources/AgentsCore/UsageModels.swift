import Foundation

/// One account of an AI tool: a config folder (`~/.claude`, `~/.claude-work`, `~/.codex`…). Each folder
/// has its own sign-in, logs and limits, so that's what "account" means here (ADR-0037).
public struct AgentAccount: Identifiable, Hashable, Sendable {
    public enum Billing: String, Hashable, Sendable {
        /// A monthly plan (Claude Pro/Max, ChatGPT Plus/Pro): money shows as "API value".
        case plan
        /// Pay per token: money shows as "Cost".
        case apiKey
        case unknown
    }

    /// "<tool>:<folder path>".
    public let id: String
    public let tool: AgentTool
    public let folder: URL
    public var email: String?
    /// "Pro", "Max 5×", "Plus"…
    public var plan: String?
    public var billing: Billing
    /// The user's nickname for it, else the email, else the tool's name.
    public var name: String

    public init(tool: AgentTool, folder: URL, email: String? = nil, plan: String? = nil,
                billing: Billing = .unknown, name: String? = nil) {
        self.id = "\(tool.rawValue):\(folder.standardizedFileURL.path)"
        self.tool = tool
        self.folder = folder
        self.email = email
        self.plan = plan
        self.billing = billing
        self.name = name ?? email ?? tool.shortName
    }

    /// For the avatar: a nickname's first letters ("W" for Work, "WM" for Work Max), else the email's
    /// first letter and its domain's ("AD" for a@d.com), else the name's first two letters.
    public var initials: String {
        if name != email, name != tool.shortName {
            let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(2)
            let letters = words.compactMap(\.first).map(String.init).joined()
            if !letters.isEmpty { return letters.uppercased() }
        }
        if let email, let at = email.firstIndex(of: "@"), at != email.startIndex {
            let domain = email[email.index(after: at)...]
            return (String(email.prefix(1)) + String(domain.prefix(1))).uppercased()
        }
        let letters = name.filter(\.isLetter)
        return String(letters.prefix(2)).uppercased()
    }

    /// "API value" for plan accounts, "Cost" for pay-per-token ones.
    public var moneyLabel: String {
        billing == .apiKey ? String(localized: "Cost", comment: "AI Usage money label")
            : String(localized: "API value", comment: "AI Usage money label: what the tokens would cost pay-per-use")
    }
}

/// How fast a limit is being used compared with spreading it evenly over its window.
public enum UsagePace: Equatable, Sendable {
    /// More than 5 points ahead of even use: burning fast.
    case ahead
    case onPace
    /// More than 5 points behind even use.
    case under

    public var label: String {
        switch self {
        case .ahead: String(localized: "Ahead of pace", comment: "Usage limit pace")
        case .onPace: String(localized: "On pace", comment: "Usage limit pace")
        case .under: String(localized: "Under pace", comment: "Usage limit pace")
        }
    }
}

/// A plan limit: Claude's 5-hour session and weekly limits, Codex's primary and secondary windows.
public struct UsageLimit: Identifiable, Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case session
        case weekly
        /// A weekly limit for one model family ("Opus").
        case weeklyModel(String)
    }

    public let kind: Kind
    /// 0…100.
    public var usedPercent: Double
    public var resetsAt: Date?
    /// The window's length (5 hours, 7 days), for the pace mark.
    public var window: TimeInterval?

    public init(kind: Kind, usedPercent: Double, resetsAt: Date?, window: TimeInterval?) {
        self.kind = kind
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetsAt = resetsAt
        self.window = window
    }

    public var id: Kind { kind }

    /// "Session", "Weekly", "Weekly · Opus".
    public var label: String {
        switch kind {
        case .session: String(localized: "Session", comment: "Usage limit: the 5-hour window")
        case .weekly: String(localized: "Weekly", comment: "Usage limit")
        case .weeklyModel(let family): String(localized: "Weekly · \(family)", comment: "Usage limit for one model family")
        }
    }

    /// What's left, 0…100. A window that has reset counts as untouched.
    public func leftPercent(now: Date = .now) -> Double {
        hasReset(now: now) ? 100 : 100 - usedPercent
    }

    public func hasReset(now: Date = .now) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }

    /// Where "% left" would be if the limit were used evenly over its window (the pace mark), 0…100.
    public func evenLeftPercent(now: Date = .now) -> Double? {
        guard let resetsAt, let window, window > 0, !hasReset(now: now) else { return nil }
        let elapsed = window - resetsAt.timeIntervalSince(now)
        return 100 - min(100, max(0, elapsed / window * 100))
    }

    public func pace(now: Date = .now) -> UsagePace? {
        guard let even = evenLeftPercent(now: now) else { return nil }
        let left = leftPercent(now: now)
        if left < even - 5 { return .ahead }
        if left > even + 5 { return .under }
        return .onPace
    }
}

/// An account's limits as last seen.
public struct AccountLimits: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case available
        /// Pay-per-token accounts have no plan limits.
        case noLimits
        /// Not seen yet: they appear after the tool has been used once.
        case notYet
    }

    public var state: State
    public var limits: [UsageLimit]
    /// When the tool last fetched them.
    public var updatedAt: Date?

    public init(state: State, limits: [UsageLimit] = [], updatedAt: Date? = nil) {
        self.state = state
        self.limits = limits
        self.updatedAt = updatedAt
    }

    public static let notYet = AccountLimits(state: .notYet)

    /// The tightest limit (least left), for the near-limit ear.
    public func tightest(now: Date = .now) -> UsageLimit? {
        limits.min { $0.leftPercent(now: now) < $1.leftPercent(now: now) }
    }
}

/// The ranges AI Usage can show.
public enum UsageRange: String, CaseIterable, Identifiable, Sendable {
    case today, week, month

    public var id: Self { self }
    /// Local calendar days, today included.
    public var days: Int {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        }
    }

    public var label: String {
        switch self {
        case .today: String(localized: "Today", comment: "AI Usage range")
        case .week: String(localized: "7 days", comment: "AI Usage range")
        case .month: String(localized: "30 days", comment: "AI Usage range")
        }
    }
}

/// Which account AI Usage shows.
public enum AccountSelection: Hashable, Sendable {
    /// Every account added up (limits stay per account).
    case all
    case account(String)
}

/// Tokens and money for one model in a range.
public struct ModelUsage: Identifiable, Equatable, Sendable {
    /// "Opus 5.5", "GPT-6.1 Sol".
    public let name: String
    public var tokens: Int64
    public var cost: Double

    public var id: String { name }

    public init(name: String, tokens: Int64, cost: Double) {
        self.name = name
        self.tokens = tokens
        self.cost = cost
    }
}

/// What a range adds up to, for one account or all of them.
public struct UsageTotals: Equatable, Sendable {
    /// Input, output and cache tokens together.
    public var tokens: Int64
    /// What the priced tokens cost at pay-per-use prices, in US dollars.
    public var cost: Double
    /// Tokens from models without a known price (left out of `cost`).
    public var unpricedTokens: Int64
    /// Biggest first.
    public var models: [ModelUsage]

    public init(tokens: Int64 = 0, cost: Double = 0, unpricedTokens: Int64 = 0, models: [ModelUsage] = []) {
        self.tokens = tokens
        self.cost = cost
        self.unpricedTokens = unpricedTokens
        self.models = models
    }

    public static let zero = UsageTotals()
}

/// Tokens and money on one local calendar day (the Statistics chart).
public struct DailyUsage: Identifiable, Equatable, Sendable {
    public let day: Date
    public var tokens: Int64
    public var cost: Double

    public var id: Date { day }

    public init(day: Date, tokens: Int64, cost: Double) {
        self.day = day
        self.tokens = tokens
        self.cost = cost
    }
}

/// An account that dropped under 10% left on one of its limits.
public struct NearLimit: Equatable, Sendable {
    public let account: AgentAccount
    public let limit: UsageLimit

    public init(account: AgentAccount, limit: UsageLimit) {
        self.account = account
        self.limit = limit
    }
}
