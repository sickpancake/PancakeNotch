import Foundation

/// Follows the real tools for `AgentsCenter`: Claude Code's session list, Codex's rollouts and, after
/// Connect, the hook helper's socket.
@MainActor
final class LiveAgentSources {
    private unowned let center: AgentsCenter

    init(center: AgentsCenter) {
        self.center = center
    }

    func start() {}
    func stop() {}
    /// The list is on screen: read each working thread's current step.
    func setDetailed(_ detailed: Bool) {}
    func answer(threadID: String, allow: Bool) {}
    /// Hands a pending permission request back to the thread's app.
    func handBack(threadID: String) {}
}
