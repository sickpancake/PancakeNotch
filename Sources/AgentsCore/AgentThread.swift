import Foundation

/// What a thread is waiting for while it needs the user.
public enum AgentNeed: Equatable, Sendable {
    /// A permission request ("Wants to run: npm test").
    case permission
    /// A question or the next message.
    case input
}

/// Where an agent thread is (ADR-0037).
public enum AgentStatus: Equatable, Sendable {
    case working
    case needsYou(AgentNeed)
    case done
    /// Interrupted by the user.
    case stopped
    case failed

    /// Needs you first, then working, then the finished ones.
    var sortRank: Int {
        switch self {
        case .needsYou: 0
        case .working: 1
        case .failed: 2
        case .done, .stopped: 3
        }
    }

    public var isFinished: Bool {
        switch self {
        case .done, .stopped, .failed: true
        case .working, .needsYou: false
        }
    }

    public var needsYou: Bool {
        if case .needsYou = self { return true }
        return false
    }

    /// "Working", "Needs you", "Done", "Stopped", "Error".
    public var label: String {
        switch self {
        case .working: String(localized: "Working", comment: "Agent status")
        case .needsYou: String(localized: "Needs you", comment: "Agent status")
        case .done: String(localized: "Done", comment: "Agent status")
        case .stopped: String(localized: "Stopped", comment: "Agent status")
        case .failed: String(localized: "Error", comment: "Agent status")
        }
    }
}

/// One agent thread (a Claude Code session, a Codex thread, a Cursor conversation).
public struct AgentThread: Identifiable, Equatable, Sendable {
    /// "<tool>:<session id>".
    public let id: String
    public let tool: AgentTool
    /// The account it runs under, when known (see `AgentAccount.id`).
    public var accountID: String?
    /// The conversation's title, or its project folder when it has none. In `AgentsCenter.threads`, the
    /// name the user picked in Settings (`name(_:)`).
    public var title: String
    /// The last message the user sent it (one line), when known.
    public var lastMessage: String?
    /// The git branch of its project folder, when it's in a repository.
    public var branch: String?
    /// The project folder's name ("PancakeNotch").
    public var project: String
    public var status: AgentStatus
    /// When `status` began: "Working · 4m", "Done · 2m ago".
    public var statusSince: Date
    /// When the current stretch of work began (a finish only pops up after 30 s of work).
    public var workStarted: Date?
    /// What it's doing right now ("Editing NotchView.swift"), while the list is on screen.
    public var step: String?
    /// What it's waiting for ("Wants to run: npm test", "input needed").
    public var request: String?
    /// The request can be answered with Allow / Deny right in the notch (after Connect).
    public var canAnswer: Bool
    /// The waiting request Allow / Deny would answer, so a click never answers one that replaced it.
    var answerID: Int?
    /// A helper a host app started for another conversation (`DelegatedHelpers`): that one's ID, and
    /// the title it gave the task. It shows under that conversation, not as a thread of its own.
    var parentID: String?
    var helperTitle: String?
    /// The app it runs in is known, so a click can bring it forward.
    public var canOpen: Bool
    /// The user has seen it finished (the list was on screen).
    public var isSeen: Bool
    /// The helpers it started that are still working, oldest first. Shown under it, never as threads.
    public var subagents: [AgentSubagent]
    /// What shows under its name, as picked in Settings (`byline(_:name:)`). Nil: its project folder.
    public var byline: String?

    public init(id: String, tool: AgentTool, accountID: String? = nil, title: String, project: String,
                status: AgentStatus, statusSince: Date, workStarted: Date? = nil, step: String? = nil,
                request: String? = nil, canAnswer: Bool = false, canOpen: Bool = false, isSeen: Bool = false,
                subagents: [AgentSubagent] = [], lastMessage: String? = nil, branch: String? = nil) {
        self.id = id
        self.tool = tool
        self.accountID = accountID
        self.title = title
        self.project = project
        self.status = status
        self.statusSince = statusSince
        self.workStarted = workStarted
        self.step = step
        self.request = request
        self.canAnswer = canAnswer
        self.canOpen = canOpen
        self.isSeen = isSeen
        self.subagents = subagents
        self.lastMessage = lastMessage
        self.branch = branch
    }

    /// What names it in the list: the chosen kind of name, else its title.
    public func name(_ style: AgentNameStyle) -> String {
        switch style {
        case .title: title
        case .lastMessage: lastMessage ?? title
        case .branch: branch ?? title
        }
    }

    /// What goes under `name`: the chosen kind, else the folder, the last message or the branch, never
    /// the name again ("Volunaro" twice). Empty when each of them is missing or the same as the name.
    public func byline(_ style: AgentDetailStyle, name: String) -> String {
        let chosen: String? = switch style {
        case .folder: project
        case .lastMessage: lastMessage
        case .branch: branch
        }
        return [chosen, project, lastMessage, branch].lazy.compactMap { $0 }
            .first { !$0.isEmpty && $0.caseInsensitiveCompare(name) != .orderedSame } ?? ""
    }
}

/// A helper a thread started: a Claude Code subagent, a Codex spawned agent.
public struct AgentSubagent: Identifiable, Equatable, Sendable {
    /// "<tool>:<its own id>".
    public let id: String
    /// What it was asked to do ("Review the parser"), or its name.
    public var title: String
    public var status: AgentStatus
    public var statusSince: Date

    public init(id: String, title: String, status: AgentStatus, statusSince: Date) {
        self.id = id
        self.title = title
        self.status = status
        self.statusSince = statusSince
    }
}

/// What the closed notch's Agents ear shows: the most urgent thing going on.
public enum AgentsAttention: Equatable, Sendable {
    /// `count` threads need the user.
    case needsYou(count: Int)
    /// `count` threads stopped with an error and haven't been seen.
    case failed(count: Int)
    /// `count` threads finished (or were stopped) and haven't been seen.
    case finished(count: Int)
    /// `count` threads are working.
    case working(count: Int)
}

/// Something worth a peek under the notch (already filtered by the smart rules, ADR-0037).
public struct AgentAlert: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case needsYou, finished, failed }
    public let kind: Kind
    public let thread: AgentThread

    public init(kind: Kind, thread: AgentThread) {
        self.kind = kind
        self.thread = thread
    }
}
