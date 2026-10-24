import Foundation
import Observation

/// Options for Agents and AI Usage (Modules and Settings pages). Stored in `UserDefaults`.
/// Whether a tool is connected isn't stored here: the tool's own hook file says so (`AgentConnector`).
@MainActor
@Observable
public final class AgentsSettings {
    /// The Agents module. Off until the user turns it on (ADR-0037).
    public var agentsEnabled: Bool { didSet { defaults.set(agentsEnabled, forKey: Keys.agentsEnabled) } }
    /// The AI Usage module. Off until the user turns it on.
    public var usageEnabled: Bool { didSet { defaults.set(usageEnabled, forKey: Keys.usageEnabled) } }
    /// Pop up under the notch when a thread needs you.
    public var peeksOnNeedsYou: Bool { didSet { defaults.set(peeksOnNeedsYou, forKey: Keys.peeksOnNeedsYou) } }
    /// Pop up when a thread finishes after 30 seconds or more of work.
    public var peeksOnFinish: Bool { didSet { defaults.set(peeksOnFinish, forKey: Keys.peeksOnFinish) } }
    /// What names each thread in the Agents list.
    public var nameStyle: AgentNameStyle { didSet { defaults.set(nameStyle.rawValue, forKey: Keys.nameStyle) } }
    /// What shows under each thread's name.
    public var detailStyle: AgentDetailStyle { didSet { defaults.set(detailStyle.rawValue, forKey: Keys.detailStyle) } }
    /// How long a finished thread stays after it was seen.
    public var keepFinished: KeepFinished { didSet { defaults.set(keepFinished.rawValue, forKey: Keys.keepFinished) } }
    /// Tools whose threads Agents leaves out.
    public var hiddenTools: Set<AgentTool> {
        didSet { defaults.set(hiddenTools.map(\.rawValue).sorted(), forKey: Keys.hiddenTools) }
    }
    /// The "2 subagents" button under a thread.
    public var showsSubagents: Bool { didSet { defaults.set(showsSubagents, forKey: Keys.showsSubagents) } }
    /// What a working thread is doing ("Editing NotchView.swift"), under its name.
    public var showsSteps: Bool { didSet { defaults.set(showsSteps, forKey: Keys.showsSteps) } }
    /// AI Usage peeks once when an account drops under 10% left.
    public var warnsNearLimit: Bool { didSet { defaults.set(warnsNearLimit, forKey: Keys.warnsNearLimit) } }
    /// The user dismissed the "We found Claude Code…" offer on Home and Modules.
    public var offerDismissed: Bool { didSet { defaults.set(offerDismissed, forKey: Keys.offerDismissed) } }

    /// The account AI Usage shows.
    public var selection: AccountSelection {
        didSet {
            switch selection {
            case .all: defaults.set(Keys.allAccounts, forKey: Keys.selection)
            case .account(let id): defaults.set(id, forKey: Keys.selection)
            }
        }
    }

    public var range: UsageRange { didSet { defaults.set(range.rawValue, forKey: Keys.range) } }

    /// When AI Usage shows beside the closed notch.
    public var earMode: UsageEarMode { didSet { defaults.set(earMode.rawValue, forKey: Keys.earMode) } }
    /// The account the closed notch and the near-limit pop-up follow (`.all`: whichever is closest to its limit).
    public var earAccount: AccountSelection {
        didSet {
            switch earAccount {
            case .all: defaults.set(Keys.allAccounts, forKey: Keys.earAccount)
            case .account(let id): defaults.set(id, forKey: Keys.earAccount)
            }
        }
    }
    /// The limit the closed notch and the near-limit pop-up follow.
    public var earLimit: UsageEarLimit { didSet { defaults.set(earLimit.rawValue, forKey: Keys.earLimit) } }

    /// Nicknames by account ID.
    public var nicknames: [String: String] { didSet { defaults.set(nicknames, forKey: Keys.nicknames) } }
    /// Account folders the user added ("Add account folder…"), as paths.
    public var addedFolders: [String] { didSet { defaults.set(addedFolders, forKey: Keys.addedFolders) } }
    /// Ignore older requests even if a tool later moves a cleared log into its archive.
    public var historyClearedAt: Date? { didSet { defaults.set(historyClearedAt, forKey: Keys.historyClearedAt) } }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        agentsEnabled = defaults.bool(forKey: Keys.agentsEnabled)
        usageEnabled = defaults.bool(forKey: Keys.usageEnabled)
        peeksOnNeedsYou = defaults.object(forKey: Keys.peeksOnNeedsYou) as? Bool ?? true
        peeksOnFinish = defaults.object(forKey: Keys.peeksOnFinish) as? Bool ?? true
        nameStyle = defaults.string(forKey: Keys.nameStyle).flatMap(AgentNameStyle.init(rawValue:)) ?? .title
        detailStyle = defaults.string(forKey: Keys.detailStyle).flatMap(AgentDetailStyle.init(rawValue:)) ?? .folder
        keepFinished = defaults.string(forKey: Keys.keepFinished).flatMap(KeepFinished.init(rawValue:)) ?? .halfHour
        hiddenTools = Set((defaults.stringArray(forKey: Keys.hiddenTools) ?? []).compactMap(AgentTool.init(rawValue:)))
        showsSubagents = defaults.object(forKey: Keys.showsSubagents) as? Bool ?? true
        showsSteps = defaults.object(forKey: Keys.showsSteps) as? Bool ?? true
        warnsNearLimit = defaults.object(forKey: Keys.warnsNearLimit) as? Bool ?? true
        offerDismissed = defaults.bool(forKey: Keys.offerDismissed)
        let stored = defaults.string(forKey: Keys.selection)
        selection = stored == nil || stored == Keys.allAccounts ? .all : .account(stored!)
        range = defaults.string(forKey: Keys.range).flatMap(UsageRange.init(rawValue:)) ?? .today
        // Before this choice, turning the warning off also hid the ear.
        earMode = defaults.string(forKey: Keys.earMode).flatMap(UsageEarMode.init(rawValue:))
            ?? (defaults.object(forKey: Keys.warnsNearLimit) as? Bool == false ? .never : .nearLimit)
        let earAccount = defaults.string(forKey: Keys.earAccount)
        self.earAccount = earAccount == nil || earAccount == Keys.allAccounts ? .all : .account(earAccount!)
        earLimit = defaults.string(forKey: Keys.earLimit).flatMap(UsageEarLimit.init(rawValue:)) ?? .closest
        nicknames = defaults.dictionary(forKey: Keys.nicknames) as? [String: String] ?? [:]
        addedFolders = defaults.stringArray(forKey: Keys.addedFolders) ?? []
        historyClearedAt = defaults.object(forKey: Keys.historyClearedAt) as? Date
    }

    /// Sets or clears (empty text) an account's nickname.
    public func setNickname(_ name: String, for accountID: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        nicknames[accountID] = trimmed.isEmpty ? nil : trimmed
    }

    private enum Keys {
        static let agentsEnabled = "agents.enabled"
        static let usageEnabled = "aiUsage.enabled"
        static let peeksOnNeedsYou = "agents.peeksOnNeedsYou"
        static let peeksOnFinish = "agents.peeksOnFinish"
        static let nameStyle = "agents.nameStyle"
        static let detailStyle = "agents.detailStyle"
        static let keepFinished = "agents.keepFinished"
        static let hiddenTools = "agents.hiddenTools"
        static let showsSubagents = "agents.showsSubagents"
        static let showsSteps = "agents.showsSteps"
        static let earMode = "aiUsage.earMode"
        static let earAccount = "aiUsage.earAccount"
        static let earLimit = "aiUsage.earLimit"
        static let warnsNearLimit = "aiUsage.warnsNearLimit"
        static let offerDismissed = "agents.offerDismissed"
        static let selection = "aiUsage.selection"
        static let range = "aiUsage.range"
        static let nicknames = "aiUsage.nicknames"
        static let addedFolders = "aiUsage.addedFolders"
        static let historyClearedAt = "aiUsage.historyClearedAt"
        static let allAccounts = "*all*"
    }
}

/// How long a finished agent stays in the list after it was seen.
public enum KeepFinished: String, CaseIterable, Sendable {
    case fiveMinutes, halfHour, untilCleared

    /// Nil: until "Clear finished".
    public var interval: TimeInterval? {
        switch self {
        case .fiveMinutes: 5 * 60
        case .halfHour: 30 * 60
        case .untilCleared: nil
        }
    }

    public var label: String {
        switch self {
        case .fiveMinutes: String(localized: "5 min", comment: "Keep finished agents for: five minutes")
        case .halfHour: String(localized: "30 min", comment: "Keep finished agents for: half an hour")
        case .untilCleared: String(localized: "Until cleared", comment: "Keep finished agents until Clear finished")
        }
    }
}

/// When AI Usage shows beside the closed notch.
public enum UsageEarMode: String, CaseIterable, Sendable {
    case never
    /// Only while the followed limit is under 10% left.
    case nearLimit
    case always

    public var label: String {
        switch self {
        case .never: String(localized: "Never", comment: "AI Usage beside the closed notch: never")
        case .nearLimit: String(localized: "When close", comment: "AI Usage beside the closed notch: only near the limit")
        case .always: String(localized: "Always", comment: "AI Usage beside the closed notch: always")
        }
    }
}

/// Which limit the closed notch follows.
public enum UsageEarLimit: String, CaseIterable, Sendable {
    /// Whichever has the least left.
    case closest
    case session
    case weekly

    public var label: String {
        switch self {
        case .closest: String(localized: "Closest", comment: "AI Usage limit to follow: whichever has the least left")
        case .session: String(localized: "Session", comment: "AI Usage limit to follow: the 5-hour one")
        case .weekly: String(localized: "Weekly", comment: "AI Usage limit to follow: the weekly one")
        }
    }
}
