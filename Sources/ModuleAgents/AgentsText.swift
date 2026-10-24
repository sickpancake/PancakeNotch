import AgentsCore
import Foundation

/// The words Agents shows, kept apart from the views so they can be tested.
enum AgentsText {
    /// How long, in one or two units: "40s", "4m", "2h 5m", "3d". Whole units, rounded down.
    static func span(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let (value, units): (Int, Set<Duration.UnitsFormatStyle.Unit>) = switch total {
        case ..<60: (total, [.seconds])
        case ..<3_600: (total / 60 * 60, [.minutes])
        case ..<86_400: (total / 60 * 60, [.hours, .minutes])
        default: (total / 86_400 * 86_400, [.days])
        }
        return Duration.seconds(value).formatted(.units(allowed: units, width: .narrow))
    }

    /// "Working · 4m", "Needs you · 40s", "Done · 2m ago".
    static func statusLine(_ status: AgentStatus, since: Date, now: Date) -> String {
        let time = span(now.timeIntervalSince(since))
        return status.isFinished
            ? String(localized: "\(status.label) · \(time) ago", comment: "Agent row: status and how long ago, e.g. Done · 2m ago")
            : String(localized: "\(status.label) · \(time)", comment: "Agent row: status and how long, e.g. Working · 4m")
    }

    /// Under the title: "project · step" while working, "project · request" while it needs you, else "project".
    /// "project" is the folder, or what Settings put in its place (`AgentThread.byline`).
    static func subtitle(_ thread: AgentThread) -> String {
        let detail: String? = switch thread.status {
        case .working: thread.step
        case .needsYou: thread.request
        case .done, .stopped, .failed: nil
        }
        return [thread.byline ?? thread.project, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "2 working · 1 needs you", with "1 done" for finished threads when asked. `nil` when there's nothing.
    static func summary(_ threads: [AgentThread], includesFinished: Bool) -> String? {
        let working = threads.count { $0.status == .working }
        let needing = threads.count { $0.status.needsYou }
        let finished = includesFinished ? threads.count { $0.status.isFinished } : 0
        var parts: [String] = []
        if working > 0 { parts.append(String(localized: "\(working) working", comment: "Agents summary")) }
        if needing == 1 { parts.append(String(localized: "1 needs you", comment: "Agents summary")) }
        if needing > 1 { parts.append(String(localized: "\(needing) need you", comment: "Agents summary")) }
        if finished > 0 { parts.append(String(localized: "\(finished) done", comment: "Agents summary: finished threads")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The strip under the notch: who it is and what happened ("Claude · web-app", "needs you").
    static func peek(_ alert: AgentAlert) -> (subject: String, verb: String) {
        let thread = alert.thread
        let subject = "\(thread.tool.shortName) · \(thread.project.isEmpty ? thread.title : thread.project)"
        let verb: String = switch alert.kind {
        case .needsYou: String(localized: "needs you", comment: "Agent peek, after the project's name")
        case .finished: String(localized: "finished", comment: "Agent peek, after the project's name")
        case .failed: String(localized: "stopped with an error", comment: "Agent peek, after the project's name")
        }
        return (subject, verb)
    }

    /// "1 subagent", "2 subagents".
    static func subagents(_ count: Int) -> String {
        count == 1 ? String(localized: "1 subagent", comment: "Agent row: helpers the thread started")
            : String(localized: "\(count) subagents", comment: "Agent row: helpers the thread started")
    }

    /// For VoiceOver, one row: "Fix the login redirect, Claude Code, web-app · Running tests, Working · 4m,
    /// 2 subagents".
    static func spoken(_ thread: AgentThread, now: Date) -> String {
        [thread.title, thread.tool.name, subtitle(thread), statusLine(thread.status, since: thread.statusSince, now: now),
         thread.subagents.isEmpty ? "" : subagents(thread.subagents.count)]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// "Subagent, Check the session cookie, Working · 3m".
    static func spoken(_ subagent: AgentSubagent, now: Date) -> String {
        [String(localized: "Subagent", comment: "VoiceOver: a helper under an agent thread"), subagent.title,
         statusLine(subagent.status, since: subagent.statusSince, now: now)].joined(separator: ", ")
    }

    /// Read while the notch is compact: "2 agents need you".
    static func spoken(_ attention: AgentsAttention) -> String {
        switch attention {
        case .needsYou(let count):
            count == 1 ? String(localized: "An agent needs you", comment: "VoiceOver, compact notch")
                : String(localized: "\(count) agents need you", comment: "VoiceOver, compact notch")
        case .failed(let count):
            count == 1 ? String(localized: "An agent stopped with an error", comment: "VoiceOver, compact notch")
                : String(localized: "\(count) agents stopped with an error", comment: "VoiceOver, compact notch")
        case .finished(let count):
            count == 1 ? String(localized: "An agent finished", comment: "VoiceOver, compact notch")
                : String(localized: "\(count) agents finished", comment: "VoiceOver, compact notch")
        case .working(let count):
            count == 1 ? String(localized: "An agent is working", comment: "VoiceOver, compact notch")
                : String(localized: "\(count) agents are working", comment: "VoiceOver, compact notch")
        }
    }
}

extension AgentsAttention {
    var count: Int {
        switch self {
        case .needsYou(let count), .failed(let count), .finished(let count), .working(let count): count
        }
    }

    /// The mark that stands for it in the ear.
    var status: AgentStatus {
        switch self {
        case .needsYou: .needsYou(.permission)
        case .failed: .failed
        case .finished: .done
        case .working: .working
        }
    }
}
