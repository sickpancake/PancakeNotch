import Foundation

/// A cloud agent's task as one of the CLI services reports it (issue #55), ready for the Agents list.
struct CloudTask: Equatable, Sendable {
    var id: String
    var title: String
    var status: AgentStatus
    /// A few words on why it waits or stopped ("Waiting for you", "Timed out").
    var reason: String?
    var started: Date?
    var changed: Date?
    /// "sickpancake/PancakeNotch", "PancakeNotch · 3 files": what shows under its name.
    var byline: String?
    var pullRequest: URL?
    var pullRequestLabel: String?
    /// Its own page on the service.
    var page: URL?

    /// The page a click opens: the pull request once it's finished with one, else its own page.
    var link: URL? { status.isFinished ? (pullRequest ?? page) : page }
}

/// A cloud service PancakeNotch follows through its command-line tool, after the user turns it on.
public enum CloudService: String, CaseIterable, Sendable {
    /// Codex cloud tasks, through `codex cloud list` and Codex's own ChatGPT sign-in.
    case codex
    /// GitHub's Copilot coding agent, through `gh agent-task list` and the GitHub CLI's sign-in.
    case github

    public var name: String {
        switch self {
        case .codex: String(localized: "Codex cloud", comment: "OpenAI's cloud coding agent")
        case .github: String(localized: "GitHub coding agent", comment: "GitHub Copilot's cloud coding agent")
        }
    }

    var tool: AgentTool { self == .codex ? .codex : .github }
    var program: CloudCommand.Program { self == .codex ? .codex : .gh }
    var idPrefix: String { "\(rawValue)-cloud:" }

    var listArguments: [String] {
        switch self {
        case .codex: ["cloud", "list", "--json", "--limit", "20"]
        case .github:
            ["agent-task", "list", "--limit", "30", "--json",
             "id,name,state,repository,createdAt,updatedAt,completedAt,pullRequestNumber,pullRequestUrl,pullRequestState"]
        }
    }

    /// Its tasks from what the tool printed; nil when that isn't the tool's JSON at all.
    func tasks(from data: Data) -> [CloudTask]? {
        switch self {
        case .codex: CodexCloudTask.tasks(from: data)
        case .github: GitHubAgentTask.tasks(from: data)
        }
    }
}

// MARK: Codex cloud

/// One task in `codex cloud list --json`: `{"tasks": [{"id", "url", "title", "status", "updated_at", ...}]}`.
struct CodexCloudTask: Decodable, Sendable {
    var id: String
    var url: String?
    var title: String?
    var status: String?
    var updatedAt: Date?
    var environmentLabel: String?
    var summary: Summary?
    var isReview: Bool?

    struct Summary: Decodable, Sendable { var filesChanged: Int? }

    private struct Page: Decodable { var tasks: [Lossy<CodexCloudTask>] }

    static func tasks(from data: Data) -> [CloudTask]? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom(CloudDates.decode)
        guard let page = try? decoder.decode(Page.self, from: data) else { return nil }
        return page.tasks.compactMap(\.value).compactMap(\.cloudTask)
    }

    var cloudTask: CloudTask? {
        let status: AgentStatus, reason: String?
        switch self.status?.lowercased() {
        case "pending": (status, reason) = (.working, nil)
        case "ready": (status, reason) = (.done, nil)
        case "applied": (status, reason) = (.done, String(localized: "Applied", comment: "Codex cloud task: its change was applied on this Mac"))
        case "error": (status, reason) = (.failed, String(localized: "Stopped with an error", comment: "A cloud agent's task"))
        default: return nil
        }
        var byline = environmentLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        if status == .done, let files = summary?.filesChanged, files > 0 {
            byline = [byline, String(localized: "\(files) files changed", comment: "Codex cloud task: the size of its change")]
                .compactMap { $0 }.joined(separator: " · ")
        }
        if let reason { byline = [byline, reason].compactMap { $0 }.joined(separator: " · ") }
        return CloudTask(id: id, title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? CloudService.codex.name,
                         status: status, reason: reason, started: nil, changed: updatedAt, byline: byline,
                         page: url.flatMap(CloudDates.web))
    }
}

// MARK: GitHub coding agent

/// One session in `gh agent-task list --json ...`.
struct GitHubAgentTask: Decodable, Sendable {
    var id: String
    var name: String?
    var state: String?
    var repository: String?
    var createdAt: Date?
    var updatedAt: Date?
    var completedAt: Date?
    var pullRequestNumber: Int?
    var pullRequestUrl: String?
    var pullRequestState: String?

    static func tasks(from data: Data) -> [CloudTask]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(CloudDates.decode)
        guard let items = try? decoder.decode([Lossy<GitHubAgentTask>].self, from: data) else { return nil }
        // The list holds a session per turn; the newest of each pull request stands for it.
        var seen: Set<String> = []
        return items.compactMap(\.value)
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .filter { seen.insert($0.pullRequestUrl ?? $0.id).inserted }
            .compactMap(\.cloudTask)
    }

    var cloudTask: CloudTask? {
        let status: AgentStatus, reason: String?
        switch state?.lowercased() {
        case "queued", "in_progress": (status, reason) = (.working, nil)
        case "waiting_for_user": (status, reason) = (.needsYou(.input), String(localized: "Waiting for you", comment: "GitHub coding agent: it asked something"))
        case "completed", "idle": (status, reason) = (.done, nil)
        case "failed": (status, reason) = (.failed, String(localized: "Stopped with an error", comment: "A cloud agent's task"))
        case "timed_out": (status, reason) = (.failed, String(localized: "Timed out", comment: "GitHub coding agent: ran out of time"))
        case "cancelled": (status, reason) = (.stopped, nil)
        default: return nil
        }
        let pr = pullRequestUrl.flatMap(CloudDates.web)
        let label = pullRequestNumber.map { number in
            let name = String(localized: "PR #\(number)", comment: "A pull request and its number")
            guard let state = pullRequestState?.trimmingCharacters(in: .whitespaces).nonEmpty else { return name }
            return "\(name) · \(state.prefix(1).uppercased())\(state.dropFirst().lowercased())"
        }
        let repo = repository?.split(separator: "/").last.map(String.init)?.nonEmpty
        let byline = [repo, status.isFinished ? label : nil, status.needsYou ? nil : reason].compactMap { $0 }.joined(separator: " · ")
        // Its log lives on the pull request's agent page.
        let page = pr.flatMap { URL(string: $0.absoluteString + "/agent-sessions/" + id) } ?? pr
        return CloudTask(id: id, title: name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? CloudService.github.name,
                         status: status, reason: reason, started: createdAt, changed: completedAt ?? updatedAt,
                         byline: byline.nonEmpty, pullRequest: pr, pullRequestLabel: label, page: page)
    }
}

// MARK: Pull request checks

/// Where a pull request's CI checks stand, from `gh pr checks --json bucket`.
public enum PullRequestChecks: Equatable, Sendable {
    case running, passed, failed

    /// From the checks' buckets ("pass", "fail", "pending", "skipping", "cancel"); nil without checks.
    static func from(_ data: Data) -> PullRequestChecks? {
        struct Check: Decodable { var bucket: String? }
        guard let checks = try? JSONDecoder().decode([Check].self, from: data) else { return nil }
        let buckets = checks.compactMap { $0.bucket?.lowercased() }
        if buckets.contains(where: { $0 == "fail" || $0 == "cancel" }) { return .failed }
        if buckets.contains("pending") { return .running }
        return buckets.contains("pass") ? .passed : nil
    }

    public var label: String {
        switch self {
        case .running: String(localized: "Checks running", comment: "A pull request's CI checks are still running")
        case .passed: String(localized: "Checks passed", comment: "A pull request's CI checks all passed")
        case .failed: String(localized: "Checks failed", comment: "A pull request's CI checks: at least one failed")
        }
    }
}

// MARK: Helpers

/// A list item that may not decode: it's skipped, not the whole list.
struct Lossy<Value: Decodable>: Decodable {
    var value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

enum CloudDates {
    /// ISO 8601 with or without fractions, or seconds since 1970.
    static func decode(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) { return Date(timeIntervalSince1970: seconds > 1e11 ? seconds / 1000 : seconds) }
        let text = try container.decode(String.self)
        if let date = try? Date(text, strategy: .iso8601) { return date }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a date: \(text)")
    }

    /// Only an https page opens from a row.
    static func web(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host() != nil else { return nil }
        return url
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
