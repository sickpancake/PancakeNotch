import Foundation

/// Short words for what an agent is doing ("Editing NotchView.swift", "Running npm test") and what it
/// asks for ("Wants to run: rm -rf build"), from a tool call's name and input. Only file names and the
/// start of a command are kept, never file contents.
enum AgentSteps {
    /// What a tool call is doing, for a working thread's row.
    static func step(tool name: String, input: [String: Any]) -> String {
        switch kind(of: name) {
        case .run: return command(in: input).map { String(localized: "Running \($0)", comment: "Agent step") }
            ?? String(localized: "Running a command", comment: "Agent step")
        case .edit: return file(in: input).map { String(localized: "Editing \($0)", comment: "Agent step") }
            ?? String(localized: "Editing files", comment: "Agent step")
        case .read: return file(in: input).map { String(localized: "Reading \($0)", comment: "Agent step") }
            ?? String(localized: "Reading files", comment: "Agent step")
        case .search: return String(localized: "Searching the code", comment: "Agent step")
        case .web: return String(localized: "Looking on the web", comment: "Agent step")
        case .agent: return String(localized: "Running a helper agent", comment: "Agent step")
        case .plan: return String(localized: "Planning", comment: "Agent step")
        case .other(let tool): return String(localized: "Using \(tool)", comment: "Agent step: a tool's name")
        }
    }

    /// What a permission request asks for, for a waiting thread's row.
    static func request(tool name: String, input: [String: Any]) -> String {
        switch kind(of: name) {
        case .run: return command(in: input).map { String(localized: "Wants to run: \($0)", comment: "Agent permission request") }
            ?? String(localized: "Wants to run a command", comment: "Agent permission request")
        case .edit: return file(in: input).map { String(localized: "Wants to edit \($0)", comment: "Agent permission request") }
            ?? String(localized: "Wants to edit files", comment: "Agent permission request")
        case .read: return file(in: input).map { String(localized: "Wants to read \($0)", comment: "Agent permission request") }
            ?? String(localized: "Wants to read files", comment: "Agent permission request")
        case .web: return host(in: input).map { String(localized: "Wants to open \($0)", comment: "Agent permission request: a website") }
            ?? String(localized: "Wants to use the web", comment: "Agent permission request")
        case .search, .agent, .plan: return String(localized: "Wants to use \(display(name))", comment: "Agent permission request: a tool's name")
        case .other(let tool): return String(localized: "Wants to use \(tool)", comment: "Agent permission request: a tool's name")
        }
    }

    private enum Kind {
        case run, edit, read, search, web, agent, plan
        case other(String)
    }

    private static func kind(of name: String) -> Kind {
        switch name {
        case "Bash", "BashOutput", "shell", "exec_command", "local_shell", "Shell", "run_terminal_cmd", "PowerShell": .run
        case "Edit", "MultiEdit", "Write", "NotebookEdit", "apply_patch", "write_file", "edit_file": .edit
        case "Read", "read_file", "view_image": .read
        case "Grep", "Glob", "LS", "grep", "glob", "codebase_search", "file_search": .search
        case "WebFetch", "WebSearch", "web_search", "web_fetch": .web
        case "Task", "Agent", "spawn_agent": .agent
        case "TodoWrite", "update_plan", "ExitPlanMode": .plan
        default: .other(display(name))
        }
    }

    /// "mcp__github__create_issue" → "create_issue (github)"; other names as they are.
    private static func display(_ name: String) -> String {
        let parts = name.components(separatedBy: "__")
        if parts.count >= 3, parts[0] == "mcp" { return "\(parts[2...].joined(separator: "__")) (\(parts[1]))" }
        return name
    }

    /// The start of the command: its first line, cut at 60 characters.
    static func command(in input: [String: Any]) -> String? {
        let value = input["command"] ?? input["cmd"]
        let text: String? = (value as? String) ?? (value as? [String]).map { $0.joined(separator: " ") }
        guard let line = text?.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces), !line.isEmpty else { return nil }
        // An `apply_patch` "command" is the patch itself.
        if line.hasPrefix("*** Begin Patch") { return nil }
        return line.count > 60 ? String(line.prefix(59)) + "…" : line
    }

    /// The file's name (not its folder).
    static func file(in input: [String: Any]) -> String? {
        for key in ["file_path", "path", "notebook_path", "filename", "target_file"] {
            if let path = input[key] as? String, !path.isEmpty { return URL(fileURLWithPath: path).lastPathComponent }
        }
        // apply_patch: "*** Update File: Sources/App.swift".
        if let patch = (input["command"] as? String) ?? (input["input"] as? String) ?? (input["patch"] as? String) {
            for marker in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] {
                if let range = patch.range(of: marker) {
                    let path = patch[range.upperBound...].prefix { !$0.isNewline }
                    return URL(fileURLWithPath: String(path)).lastPathComponent
                }
            }
        }
        return nil
    }

    private static func host(in input: [String: Any]) -> String? {
        (input["url"] as? String).flatMap { URL(string: $0)?.host() }
    }
}
