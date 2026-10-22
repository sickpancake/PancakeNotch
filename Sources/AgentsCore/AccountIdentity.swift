import Foundation

/// Who an account folder belongs to and its plan limits, from the files the tools keep there
/// (ADR-0037). No network, no Keychain: Claude Code saves its last limits in `.claude.json`
/// (`cachedUsageUtilization`, not a documented format: if it changes, limits read as "not yet"), and
/// Codex reports them in its rollouts. Sign-in tokens are never kept or sent anywhere.
enum AccountIdentity {
    struct Claude: Equatable, Sendable {
        var email: String?
        var plan: String?
        var billing: AgentAccount.Billing
        var limits: AccountLimits
    }

    /// Nil when the file can't be read right now (missing, or caught mid-write).
    static func claude(configFile: URL) -> Claude? {
        guard let data = try? Data(contentsOf: configFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let account = object["oauthAccount"] as? [String: Any] else {
            // Signed in with an API key: pay per token, no plan limits.
            let usesKey = object["primaryApiKey"] != nil || object["customApiKeyResponses"] != nil
            return Claude(billing: usesKey ? .apiKey : .unknown, limits: usesKey ? AccountLimits(state: .noLimits) : .notYet)
        }
        let plan = claudePlan(type: account["organizationType"] as? String,
                              tier: account["userRateLimitTier"] as? String ?? account["organizationRateLimitTier"] as? String)
        var limits = AccountLimits.notYet
        if let cached = object["cachedUsageUtilization"] as? [String: Any],
           (cached["accountUuid"] as? String).map({ $0 == account["accountUuid"] as? String }) ?? true,
           let utilization = cached["utilization"] as? [String: Any] {
            let found = claudeLimits(utilization)
            let fetched = (cached["fetchedAtMs"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            if !found.isEmpty { limits = AccountLimits(state: .available, limits: found, updatedAt: fetched) }
        }
        return Claude(email: account["emailAddress"] as? String, plan: plan, billing: .plan, limits: limits)
    }

    /// "claude_max" + "default_claude_max_5x" → "Max 5×".
    static func claudePlan(type: String?, tier: String?) -> String? {
        switch type {
        case "claude_pro": return "Pro"
        case "claude_max":
            if tier?.contains("20x") == true { return "Max 20×" }
            if tier?.contains("5x") == true { return "Max 5×" }
            return "Max"
        case "claude_team": return "Team"
        case "claude_enterprise": return "Enterprise"
        default: return nil
        }
    }

    /// The named windows (`five_hour`, `seven_day`, `seven_day_opus`…), else the newer `limits` list.
    static func claudeLimits(_ utilization: [String: Any]) -> [UsageLimit] {
        let windows: [(String, UsageLimit.Kind, TimeInterval)] = [
            ("five_hour", .session, 5 * 3600),
            ("seven_day", .weekly, 7 * 86_400),
            ("seven_day_opus", .weeklyModel("Opus"), 7 * 86_400),
            ("seven_day_sonnet", .weeklyModel("Sonnet"), 7 * 86_400),
        ]
        let named = windows.compactMap { key, kind, window -> UsageLimit? in
            guard let value = utilization[key] as? [String: Any], let used = value["utilization"] as? Double else { return nil }
            return UsageLimit(kind: kind, usedPercent: used, resetsAt: (value["resets_at"] as? String).flatMap(date), window: window)
        }
        guard named.isEmpty, let list = utilization["limits"] as? [[String: Any]] else { return named }
        return list.compactMap { value in
            guard let used = value["percent"] as? Double else { return nil }
            let kind: UsageLimit.Kind
            if value["kind"] as? String == "session" {
                kind = .session
            } else if value["group"] as? String == "weekly" {
                kind = (value["scope"] as? String).map { .weeklyModel($0.capitalized) } ?? .weekly
            } else {
                return nil
            }
            return UsageLimit(kind: kind, usedPercent: used, resetsAt: (value["resets_at"] as? String).flatMap(date),
                              window: kind == .session ? 5 * 3600 : 7 * 86_400)
        }
    }

    struct Codex: Equatable, Sendable {
        var email: String?
        var plan: String?
        var billing: AgentAccount.Billing
    }

    /// From `auth.json`: the sign-in kind, and the email and plan in the ID token's payload.
    static func codex(folder: URL) -> Codex {
        guard let data = try? Data(contentsOf: folder.appending(path: "auth.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Codex(billing: .unknown)
        }
        if (object["auth_mode"] as? String)?.lowercased().contains("key") == true
            || (object["tokens"] == nil && object["OPENAI_API_KEY"] is String) {
            return Codex(billing: .apiKey)
        }
        let claims = ((object["tokens"] as? [String: Any])?["id_token"] as? String).flatMap(jwtPayload) ?? [:]
        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        return Codex(email: claims["email"] as? String, plan: (auth?["chatgpt_plan_type"] as? String).map(codexPlan), billing: .plan)
    }

    /// "plus" → "Plus", "pro" → "Pro".
    static func codexPlan(_ type: String) -> String {
        type.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    /// A JWT's middle part, decoded (no signature check: it's only read for the email shown).
    static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// "2026-10-22T00:19:59.86164+00:00", with or without fractions or a time zone (then UTC).
    static func date(_ text: String) -> Date? {
        if let date = CodexRollout.date(text) { return date }
        let withZone = text.contains("+") || text.hasSuffix("Z") || text.dropFirst(10).contains("-") ? text : text + "Z"
        if let date = CodexRollout.date(withZone) { return date }
        // More than three fraction digits: drop the fraction.
        if let dot = withZone.firstIndex(of: ".") {
            let zone = withZone[dot...].drop { $0.isNumber || $0 == "." }
            return CodexRollout.date(String(withZone[..<dot]) + zone)
        }
        return nil
    }
}
