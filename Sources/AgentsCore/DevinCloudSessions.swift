import Foundation

/// Devin's cloud sessions as its API reports them (`GET /v3/organizations/{org}/sessions`, issue #55).
/// Only the fields PancakeNotch shows are read; anything missing or unexpected is skipped, never guessed.
struct DevinCloudSession: Decodable, Equatable, Sendable {
    struct PullRequest: Decodable, Equatable, Sendable {
        var prUrl: String?
        var prState: String?
    }

    var sessionId: String
    var url: String?
    /// `new`, `claimed`, `running`, `exit`, `error`, `suspended`, `resuming`.
    var status: String?
    /// While running: `working`, `waiting_for_user`, `waiting_for_approval`, `finished`. While
    /// suspended: why (`inactivity`, `user_request`, `out_of_credits`…).
    var statusDetail: String?
    var title: String?
    var createdAt: Date?
    var updatedAt: Date?
    var acusConsumed: Double?
    var pullRequests: [PullRequest]?
    var userId: String?
    var isArchived: Bool?

    enum CodingKeys: String, CodingKey {
        case sessionId, url, status, statusDetail, title, createdAt, updatedAt, acusConsumed, pullRequests, userId, isArchived
    }

    init(sessionId: String, url: String? = nil, status: String?, statusDetail: String? = nil, title: String? = nil,
         createdAt: Date? = nil, updatedAt: Date? = nil, acusConsumed: Double? = nil,
         pullRequests: [PullRequest]? = nil, userId: String? = nil, isArchived: Bool? = nil) {
        self.sessionId = sessionId
        self.url = url
        self.status = status
        self.statusDetail = statusDetail
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.acusConsumed = acusConsumed
        self.pullRequests = pullRequests
        self.userId = userId
        self.isArchived = isArchived
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        statusDetail = try? c.decodeIfPresent(String.self, forKey: .statusDetail)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        createdAt = Self.date(c, .createdAt)
        updatedAt = Self.date(c, .updatedAt)
        acusConsumed = try? c.decodeIfPresent(Double.self, forKey: .acusConsumed)
        pullRequests = try? c.decodeIfPresent([PullRequest].self, forKey: .pullRequests)
        userId = try? c.decodeIfPresent(String.self, forKey: .userId)
        isArchived = try? c.decodeIfPresent(Bool.self, forKey: .isArchived)
    }

    /// Devin's docs don't say whether its times are seconds or milliseconds: both are read, and ISO
    /// dates too.
    private static func date(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Date? {
        if let number = try? c.decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
        }
        if let text = try? c.decodeIfPresent(String.self, forKey: key) {
            return (try? Date(text, strategy: .iso8601)) ?? (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return nil
    }

    /// Where it stands in the Agents list, and a few words on why when that's worth saying. Nil for a
    /// status PancakeNotch doesn't know: that session is left out rather than shown wrong.
    var agentStatus: (status: AgentStatus, reason: String?)? {
        switch status {
        case "new", "claimed", "resuming":
            return (.working, nil)
        case "running":
            switch statusDetail {
            case "waiting_for_user":
                return (.needsYou(.input), String(localized: "Waiting for your reply", comment: "Devin cloud session: it asked something"))
            case "waiting_for_approval":
                return (.needsYou(.permission), String(localized: "Waiting for your approval", comment: "Devin cloud session: it waits for an approval"))
            case "finished":
                return (.done, nil)
            default:
                return (.working, nil)
            }
        case "exit":
            return (.done, nil)
        case "error":
            return (.failed, String(localized: "Stopped with an error", comment: "Devin cloud session"))
        case "suspended":
            switch statusDetail {
            case "inactivity", nil:
                return (.done, String(localized: "Asleep", comment: "Devin cloud session: suspended after a while without activity"))
            case "user_request":
                return (.stopped, nil)
            case "error":
                return (.failed, String(localized: "Stopped with an error", comment: "Devin cloud session"))
            case "payment_declined":
                return (.failed, String(localized: "Payment declined", comment: "Devin cloud session: why it stopped"))
            default:
                // Out of credits, quota or a usage limit.
                return (.failed, String(localized: "Out of usage", comment: "Devin cloud session: why it stopped"))
            }
        default:
            return nil
        }
    }

    /// Its first pull request, as "PR #128 · Merged" (the state only when Devin gives one).
    var pullRequestLabel: String? {
        guard let pr = pullRequests?.first, let link = pr.prUrl, !link.isEmpty else { return nil }
        let number = link.split(separator: "/").last.flatMap { Int($0) }
        let name = number.map { String(localized: "PR #\($0)", comment: "A pull request and its number") }
            ?? String(localized: "Pull request", comment: "A pull request without a known number")
        guard let state = pr.prState?.trimmingCharacters(in: .whitespaces), !state.isEmpty else { return name }
        return "\(name) · \(state.prefix(1).uppercased())\(state.dropFirst().lowercased())"
    }

    /// The page a click opens: the pull request once it's finished with one, else the session.
    var link: URL? {
        if agentStatus?.status.isFinished == true, let pr = pullRequests?.first?.prUrl, let url = Self.web(pr) { return url }
        return url.flatMap(Self.web)
    }

    /// Only web pages are opened, never another kind of link.
    private static func web(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.host() != nil else { return nil }
        return url
    }
}

/// One page of sessions.
struct DevinCloudPage: Decodable, Sendable {
    var items: [DevinCloudSession]
    var hasNextPage: Bool?
    var endCursor: String?

    enum CodingKeys: String, CodingKey { case items, hasNextPage, endCursor }

    init(items: [DevinCloudSession], hasNextPage: Bool? = nil, endCursor: String? = nil) {
        self.items = items
        self.hasNextPage = hasNextPage
        self.endCursor = endCursor
    }

    /// A session that doesn't read is skipped, not the whole page.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var list = try c.nestedUnkeyedContainer(forKey: .items)
        var items: [DevinCloudSession] = []
        while !list.isAtEnd {
            if let item = try? list.decode(DevinCloudSession.self) { items.append(item) } else { _ = try? list.decode(Skip.self) }
        }
        self.items = items
        hasNextPage = try? c.decodeIfPresent(Bool.self, forKey: .hasNextPage)
        endCursor = try? c.decodeIfPresent(String.self, forKey: .endCursor)
    }

    private struct Skip: Decodable {}
}

/// Who the key belongs to (`GET /v3/self`).
struct DevinCloudIdentity: Decodable, Equatable, Sendable {
    var userId: String?
    var userName: String?
    var orgId: String?
    var devinSessionsOrgId: String?

    /// The organization whose sessions are listed.
    var sessionsOrg: String? { [devinSessionsOrgId, orgId].compactMap { $0 }.first { !$0.isEmpty } }
}

/// What the cloud sessions of the last 30 days used, for AI Usage. Each session counts on the day it began.
public struct DevinCloudUsage: Equatable, Sendable {
    public struct Session: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let started: Date
        public let acus: Double
    }

    public let sessions: [Session]
    /// When Devin was last asked.
    public let updatedAt: Date

    public init(sessions: [Session], updatedAt: Date) {
        self.sessions = sessions
        self.updatedAt = updatedAt
    }

    /// The sessions begun in `range` (local calendar days, today included).
    public func sessions(in range: UsageRange, now: Date = .now, calendar: Calendar = .current) -> [Session] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: 1 - range.days, to: today) else { return sessions }
        return sessions.filter { $0.started >= start }
    }

    /// ACUs used in `range`.
    public func acus(in range: UsageRange, now: Date = .now) -> Double {
        sessions(in: range, now: now).reduce(0) { $0 + $1.acus }
    }

    /// The sessions that used most in `range`, biggest first.
    public func top(_ count: Int, in range: UsageRange, now: Date = .now) -> [Session] {
        Array(sessions(in: range, now: now).filter { $0.acus > 0 }
            .sorted { $0.acus == $1.acus ? $0.started > $1.started : $0.acus > $1.acus }.prefix(count))
    }
}
