import Foundation

/// The AI coding tools PancakeNotch follows (ADR-0037). Claude Code and Codex fully; Cursor and Devin
/// only in Agents, and only after Connect (PancakeNotch reads no usage of theirs).
public enum AgentTool: String, CaseIterable, Codable, Sendable {
    case claude, codex, cursor, devin

    /// "Claude Code", "Codex", "Cursor", "Devin".
    public var name: String {
        switch self {
        case .claude: String(localized: "Claude Code", comment: "AI tool name")
        case .codex: String(localized: "Codex", comment: "AI tool name")
        case .cursor: String(localized: "Cursor", comment: "AI tool name")
        case .devin: String(localized: "Devin", comment: "AI tool name")
        }
    }

    /// "Claude", "Codex", "Cursor", "Devin": for tight spots (the account pill, peeks).
    public var shortName: String {
        switch self {
        case .claude: String(localized: "Claude", comment: "Short AI tool name")
        case .codex, .cursor, .devin: name
        }
    }

    /// SF Symbol standing in for the tool (the look stays monochrome, ADR-0029).
    public var symbol: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow.rays"
        case .devin: "circle.hexagonpath"
        }
    }

    /// Tools whose usage (tokens, limits) PancakeNotch can read.
    public var hasUsage: Bool { self == .claude || self == .codex }

    /// Tools whose permission requests can be answered from the notch after Connect.
    public var canAnswerInNotch: Bool { self != .cursor }

    /// Tools whose conversations PancakeNotch reads from their own files (titles, subagents, the
    /// helpers host apps start). The others are known only from their hooks.
    var hasTranscripts: Bool { self == .claude || self == .codex }
}
