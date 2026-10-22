import Foundation
import Testing
@testable import AgentsCore

@Test func initialsComeFromTheEmail() {
    let account = AgentAccount(tool: .claude, folder: URL(fileURLWithPath: "/tmp/.claude"), email: "sam@studio.example")
    #expect(account.initials == "SS")
}

@MainActor
@Test func practiceModelsGrowWithTheRange() async {
    let usage = UsageCenter.practice()
    let week = await usage.models(days: 7)
    let month = await usage.models(days: 30)
    #expect(!week.isEmpty)
    #expect(month.reduce(0) { $0 + $1.tokens } > week.reduce(0) { $0 + $1.tokens })
}

@Test @MainActor func practiceChartsAndModelsReconcileForEveryAccount() async {
    let center = UsageCenter.practice()
    for selection in [AccountSelection.all] + center.accounts.map({ .account($0.id) }) {
        center.selection = selection
        for days in [1, 7, 30, 90] {
            let daily = await center.daily(days: days)
            let models = await center.models(days: days)
            #expect(daily.count == days)
            #expect(daily.reduce(0) { $0 + $1.tokens } == models.reduce(0) { $0 + $1.tokens })
            #expect(abs(daily.reduce(0) { $0 + $1.cost } - models.reduce(0) { $0 + $1.cost }) < 0.000001)
        }
    }
}
