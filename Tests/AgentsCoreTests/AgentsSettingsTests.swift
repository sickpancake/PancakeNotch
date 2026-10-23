import Foundation
import Testing
@testable import AgentsCore

@MainActor
struct AgentsSettingsTests {
    private func settings() -> AgentsSettings {
        AgentsSettings(defaults: UserDefaults(suiteName: "AgentsSettingsTests.\(UUID().uuidString)")!)
    }

    @Test func choicesAreKept() {
        let defaults = UserDefaults(suiteName: "AgentsSettingsTests.\(UUID().uuidString)")!
        let first = AgentsSettings(defaults: defaults)
        first.nameStyle = .branch
        first.keepFinished = .untilCleared
        first.hiddenTools = [.cursor]
        first.showsSteps = false
        first.earMode = .always
        first.earAccount = .account("codex:/x")
        first.earLimit = .weekly
        let again = AgentsSettings(defaults: defaults)
        #expect(again.nameStyle == .branch)
        #expect(again.keepFinished == .untilCleared)
        #expect(again.hiddenTools == [.cursor])
        #expect(!again.showsSteps)
        #expect(again.showsSubagents)
        #expect(again.earMode == .always)
        #expect(again.earAccount == .account("codex:/x"))
        #expect(again.earLimit == .weekly)
    }

    @Test func turningTheWarningOffBeforeKeepsTheEarHidden() {
        let defaults = UserDefaults(suiteName: "AgentsSettingsTests.\(UUID().uuidString)")!
        defaults.set(false, forKey: "aiUsage.warnsNearLimit")
        #expect(AgentsSettings(defaults: defaults).earMode == .never)
        #expect(settings().earMode == .nearLimit)
    }

    @Test func hiddenToolsLeaveTheListTheEarAndThePeeks() {
        let center = AgentsCenter(settings: settings())
        var alerts: [String] = []
        center.onAlert = { alerts.append($0.thread.id) }
        center.settings.hiddenTools = [.cursor]
        let now = Date()
        center.apply(.init(id: "cursor:a", tool: .cursor, at: now, status: .needsYou(.input)))
        center.apply(.init(id: "claude:b", tool: .claude, at: now, status: .working))
        #expect(center.threads.map(\.id) == ["claude:b"])
        #expect(center.attention == .working(count: 1))
        #expect(alerts.isEmpty)
        center.settings.hiddenTools = []
        #expect(center.threads.count == 2)
        #expect(center.attention == .needsYou(count: 1))
    }

    @Test func stepsAndSubagentsCanBeHidden() {
        let center = AgentsCenter(settings: settings())
        let now = Date()
        center.apply(.init(id: "claude:a", tool: .claude, at: now, status: .working, step: .some("Editing a.swift")))
        center.setSubagents([AgentSubagent(id: "claude:s", title: "Help", status: .working, statusSince: now)], of: "claude:a")
        #expect(center.threads.first?.step == "Editing a.swift")
        #expect(center.threads.first?.subagents.count == 1)
        center.settings.showsSteps = false
        center.settings.showsSubagents = false
        #expect(center.threads.first?.step == nil)
        #expect(center.threads.first?.subagents.isEmpty == true)
    }

    @Test func finishedAgentsCanStayUntilCleared() {
        let center = AgentsCenter(settings: settings())
        center.settings.keepFinished = .untilCleared
        let now = Date()
        center.apply(.init(id: "claude:a", tool: .claude, at: now, status: .done, quietly: true))
        center.apply(.init(id: "claude:b", tool: .claude, at: now.addingTimeInterval(3 * 3600), status: .working))
        #expect(center.thread("claude:a") != nil)
        center.settings.keepFinished = .fiveMinutes
        center.apply(.init(id: "claude:b", tool: .claude, at: now.addingTimeInterval(3 * 3600), step: .some("x")))
        #expect(center.thread("claude:a") == nil)
    }

    @Test func theClosedNotchFollowsTheChosenAccountAndLimit() {
        let usage = UsageCenter(settings: settings(), stats: nil)
        let work = AgentAccount(tool: .claude, folder: URL(fileURLWithPath: "/tmp/work"), name: "Work")
        let home = AgentAccount(tool: .codex, folder: URL(fileURLWithPath: "/tmp/home"), name: "Home")
        usage.setAccounts([work, home])
        let later = Date().addingTimeInterval(3600)
        usage.setLimits(AccountLimits(state: .available, limits: [
            UsageLimit(kind: .session, usedPercent: 95, resetsAt: later, window: nil),
            UsageLimit(kind: .weekly, usedPercent: 40, resetsAt: later, window: nil),
        ]), for: work.id)
        usage.setLimits(AccountLimits(state: .available, limits: [
            UsageLimit(kind: .session, usedPercent: 20, resetsAt: later, window: nil),
        ]), for: home.id)

        // When close: only the account under 10% left, on its closest limit.
        #expect(usage.earReading?.account.id == work.id)
        #expect(usage.earReading?.limit.kind == .session)
        usage.settings.earLimit = .weekly
        #expect(usage.earReading == nil)

        usage.settings.earMode = .always
        #expect(usage.earReading?.limit.kind == .weekly)
        usage.settings.earAccount = .account(home.id)
        usage.settings.earLimit = .session
        #expect(usage.earReading?.account.id == home.id)
        #expect(usage.earReading?.limit.usedPercent == 20)
        // An account that's gone: back to all of them.
        usage.settings.earAccount = .account("claude:/gone")
        #expect(usage.earReading?.account.id == work.id)

        usage.settings.earMode = .never
        #expect(usage.earReading == nil)
    }
}
