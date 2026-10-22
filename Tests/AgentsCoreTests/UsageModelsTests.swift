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
