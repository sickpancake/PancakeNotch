import Foundation
import Testing
@testable import AgentsCore

@MainActor
struct AccountNamesTests {
    func account(_ tool: AgentTool = .claude, folder: String = "/tmp/.claude", plan: String? = "Pro") -> AgentAccount {
        AgentAccount(tool: tool, folder: URL(fileURLWithPath: folder), email: "tester@example.com", plan: plan)
    }

    @Test func oneAccountUsesProviderThenTierWithoutEmailOrNumber() {
        let claude = account()
        #expect(claude.name == "Claude Pro")
        #expect(account(.codex, plan: "Plus").name == "Codex Plus")
        #expect(account(plan: nil).name == "Claude")
        #expect(account(plan: "").name == "Claude")
        #expect(claude.isDefaultName)
    }

    @Test func multipleAccountsAreNumberedPerProviderInStableOrder() {
        let pro = account()
        let max = account(folder: "/tmp/.claude-work", plan: "Max")
        let codex = account(.codex, folder: "/tmp/.codex", plan: "Plus")
        let named = AgentAccount.named([pro, max, codex])
        #expect(named.map(\.name) == ["Claude Pro 1", "Claude Max 2", "Codex Plus"])
        let reversed = AgentAccount.named([codex, max, pro])
        #expect(Dictionary(uniqueKeysWithValues: named.map { ($0.id, $0.name) }) == Dictionary(uniqueKeysWithValues: reversed.map { ($0.id, $0.name) }))
        #expect(named[0].initials == "1")
        #expect(named[1].initials == "2")
        #expect(AgentAccount.named([max])[0].name == "Claude Max")
    }

    @Test func renamesStayAndClearingOneRestoresGeneratedName() {
        let defaults = UserDefaults(suiteName: "AccountNames.\(UUID().uuidString)")!
        let settings = AgentsSettings(defaults: defaults)
        let center = UsageCenter(settings: settings, stats: nil)
        let pro = account(), max = account(folder: "/tmp/.claude-work", plan: "Max")
        center.setAccounts([pro, max])
        settings.setNickname("Studio", for: pro.id)
        center.renamed()
        #expect(center.accounts[0].name == "Studio")
        #expect(!center.accounts[0].isDefaultName)
        #expect(center.accounts[1].name == "Claude Max 2")
        settings.setNickname("", for: pro.id)
        center.renamed()
        #expect(center.accounts[0].name == "Claude Pro 1")
        #expect(center.accounts[0].isDefaultName)
        var upgraded = pro
        upgraded.plan = "Ultra"
        center.setAccounts([upgraded, max])
        #expect(center.accounts[0].name == "Claude Ultra 1")
        center.stop()
    }

    @Test func practiceUsesTheSameDefaultsAsRealAccounts() {
        #expect(UsageCenter.practice().accounts.map(\.name) == ["Claude Pro 1", "Claude Max 2", "Codex Plus"])
    }
}
