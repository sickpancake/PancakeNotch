import AgentsCore
import Foundation

/// The words and numbers AI Usage shows, kept apart from the views so they can be tested.
enum AIUsageText {
    /// "63" for the share a limit has left, in whole percent.
    static func percent(_ value: Double) -> Int {
        value.isFinite && value >= 0 ? (Int(exactly: value.rounded()) ?? 0) : 0
    }

    /// "Session · On pace", or just "Session" while the pace isn't known.
    static func title(_ limit: UsageLimit, now: Date) -> String {
        [limit.label, limit.pace(now: now)?.label].compactMap { $0 }.joined(separator: " · ")
    }

    /// "63% left · resets in 2h 14m".
    static func detail(_ limit: UsageLimit, now: Date) -> String {
        [left(limit, now: now), reset(limit.resetsAt, now: now)].compactMap { $0 }.joined(separator: " · ")
    }

    static func left(_ limit: UsageLimit, now: Date) -> String {
        String(localized: "\(percent(limit.leftPercent(now: now)))% left", comment: "AI Usage: how much of a limit is left")
    }

    /// "resets in 2h 14m" within a day, else "resets Sun 11:00". `nil` without a reset time, or once it has passed.
    static func reset(_ date: Date?, now: Date) -> String? {
        guard let date, date > now else { return nil }
        let remaining = date.timeIntervalSince(now)
        if remaining < 86_400 {
            return String(localized: "resets in \(AgentsText.span(remaining))", comment: "AI Usage: time until a limit resets, e.g. resets in 2h 14m")
        }
        return String(localized: "resets \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))",
                      comment: "AI Usage: when a limit resets, e.g. resets Sun 11:00")
    }

    /// "as of 3:12 PM" when the tool last fetched the limits more than 10 minutes ago, else `nil`.
    static func asOf(_ updatedAt: Date?, now: Date) -> String? {
        guard let updatedAt, now.timeIntervalSince(updatedAt) > 600 else { return nil }
        let when = Calendar.current.isDate(updatedAt, inSameDayAs: now)
            ? updatedAt.formatted(date: .omitted, time: .shortened)
            : updatedAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return String(localized: "as of \(when)", comment: "AI Usage: when the limits were last updated, e.g. as of 3:12 PM")
    }

    /// "12.4M", "950K", "42": three digits at most, with the K, M or B of the user's language.
    static func tokens(_ count: Int64, locale: Locale = .current) -> String {
        count.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)).locale(locale))
    }

    /// "≈ $41.20 API value" for plans, "$41.20 Cost" for accounts that pay per token.
    static func money(_ cost: Double, label: String, paysPerToken: Bool) -> String {
        let amount = cost.formatted(.currency(code: "USD"))
        return paysPerToken ? "\(amount) \(label)"
            : String(localized: "≈ \(amount) \(label)", comment: "AI Usage: an estimate, e.g. ≈ $41.20 API value")
    }

    /// "Opus 5.5 · 62%": the model's share of the tokens.
    static func share(_ model: ModelUsage, of total: Int64) -> String {
        guard total > 0 else { return model.name }
        let share = Double(model.tokens) / Double(total) * 100
        return "\(model.name) · \(share < 1 ? "<1" : String(Int(share.rounded())))%"
    }

    /// The Module Menu's line: the chosen account's tightest limit ("Session 63% left"), its name when it
    /// has no limits, else "All accounts".
    static func menuStatus(account: AgentAccount?, limits: AccountLimits?, now: Date = .now) -> String {
        guard let account else { return String(localized: "All accounts", comment: "AI Usage: every account at once") }
        guard let limit = limits?.tightest(now: now) else { return EmailPrivacy.masked(account.name) }
        return "\(limit.label) \(left(limit, now: now))"
    }

    /// The strip under the notch: who is nearly out ("Claude · Work") and what's left.
    static func peek(_ near: NearLimit, now: Date) -> (subject: String, detail: String) {
        let account = near.account
        let name = EmailPrivacy.masked(account.name)
        let subject = account.isDefaultName || account.name == account.tool.shortName ? name : "\(account.tool.shortName) · \(name)"
        return (subject, detail(near.limit, now: now))
    }

    static func resetPeek(_ notice: LimitResetNotice) -> (subject: String, detail: String) {
        guard notice.accounts.count == 1, let account = notice.accounts.first else {
            return (String(localized: "\(notice.limitCount) limits reset"),
                    String(localized: "\(notice.accounts.count) accounts"))
        }
        let name = EmailPrivacy.masked(account.name)
        let subject = account.isDefaultName || account.name == account.tool.shortName ? name : "\(account.tool.shortName) · \(name)"
        let labels = notice.items.map { $0.reset.kind.label }
        let limits = ListFormatter.localizedString(byJoining: labels)
        let reset = String(localized: "\(limits) reset", comment: "Usage limits restored, e.g. Session and Weekly reset")
        return (subject, [account.isDefaultName ? nil : account.plan, reset].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
    }

    /// Read while the notch is compact: "Work is nearly out of Claude Code: 8% left", or when it always
    /// shows, "Work, Claude Code: 64% left".
    static func spoken(_ near: NearLimit, now: Date) -> String {
        let name = EmailPrivacy.masked(near.account.name)
        guard near.limit.leftPercent(now: now) < UsageCenter.nearLimitPercent else {
            return String(localized: "\(name), \(near.account.tool.name): \(left(near.limit, now: now))",
                          comment: "VoiceOver, compact notch: how much of an account's limit is left")
        }
        return String(localized: "\(name) is nearly out of \(near.account.tool.name): \(left(near.limit, now: now))",
                      comment: "VoiceOver, compact notch: an account is almost at its limit")
    }

    // MARK: Account circles

    /// White opacities over black: the grays an account's circle can have.
    static let circleShades: [Double] = [0.18, 0.26, 0.34, 0.42]

    /// A gray that stays the same for an account (from its email, else its name), so it's easy to spot again.
    static func circleShade(for account: AgentAccount) -> Double {
        // FNV-1a: `hashValue` changes on every launch.
        var hash: UInt32 = 2_166_136_261
        for byte in (account.email ?? account.name).lowercased().utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return circleShades[Int(hash % UInt32(circleShades.count))]
    }
}
