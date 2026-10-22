import Foundation

/// AI Usage's pretend accounts for the practice notches: two Claude accounts (Personal on Pro, Work on
/// Max) and a Codex one, with believable limits and totals. Nothing real is read.
enum PracticeUsage {
    static let accounts: [AgentAccount] = [
        AgentAccount(tool: .claude, folder: URL(fileURLWithPath: "/practice/.claude"), email: "sam@example.com",
                     plan: "Pro", billing: .plan, name: String(localized: "Personal", comment: "Practice account name")),
        AgentAccount(tool: .claude, folder: URL(fileURLWithPath: "/practice/.claude-work"), email: "sam@example.org",
                     plan: "Max 5×", billing: .plan, name: String(localized: "Work", comment: "Practice account name")),
        AgentAccount(tool: .codex, folder: URL(fileURLWithPath: "/practice/.codex"), email: "sam@example.com",
                     plan: "Plus", billing: .plan),
    ]

    static func limits(now: Date) -> [String: AccountLimits] {
        func limits(session: Double, sessionIn: TimeInterval, weekly: Double, weeklyIn: TimeInterval) -> AccountLimits {
            AccountLimits(state: .available, limits: [
                UsageLimit(kind: .session, usedPercent: session, resetsAt: now.addingTimeInterval(sessionIn), window: 5 * 3600),
                UsageLimit(kind: .weekly, usedPercent: weekly, resetsAt: now.addingTimeInterval(weeklyIn), window: 7 * 86_400),
            ], updatedAt: now.addingTimeInterval(-90))
        }
        return [
            accounts[0].id: limits(session: 37, sessionIn: 2 * 3600 + 14 * 60, weekly: 23, weeklyIn: 4 * 86_400 + 3 * 3600),
            accounts[1].id: limits(session: 92, sessionIn: 41 * 60, weekly: 58, weeklyIn: 2 * 86_400),
            accounts[2].id: limits(session: 12, sessionIn: 3 * 3600 + 30 * 60, weekly: 41, weeklyIn: 5 * 86_400),
        ]
    }

    static func totals(for selection: AccountSelection, range: UsageRange) -> UsageTotals {
        let scale: Double = switch range {
        case .today: 1
        case .week: 5.6
        case .month: 21
        }
        // Each account's share of a pretend day.
        let personal: [ModelUsage] = [ModelUsage(name: "Sonnet 5.5", tokens: 3_400_000, cost: 2.10), ModelUsage(name: "Haiku 5.5", tokens: 900_000, cost: 0.08)]
        let work: [ModelUsage] = [ModelUsage(name: "Opus 5.5", tokens: 9_800_000, cost: 11.40), ModelUsage(name: "Sonnet 5.5", tokens: 2_100_000, cost: 1.30)]
        let codex: [ModelUsage] = [ModelUsage(name: "GPT-6.1 Sol", tokens: 4_200_000, cost: 1.85)]
        let models: [ModelUsage] = switch selection {
        case .account(let id) where id == accounts[0].id: personal
        case .account(let id) where id == accounts[1].id: work
        case .account: codex
        case .all: personal + work + codex
        }
        var merged: [String: ModelUsage] = [:]
        for model in models {
            let scaled = ModelUsage(name: model.name, tokens: Int64(Double(model.tokens) * scale), cost: model.cost * scale)
            merged[model.name, default: ModelUsage(name: model.name, tokens: 0, cost: 0)].tokens += scaled.tokens
            merged[model.name]?.cost += scaled.cost
        }
        let sorted = merged.values.sorted { $0.tokens > $1.tokens }
        return UsageTotals(tokens: sorted.reduce(0) { $0 + $1.tokens }, cost: sorted.reduce(0) { $0 + $1.cost }, models: sorted)
    }

    static func daily(days: Int, now: Date = .now) -> [DailyUsage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            // A steady-looking but uneven pretend month: busier on weekdays.
            let weekday = calendar.component(.weekday, from: day)
            let busy = weekday == 1 || weekday == 7 ? 0.35 : 1.0
            let wave = 0.7 + 0.3 * sin(Double(offset) * 0.9)
            let tokens = Int64(20_400_000 * busy * wave)
            return DailyUsage(day: day, tokens: tokens, cost: Double(tokens) / 1_000_000 * 0.82)
        }
    }
}
