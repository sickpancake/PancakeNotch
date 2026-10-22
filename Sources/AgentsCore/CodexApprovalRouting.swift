import Foundation

/// PermissionRequest is a policy hook, not proof that Codex needs a person: it also fires before
/// Auto Review. The hook omits the reviewer, but the same turn's saved context includes it. Never
/// guess from a host app, global config, an earlier turn, or a missing field. Runs on the socket queue.
enum CodexApprovalRouting {
    static let tailBytes = 512 * 1024

    static func needsUser(_ event: HookEvent) -> Bool {
        guard event.permissionMode != "bypassPermissions",
              let turnID = event.turnID, !turnID.isEmpty,
              let path = event.transcriptPath,
              let lines = JSONLines.tail(of: URL(fileURLWithPath: path), bytes: tailBytes) else { return false }
        for line in lines.reversed() where line.prefix(200).contains("\"turn_context\"") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "turn_context", let context = object["payload"] as? [String: Any] else { continue }
            // Only the latest context counts, and it must belong to this exact request's turn.
            return context["turn_id"] as? String == turnID
                && context["approvals_reviewer"] as? String == "user"
                && canAsk(context["approval_policy"])
        }
        // Older versions, an unflushed context, or one beyond the bounded read: ask in Codex itself.
        return false
    }

    private static func canAsk(_ policy: Any?) -> Bool {
        if let policy = policy as? String { return ["on-request", "untrusted", "on-failure"].contains(policy) }
        return (policy as? [String: Any])?["granular"] as? [String: Any] != nil
    }
}
