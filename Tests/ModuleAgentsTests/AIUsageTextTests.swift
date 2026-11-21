import AgentsCore
import Foundation
import Testing
@testable import ModuleAgents

struct AIUsageTextTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let english = Locale(identifier: "en_US")

    func limit(_ kind: UsageLimit.Kind = .session, used: Double, resetsIn: TimeInterval?, window: TimeInterval? = 5 * 3600) -> UsageLimit {
        UsageLimit(kind: kind, usedPercent: used, resetsAt: resetsIn.map { now.addingTimeInterval($0) }, window: window)
    }

    func account(_ name: String, email: String? = nil) -> AgentAccount {
        AgentAccount(tool: .claude, folder: URL(fileURLWithPath: "/tmp/.claude-\(name)"), email: email, plan: "Pro", billing: .plan, name: name)
    }

    @Test func tokensAreShortenedToThreeDigits() {
        #expect(AIUsageText.tokens(950, locale: english) == "950")
        #expect(AIUsageText.tokens(1_240, locale: english) == "1.24K")
        #expect(AIUsageText.tokens(12_400_000, locale: english) == "12.4M")
        #expect(AIUsageText.tokens(124_000_000, locale: english) == "124M")
        #expect(AIUsageText.tokens(2_000_000_000, locale: english) == "2B")
    }

    @Test func resetsInAFewHoursReadAsATimeLeft() {
        let text = AIUsageText.reset(now.addingTimeInterval(2 * 3600 + 14 * 60), now: now)
        #expect(text == "resets in \(AgentsText.span(2 * 3600 + 14 * 60))")
        #expect(AIUsageText.reset(now.addingTimeInterval(41 * 60), now: now)?.hasPrefix("resets in ") == true)
    }

    @Test func resetsAfterADayReadAsAWeekdayAndTime() {
        let text = AIUsageText.reset(now.addingTimeInterval(3 * 86_400), now: now)
        #expect(text?.hasPrefix("resets ") == true)
        #expect(text?.hasPrefix("resets in ") == false)
    }

    @Test func noResetTimeOrOnePassedSaysNothing() {
        #expect(AIUsageText.reset(nil, now: now) == nil)
        #expect(AIUsageText.reset(now.addingTimeInterval(-5), now: now) == nil)
    }

    @Test func aLimitReadsAsPercentLeftAndReset() {
        let session = limit(used: 37, resetsIn: 2 * 3600 + 14 * 60)
        #expect(AIUsageText.left(session, now: now) == "63% left")
        #expect(AIUsageText.detail(session, now: now) == "63% left · resets in \(AgentsText.span(2 * 3600 + 14 * 60))")
        #expect(AIUsageText.detail(limit(used: 37, resetsIn: nil), now: now) == "63% left")
    }

    @Test func theTitleCarriesThePaceWhenKnown() {
        // Half the window gone, 63% left: ahead of even use.
        #expect(AIUsageText.title(limit(used: 37, resetsIn: 2.5 * 3600), now: now) == "Session · Under pace")
        #expect(AIUsageText.title(limit(used: 90, resetsIn: 2.5 * 3600), now: now) == "Session · Ahead of pace")
        #expect(AIUsageText.title(limit(used: 37, resetsIn: nil, window: nil), now: now) == "Session")
    }

    @Test func oldLimitsSayWhenTheyWereSeen() {
        #expect(AIUsageText.asOf(now.addingTimeInterval(-600), now: now) == nil)
        #expect(AIUsageText.asOf(nil, now: now) == nil)
        #expect(AIUsageText.asOf(now.addingTimeInterval(-2 * 3600), now: now)?.hasPrefix("as of ") == true)
    }

    @Test func menuStatusShowsTheTightestLimitOfTheChosenAccount() {
        let limits = AccountLimits(state: .available, limits: [
            limit(.session, used: 37, resetsIn: 2 * 3600),
            limit(.weekly, used: 80, resetsIn: 3 * 86_400, window: 7 * 86_400),
        ], updatedAt: now)
        #expect(AIUsageText.menuStatus(account: account("Work"), limits: limits, now: now) == "Weekly 20% left")
        #expect(AIUsageText.menuStatus(account: account("Work"), limits: nil, now: now) == "Work")
        #expect(AIUsageText.menuStatus(account: nil, limits: nil, now: now) == "All accounts")
    }

    @Test func modelsShowTheirShareOfTheTokens() {
        let opus = ModelUsage(name: "Opus 5.5", tokens: 620, cost: 1)
        #expect(AIUsageText.share(opus, of: 1_000) == "Opus 5.5 · 62%")
        #expect(AIUsageText.share(ModelUsage(name: "Haiku 5.5", tokens: 3, cost: 0), of: 1_000) == "Haiku 5.5 · <1%")
        #expect(AIUsageText.share(opus, of: 0) == "Opus 5.5")
    }

    @Test func moneyIsAnEstimateOnlyForPlans() {
        #expect(AIUsageText.money(41.2, label: "API value", paysPerToken: false) == "≈ $41.20 API value")
        #expect(AIUsageText.money(41.2, label: "Cost", paysPerToken: true) == "$41.20 Cost")
    }

    @Test func thePeekNamesToolAndAccount() {
        let near = NearLimit(account: account("Work"), limit: limit(used: 92, resetsIn: 41 * 60))
        let text = AIUsageText.peek(near, now: now)
        #expect(text.subject == "Claude · Work")
        #expect(text.detail == "8% left · resets in \(AgentsText.span(41 * 60))")
        // An account named after the tool isn't said twice.
        let plain = NearLimit(account: account("Claude"), limit: limit(used: 92, resetsIn: 41 * 60))
        #expect(AIUsageText.peek(plain, now: now).subject == "Claude")
    }

    @Test func anAccountKeepsItsGray() {
        let one = account("Work", email: "sam@studio.dev")
        #expect(AIUsageText.circleShade(for: one) == AIUsageText.circleShade(for: account("Other", email: "SAM@studio.dev")))
        for name in ["a", "b", "c", "d", "e", "f"] {
            #expect(AIUsageText.circleShades.contains(AIUsageText.circleShade(for: account(name))))
        }
    }
}

struct StatusColorsTests {
    @Test func limitsChangeColorAsTheyRunLow() {
        #expect(StatusColors.color(left: 80) == StatusColors.green)
        #expect(StatusColors.color(left: 50) == StatusColors.green)
        #expect(StatusColors.color(left: 35) == StatusColors.yellow)
        #expect(StatusColors.color(left: 12) == StatusColors.orange)
        #expect(StatusColors.color(left: 8) == StatusColors.red)
    }

    @Test func eachStatusHasItsColor() {
        #expect(StatusColors.color(for: .working) == StatusColors.blue)
        #expect(StatusColors.color(for: .needsYou(.input)) == StatusColors.orange)
        #expect(StatusColors.color(for: .failed) == StatusColors.red)
    }
}

struct AgentsSubagentTextTests {
    @Test func subagentCounts() {
        #expect(AgentsText.subagents(1) == "1 subagent")
        #expect(AgentsText.subagents(3) == "3 subagents")
    }

    @Test func aThreadSaysHowManySubagentsItHas() {
        let now = Date()
        let thread = AgentThread(id: "claude:a", tool: .claude, title: "Fix it", project: "web", status: .working, statusSince: now,
                                 subagents: [AgentSubagent(id: "claude:s", title: "Check it", status: .working, statusSince: now)])
        #expect(AgentsText.spoken(thread, now: now).hasSuffix(", 1 subagent"))
        #expect(AgentsText.spoken(thread.subagents[0], now: now) == "Subagent, Check it, Working · 0s")
    }
}

@MainActor
struct ResetTextTests {
    @Test func textNamesThePlanAndLimitsAndMasksEmails() throws {
        let account = AgentAccount(tool: .claude, folder: URL(fileURLWithPath: "/tmp/reset"), email: "tester@example.com", plan: "Max", name: "tester@example.com")
        let items = [UsageLimit.Kind.session, .weekly].map { kind in
            LimitResetNotice.Item(account: account, reset: LimitReset(accountID: account.id, kind: kind, endedAt: .now, leftBefore: 5))
        }
        let notice = LimitResetNotice(items: items)
        let text = AIUsageText.resetPeek(notice)
        #expect(text.subject == "Claude · t•••••@example.com")
        #expect(text.detail == "Max · Session and Weekly reset")
        let unknown = AgentAccount(tool: .codex, folder: URL(fileURLWithPath: "/tmp/unknown"), name: "Personal")
        let single = LimitResetNotice(items: [.init(account: unknown, reset: LimitReset(accountID: unknown.id, kind: .weekly, endedAt: .now, leftBefore: 80))])
        #expect(AIUsageText.resetPeek(single).detail == "Weekly reset")
        let summary = LimitResetNotice(items: items + single.items)
        #expect(AIUsageText.resetPeek(summary).subject == "3 limits reset")
        #expect(AIUsageText.resetPeek(summary).detail == "2 accounts")
        #expect(summary.lowestLeftBefore == 5)
    }
}

@MainActor
struct DefaultAccountTextTests {
    @Test func defaultResetLabelDoesNotRepeatProviderOrTier() throws {
        let center = UsageCenter.practice()
        let notice = try #require(center.exampleResetNotice())
        let text = AIUsageText.resetPeek(notice)
        #expect(text.subject == "Claude Max 2")
        #expect(text.detail == "Session reset")
        let near = try #require(center.earReading)
        #expect(AIUsageText.peek(near, now: .now).subject == "Claude Max 2")
    }
}
