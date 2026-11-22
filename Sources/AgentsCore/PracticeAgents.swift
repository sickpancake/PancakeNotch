import Foundation

/// The practice notch's pretend threads (Modules page, the Agents lesson): one working, one asking to
/// run a command, one finished, and cloud agents (Devin waiting for a reply, Codex cloud working, finished Devin and GitHub
/// coding agent pull requests). Allow and Deny play out like the real thing, then the pretend threads
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
    static let editingID = "claude:practice-button"
    static let cloudID = "devin-cloud:practice-dates"
    static let cloudAskingID = "devin-cloud:practice-ask"
    static let codexCloudID = "codex-cloud:practice-csv"
    static let copilotID = "github-cloud:practice-flaky"

    /// A thread asking to change a file, for the off-screen snapshot's review screen.
    static func editingThread(now: Date) -> AgentThread {
        let change = AgentReview.FileChange(
            path: ["src/components/Button.tsx"], action: .change, warning: nil, everyMatch: false,
            lines: [
                .init(kind: .context, text: "export function Button({ label, onClick }: Props) {"),
                .init(kind: .removed, text: "  return <button onClick={onClick}>{label}</button>"),
                .init(kind: .added, text: "  return ("),
                .init(kind: .added, text: "    <button className=\"button\" onClick={onClick} disabled={!onClick}>"),
                .init(kind: .added, text: "      {label}"),
                .init(kind: .added, text: "    </button>"),
                .init(kind: .added, text: "  )"),
                .init(kind: .context, text: "}"),
            ])
        return AgentThread(id: editingID, tool: .claude, title: String(localized: "Tidy the button styles", comment: "Practice agent thread"),
                           project: "web-app", status: .needsYou(.permission), statusSince: now.addingTimeInterval(-20),
                           workStarted: now.addingTimeInterval(-3 * 60),
                           request: String(localized: "Wants to edit Button.tsx", comment: "Practice agent request"),
                           approval: PendingApproval(requestID: 1, review: AgentReview(content: .edit(change))), canOpen: true,
                           hostName: "Terminal")
    }

    static func threads(now: Date) -> [AgentThread] {
        [
            AgentThread(id: workingID, tool: .claude, title: String(localized: "Fix the login redirect", comment: "Practice agent thread"),
                        project: "web-app", status: .working, statusSince: now.addingTimeInterval(-4 * 60),
                        workStarted: now.addingTimeInterval(-4 * 60),
                        step: String(localized: "Running tests", comment: "Practice agent step"), canOpen: true, hostName: "T3 Code",
                        subagents: [
                            AgentSubagent(id: "claude:practice-cookie", title: String(localized: "Check the session cookie", comment: "Practice subagent"),
                                          status: .working, statusSince: now.addingTimeInterval(-3 * 60)),
                            AgentSubagent(id: "claude:practice-test", title: String(localized: "Write a test for the redirect", comment: "Practice subagent"),
                                          status: .working, statusSince: now.addingTimeInterval(-90)),
                        ]),
            AgentThread(id: askingID, tool: .codex, title: String(localized: "Refactor the parser", comment: "Practice agent thread"),
                        project: "compiler", status: .needsYou(.permission), statusSince: now.addingTimeInterval(-40),
                        workStarted: now.addingTimeInterval(-6 * 60),
                        request: String(localized: "Wants to run: rm -rf build", comment: "Practice agent request"),
                        approval: PendingApproval(requestID: 0, review: AgentReview(content: .command(lines: ["rm -rf build"]))),
                        canOpen: true, hostName: "Codex"),
            AgentThread(id: doneID, tool: .cursor, title: String(localized: "Update the README", comment: "Practice agent thread"),
                        project: "docs", status: .done, statusSince: now.addingTimeInterval(-2 * 60), canOpen: true,
                        hostName: "Cursor", isSeen: true),
            cloudAskingThread(now: now),
            codexCloudThread(now: now),
            cloudThread(now: now),
            copilotThread(now: now),
        ]
    }

    /// Devin cloud sessions working, asking and finished, plus Codex cloud and GitHub's coding agent
    /// (the off-screen snapshot).
    static func cloudThreads(now: Date) -> [AgentThread] {
        var working = AgentThread(id: "devin-cloud:practice-dark", tool: .devin, title: "Add a dark mode", project: "Devin cloud",
                                  status: .working, statusSince: now.addingTimeInterval(-12 * 60), canOpen: true, hostName: cloud)
        var failed = AgentThread(id: "devin-cloud:practice-fail", tool: .devin, title: "Speed up the test suite",
                                 project: "Devin cloud · Out of usage", status: .stopped, statusSince: now.addingTimeInterval(-20 * 60),
                                 canOpen: true, hostName: cloud, isSeen: true)
        working.isCloud = true
        failed.isCloud = true
        return [working, cloudAskingThread(now: now), codexCloudThread(now: now), cloudThread(now: now),
                copilotThread(now: now), failed]
    }

    private static var cloud: String { String(localized: "the cloud", comment: "Where a cloud agent runs, after 'Devin in'") }

    /// A Devin cloud session waiting for a reply, with Stop and Continue.
    private static func cloudAskingThread(now: Date) -> AgentThread {
        var thread = AgentThread(id: cloudAskingID, tool: .devin,
                                 title: String(localized: "Move the API to v3", comment: "Practice agent thread"),
                                 project: "Devin cloud", status: .needsYou(.input), statusSince: now.addingTimeInterval(-3 * 60),
                                 request: String(localized: "Waiting for your reply", comment: "Practice Devin cloud session asking"),
                                 canOpen: true, hostName: cloud)
        thread.isCloud = true
        thread.quickReplies = [.proceed, .stop]
        return thread
    }

    /// A Codex cloud task at work.
    private static func codexCloudThread(now: Date) -> AgentThread {
        var thread = AgentThread(id: codexCloudID, tool: .codex,
                                 title: String(localized: "Add CSV export", comment: "Practice agent thread"),
                                 project: "Codex cloud · pancakenotch-web", status: .working,
                                 statusSince: now.addingTimeInterval(-4 * 60), canOpen: true, hostName: cloud)
        thread.isCloud = true
        return thread
    }

    /// A finished GitHub coding agent task whose pull request's checks failed.
    private static func copilotThread(now: Date) -> AgentThread {
        var thread = AgentThread(id: copilotID, tool: .github,
                                 title: String(localized: "Fix the flaky login test", comment: "Practice agent thread"),
                                 project: "sickpancake/PancakeNotch · PR #131 · Open", status: .done,
                                 statusSince: now.addingTimeInterval(-9 * 60), canOpen: true, hostName: cloud, isSeen: true)
        thread.isCloud = true
        thread.pullRequest = URL(string: "https://github.com/sickpancake/PancakeNotch/pull/131")
        thread.checks = .failed
        return thread
    }

    /// A finished Devin cloud session with its pull request (issue #55).
    private static func cloudThread(now: Date) -> AgentThread {
        var thread = AgentThread(id: cloudID, tool: .devin, title: String(localized: "Upgrade the date library", comment: "Practice agent thread"),
                                 project: String(localized: "Devin cloud · PR #128 · Open", comment: "Practice Devin cloud session: its pull request"),
                                 status: .done, statusSince: now.addingTimeInterval(-6 * 60), canOpen: true,
                                 hostName: String(localized: "the cloud", comment: "Where a cloud agent runs, after 'Devin in'"), isSeen: true)
        thread.isCloud = true
        thread.pullRequest = URL(string: "https://github.com/sickpancake/PancakeNotch/pull/128")
        thread.checks = .passed
        return thread
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

    /// Continue: back to work for a moment, then done. Stop: stopped. A little later everything resets.
    func reply(_ id: String, _ reply: AgentQuickReply) {
        guard let thread = center.thread(id) else { return }
        switch reply {
        case .proceed:
            center.apply(.init(id: id, tool: thread.tool, at: .now, status: .working, quickReplies: [], quietly: true))
            schedule(after: 2.5) { center in
                center.apply(.init(id: id, tool: thread.tool, at: .now, status: .done, quietly: true))
            }
        case .stop:
            center.apply(.init(id: id, tool: thread.tool, at: .now, status: .stopped, quickReplies: [], quietly: true))
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
