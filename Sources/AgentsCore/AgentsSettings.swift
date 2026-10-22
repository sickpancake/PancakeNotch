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
    /// AI Usage takes an ear (and peeks once) when an account drops under 10% left.
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
        warnsNearLimit = defaults.object(forKey: Keys.warnsNearLimit) as? Bool ?? true
        offerDismissed = defaults.bool(forKey: Keys.offerDismissed)
        let stored = defaults.string(forKey: Keys.selection)
        selection = stored == nil || stored == Keys.allAccounts ? .all : .account(stored!)
        range = defaults.string(forKey: Keys.range).flatMap(UsageRange.init(rawValue:)) ?? .today
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
