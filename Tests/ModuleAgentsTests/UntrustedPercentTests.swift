import Testing
@testable import ModuleAgents

struct UntrustedPercentTests {
    @Test func invalidPercentagesDoNotTrap() {
        for value in [Double.nan, .infinity, -.infinity, -1, Double.greatestFiniteMagnitude, Double(Int.max)] {
            #expect(AIUsageText.percent(value) == 0)
        }
        #expect(AIUsageText.percent(62.7) == 63)
    }
}
