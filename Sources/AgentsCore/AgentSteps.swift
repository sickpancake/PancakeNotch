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

    /// Whether `request` shows everything an answer would approve, so the notch may offer Allow: a
    /// one-line command short enough to show whole, or one file inside the project. Anything else (a cut
    /// or multi-line command, a file elsewhere, several files, a web address, another tool's arguments) is
    /// answered in the tool's own window, where it's shown in full.
    static func isFullyShown(tool name: String, input: [String: Any], cwd: String?) -> Bool {
        switch kind(of: name) {
        case .run:
            guard let text = commandText(in: input)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return !text.isEmpty && !text.contains(where: \.isNewline) && text.count <= commandLimit
        case .edit, .read:
            guard let cwd, !cwd.isEmpty, let path = singleFilePath(in: input) else { return false }
            // Whole paths on both sides: a relative URL resolves differently across macOS versions.
            let folder = URL(fileURLWithPath: cwd, isDirectory: true)
            let project = folder.standardizedFileURL.resolvingSymlinksInPath()
            let given = path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appending(path: path)
            let file = given.standardizedFileURL.resolvingSymlinksInPath()
            return file.path.hasPrefix(project.path + "/")
        case .search, .web, .agent, .plan, .other:
            return false
        }
    }

    private static let commandLimit = 60

    private static func commandText(in input: [String: Any]) -> String? {
        let value = input["command"] ?? input["cmd"]
        return (value as? String) ?? (value as? [String]).map { $0.joined(separator: " ") }
    }

    /// The one file a call touches, as given; nil for none or several.
    private static func singleFilePath(in input: [String: Any]) -> String? {
        for key in ["file_path", "path", "notebook_path", "filename", "target_file"] {
            if let path = input[key] as? String, !path.isEmpty { return path }
        }
        guard let patch = (input["command"] as? String) ?? (input["input"] as? String) ?? (input["patch"] as? String) else { return nil }
        let paths = patch.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            ["*** Update File: ", "*** Add File: ", "*** Delete File: ", "*** Move to: "].lazy
                .compactMap { line.hasPrefix($0) ? String(line.dropFirst($0.count)) : nil }.first
        }
        return paths.count == 1 ? paths[0] : nil
    }

    /// The start of the command: its first line, cut at 60 characters.
    static func command(in input: [String: Any]) -> String? {
        let text = commandText(in: input)
        guard let line = text?.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces), !line.isEmpty else { return nil }
        // An `apply_patch` "command" is the patch itself.
        if line.hasPrefix("*** Begin Patch") { return nil }
        return line.count > commandLimit ? String(line.prefix(commandLimit - 1)) + "…" : line
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
