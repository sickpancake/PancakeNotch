import Foundation

/// The practice notch's pretend threads (Modules page, the Agents lesson): one working, one asking to
/// run a command, one finished. Allow and Deny play out like the real thing, then the pretend threads
/// come back so the practice can be tried again.
@MainActor
final class PracticeAgents {
    private unowned let center: AgentsCenter
    private var tasks: [Task<Void, Never>] = []

    init(center: AgentsCenter) {
        self.center = center
    }

    static let workingID = "claude:practice-login"
    static let askingID = "codex:practice-parser"
    static let doneID = "cursor:practice-readme"

    static func threads(now: Date) -> [AgentThread] {
        [
            AgentThread(id: workingID, tool: .claude, title: String(localized: "Fix the login redirect", comment: "Practice agent thread"),
                        project: "web-app", status: .working, statusSince: now.addingTimeInterval(-4 * 60),
                        workStarted: now.addingTimeInterval(-4 * 60),
                        step: String(localized: "Running tests", comment: "Practice agent step"), canOpen: true),
            AgentThread(id: askingID, tool: .codex, title: String(localized: "Refactor the parser", comment: "Practice agent thread"),
                        project: "compiler", status: .needsYou(.permission), statusSince: now.addingTimeInterval(-40),
                        workStarted: now.addingTimeInterval(-6 * 60),
                        request: String(localized: "Wants to run: rm -rf build", comment: "Practice agent request"),
                        canAnswer: true, canOpen: true),
            AgentThread(id: doneID, tool: .cursor, title: String(localized: "Update the README", comment: "Practice agent thread"),
                        project: "docs", status: .done, statusSince: now.addingTimeInterval(-2 * 60), canOpen: true, isSeen: true),
        ]
    }

    /// Allow: back to work for a moment, then done. Deny: stopped. A little later everything resets.
    func answer(_ id: String, allow: Bool) {
        guard let thread = center.thread(id) else { return }
        let now = Date()
        if allow {
            center.apply(.init(id: id, tool: thread.tool, at: now, status: .working,
                               step: .some(String(localized: "Running rm -rf build", comment: "Practice agent step")), quietly: true))
            schedule(after: 2.5) { center in
                center.apply(.init(id: id, tool: thread.tool, at: .now, status: .done, quietly: true))
            }
        } else {
            center.apply(.init(id: id, tool: thread.tool, at: now, status: .stopped,
                               request: .some(String(localized: "Denied", comment: "Practice agent: the request was denied")), quietly: true))
        }
        schedule(after: 12) { center in center.reset() }
    }

    private func schedule(after seconds: Double, _ action: @escaping @MainActor (AgentsCenter) -> Void) {
        tasks.append(Task { [weak center] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let center else { return }
            action(center)
        })
    }

    deinit {
        for task in tasks { task.cancel() }
    }
}
