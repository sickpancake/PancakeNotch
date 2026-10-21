import Foundation
import Testing
@testable import AgentsCore

@Test func initialsComeFromTheEmail() {
    let account = AgentAccount(tool: .claude, folder: URL(fileURLWithPath: "/tmp/.claude"), email: "sam@studio.dev")
    #expect(account.initials == "SS")
}
