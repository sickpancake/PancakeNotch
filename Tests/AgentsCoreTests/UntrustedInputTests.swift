import Foundation
import Testing
@testable import AgentsCore

struct UntrustedInputTests {
    @Test func aHugeMessageHasABoundedTitle() {
        let message = "Fix this " + String(repeating: "word ", count: 840_000)
        #expect(AgentNames.oneLine(message)?.count == 80)
        #expect(AgentNames.oneLine("First line\n" + message) == "First line")
        #expect(AgentNames.oneLine(String(repeating: " ", count: 4 * 1024 * 1024)) == nil)
    }

    @Test func invalidPIDsNeverBecomeAnotherProcess() throws {
        for pid in [-1.0, 0, 1.5, Double(Int64.max), Double(UInt64.max)] {
            let data = try JSONSerialization.data(withJSONObject: ["pid": pid, "sessionId": "test", "status": "busy"])
            #expect(ClaudeSession(data: data) == nil)
        }
        let valid = Data(#"{"pid":123,"sessionId":"test","status":"busy"}"#.utf8)
        #expect(ClaudeSession(data: valid)?.pid == 123)
    }

    @Test func overflowingAndNegativeTokenCountsAreRejected() {
        for counts in [#""input_tokens":9223372036854775807,"output_tokens":1"#,
                       #""input_tokens":-1,"output_tokens":2"#,
                       #""input_tokens":1e100,"output_tokens":2"#,
                       #""input_tokens":1.5,"output_tokens":2"#] {
            let line = Data("{\"type\":\"assistant\",\"timestamp\":\"2026-10-22T10:00:00Z\",\"message\":{\"id\":\"test\",\"model\":\"claude-sonnet-4-6\",\"usage\":{\(counts)}}}".utf8)
            #expect(ClaudeUsageLog.record(line, account: "test") == nil)
        }
        var codex = CodexUsageLog()
        let line = Data(#"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":-1,"total_tokens":9223372036854775807}}}}"#.utf8)
        #expect(codex.record(line, account: "test", fallbackThread: "test") == nil)
        #expect(codex.total == 0)
    }

    @Test func delegationScansUTF8IncludingUnicodeStrings() {
        let source = String(repeating: " ", count: 4 * 1024 * 1024 - 200) + #"tools.mcp__t3_code__delegate_task({task:'Check café 🎵',title:'\u0041'});"#
        let input = DelegationScript.inputs(source).first
        #expect(input?["task"] as? String == "Check café 🎵")
        #expect(input?["title"] as? String == "A")
    }
}
