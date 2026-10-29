import Darwin
import Foundation

/// Exactly what Allow would approve, shown whole in the notch before Allow is offered (ADR-0037,
/// 2026-10-28 amendment): a command or a file to read, in full in the thread's row, or one file's change
/// on the review screen. A request with no review (too big to show at once, more than one file, characters
/// that could hide or disguise text, an argument list, another tool) is answered in the tool's own window.
/// Held only while its request waits: never logged or saved.
public struct AgentReview: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        /// A command, on its own lines (wrapped at `columns`).
        case command(lines: [String])
        /// A file inside the project to read, by its place in the project (wrapped at `columns`).
        case read(lines: [String])
        /// One file's change.
        case edit(FileChange)
    }

    public struct FileChange: Equatable, Sendable {
        public enum Action: Equatable, Sendable {
            /// Some of its text changes (shown as removed and added lines).
            case change
            /// A new file, all of it shown.
            case create
            /// The whole file is replaced by what's shown.
            case replace
            case delete
        }

        public enum Warning: Equatable, Sendable {
            case outsideProject
            /// Settings, hooks, scripts or agent instructions: a change here can run code or change what
            /// tools do later.
            case runsCode
        }

        public struct Line: Equatable, Sendable {
            public enum Kind: Equatable, Sendable { case removed, added, context, gap }
            public let kind: Kind
            /// One screen line: wrapped at `columns`, tabs as spaces, trailing spaces as "·".
            public let text: String
        }

        /// Where the file really is (links followed): from the project folder, else from home ("~/…").
        /// Wrapped at `columns`.
        public let path: [String]
        public let action: Action
        public let warning: Warning?
        /// The change replaces every match in the file, not just the first.
        public let everyMatch: Bool
        public let lines: [Line]
    }

    public let content: Content

    /// Screen lines are cut at this many columns (a non-ASCII character counts as two).
    public static let columns = 72
    /// Most lines a command or a file to read may take in a row.
    public static let rowLines = 3
    /// Most lines of change the review screen shows, and of a file's location.
    public static let changeLines = 10
    public static let pathLines = 2
    /// Longer inputs aren't even looked at: they can't fit.
    private static let maxInput = 8 * 1024

    /// The review for a permission request, or nil when it can't be shown whole.
    static func make(tool name: String, input: [String: Any], cwd: String?, home: String) -> AgentReview? {
        switch name {
        case "Bash", "shell", "exec_command", "local_shell", "Shell", "run_terminal_cmd", "PowerShell":
            // An argument list is joined differently by each tool: answered there.
            guard let text = (input["command"] ?? input["cmd"]) as? String else { return nil }
            return command(text)
        case "Read", "read_file":
            guard let place = place(of: input, cwd: cwd, home: home), place.inside,
                  let lines = wrapped([place.shown], plain: false), lines.count <= rowLines else { return nil }
            return AgentReview(content: .read(lines: lines))
        case "Edit", "MultiEdit", "Write":
            return edit(name, input: input, cwd: cwd, home: home)
        case "apply_patch":
            guard let patch = (input["input"] ?? input["patch"] ?? input["command"]) as? String else { return nil }
            return applyPatch(patch, cwd: cwd, home: home)
        default:
            return nil
        }
    }

    // MARK: Commands

    private static func command(_ text: String) -> AgentReview? {
        guard text.utf8.count <= maxInput else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Plain printable ASCII and line breaks only: nothing that could look like something else.
        guard !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy({ $0 == "\n" || (0x20...0x7E).contains($0.value) }),
              !trimmed.hasPrefix("*** Begin Patch"),
              let lines = wrapped(trimmed.components(separatedBy: "\n"), plain: true), lines.count <= rowLines else { return nil }
        return AgentReview(content: .command(lines: lines))
    }

    // MARK: Edits

    private static func edit(_ name: String, input: [String: Any], cwd: String?, home: String) -> AgentReview? {
        guard let place = place(of: input, cwd: cwd, home: home) else { return nil }
        var lines: [FileChange.Line] = []
        var action = FileChange.Action.change
        var everyMatch = false
        switch name {
        case "Write":
            guard let content = input["content"] as? String, content.utf8.count <= maxInput,
                  let added = textLines(content, droppingFinalBreak: true) else { return nil }
            action = place.exists ? .replace : .create
            lines = added.map { FileChange.Line(kind: .added, text: $0) }
        case "Edit":
            guard let block = change(input) else { return nil }
            lines = block.lines
            everyMatch = block.everyMatch
        default: // MultiEdit: every change, one after another.
            guard let edits = input["edits"] as? [[String: Any]], !edits.isEmpty, edits.count <= changeLines else { return nil }
            for (index, edit) in edits.enumerated() {
                guard let block = change(edit) else { return nil }
                if index > 0 { lines.append(FileChange.Line(kind: .gap, text: "")) }
                lines += block.lines
                everyMatch = everyMatch || block.everyMatch
            }
        }
        return review(place, action: action, everyMatch: everyMatch, lines: lines)
    }

    /// One `old_string` → `new_string` change: the lines both share at the start and end once, as context,
    /// then what's removed and what's added.
    private static func change(_ edit: [String: Any]) -> (lines: [FileChange.Line], everyMatch: Bool)? {
        guard let old = edit["old_string"] as? String, let new = edit["new_string"] as? String, old != new,
              old.utf8.count + new.utf8.count <= maxInput,
              let before = textLines(old, droppingFinalBreak: false), let after = textLines(new, droppingFinalBreak: false) else { return nil }
        var start = 0
        while start < before.count, start < after.count, before[start] == after[start] { start += 1 }
        var end = 0
        while end < before.count - start, end < after.count - start, before[before.count - 1 - end] == after[after.count - 1 - end] { end += 1 }
        var lines = before[..<start].map { FileChange.Line(kind: .context, text: $0) }
        lines += before[start..<(before.count - end)].map { FileChange.Line(kind: .removed, text: $0) }
        lines += after[start..<(after.count - end)].map { FileChange.Line(kind: .added, text: $0) }
        lines += before[(before.count - end)...].map { FileChange.Line(kind: .context, text: $0) }
        return (lines, edit["replace_all"] as? Bool == true)
    }

    /// Codex's patch format, for exactly one file it adds, changes or deletes (not moves). Codex reads
    /// markers on trimmed lines, so an indented marker that would start another file isn't accepted.
    private static func applyPatch(_ patch: String, cwd: String?, home: String) -> AgentReview? {
        guard patch.utf8.count <= maxInput, !patch.contains("\r") else { return nil }
        var rows = patch.components(separatedBy: "\n")
        while rows.last?.isEmpty == true { rows.removeLast() }
        guard rows.count >= 3, rows.first == "*** Begin Patch", rows.last == "*** End Patch" else { return nil }
        let body = rows.dropFirst().dropLast()
        guard let header = body.first else { return nil }
        let operations: [(String, FileChange.Action)] = [("*** Add File: ", .create), ("*** Update File: ", .change), ("*** Delete File: ", .delete)]
        guard let (marker, action) = operations.first(where: { header.hasPrefix($0.0) }) else { return nil }
        let path = String(header.dropFirst(marker.count))
        guard let place = place(of: ["file_path": path], cwd: cwd, home: home) else { return nil }
        var lines: [FileChange.Line] = []
        for row in body.dropFirst() {
            if row.trimmingCharacters(in: .whitespaces).hasPrefix("***") {
                guard action == .change, row == "*** End of File" else { return nil }
                continue
            }
            switch (action, row.first) {
            case (.create, "+"): lines.append(FileChange.Line(kind: .added, text: String(row.dropFirst())))
            case (.change, "+"): lines.append(FileChange.Line(kind: .added, text: String(row.dropFirst())))
            case (.change, "-"): lines.append(FileChange.Line(kind: .removed, text: String(row.dropFirst())))
            case (.change, " "): lines.append(FileChange.Line(kind: .context, text: String(row.dropFirst())))
            case (.change, nil): lines.append(FileChange.Line(kind: .context, text: ""))
            case (.change, "@"):
                guard row.hasPrefix("@@") else { return nil }
                if !lines.isEmpty { lines.append(FileChange.Line(kind: .gap, text: "")) }
                let anchor = row.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !anchor.isEmpty { lines.append(FileChange.Line(kind: .context, text: anchor)) }
            default: return nil
            }
        }
        // A changed or added line's text is checked like any other text.
        for line in lines where !isPlain(line.text) { return nil }
        if action == .create, place.exists { return nil }
        return review(place, action: action, everyMatch: false, lines: lines)
    }

    private static func review(_ place: Place, action: FileChange.Action, everyMatch: Bool, lines: [FileChange.Line]) -> AgentReview? {
        guard action == .delete || !lines.isEmpty,
              let path = wrapped([place.shown], plain: false), path.count <= pathLines else { return nil }
        var shown: [FileChange.Line] = []
        for line in lines {
            guard let parts = wrapped([line.text], plain: false) else { return nil }
            shown += parts.map { FileChange.Line(kind: line.kind, text: $0) }
            if shown.count > changeLines { return nil }
        }
        let warning: FileChange.Warning? = !place.inside ? .outsideProject : runsCode(place.shown) ? .runsCode : nil
        return AgentReview(content: .edit(FileChange(path: path, action: action, warning: warning, everyMatch: everyMatch, lines: shown)))
    }

    /// Folders and files whose contents run code or steer tools later.
    private static let codeFolders: Set<String> = [".git", ".github", ".claude", ".codex", ".cursor", ".vscode", ".idea", ".husky", ".devcontainer"]
    private static let codeFiles: Set<String> = [
        "package.json", "Package.swift", "Makefile", "makefile", "GNUmakefile", "build.rs", "setup.py", "pyproject.toml",
        ".envrc", ".npmrc", ".yarnrc", ".yarnrc.yml", ".gitattributes", ".gitmodules", ".zshrc", ".zprofile", ".bashrc",
        ".bash_profile", ".profile", "AGENTS.md", "CLAUDE.md", "GEMINI.md", ".cursorrules",
    ]

    static func runsCode(_ shown: String) -> Bool {
        let parts = shown.split(separator: "/").map(String.init)
        guard let name = parts.last else { return false }
        return parts.dropLast().contains(where: codeFolders.contains) || codeFiles.contains(name)
    }

    // MARK: Paths

    struct Place {
        /// From the project ("Sources/App.swift"), else from home ("~/.zshrc"), else in full.
        let shown: String
        let inside: Bool
        let exists: Bool
    }

    /// Where a request's one file really is: links followed all the way, including a link in a folder of
    /// a file that doesn't exist yet. A broken link or a ".." climb has no place: it could end anywhere.
    static func place(of input: [String: Any], cwd: String?, home: String) -> Place? {
        guard let cwd, cwd.hasPrefix("/"), let project = realPath(cwd),
              let given = ["file_path", "path", "notebook_path", "filename", "target_file"].lazy.compactMap({ input[$0] as? String }).first,
              !given.isEmpty, isPlain(given), !given.contains("\n") else { return nil }
        let full = given.hasPrefix("/") ? given : cwd + "/" + given
        var parts = full.split(separator: "/").map(String.init).filter { $0 != "." }
        guard !parts.contains("..") else { return nil }
        // Climb to the deepest part that exists; what's under it is new, so it can't be a link.
        var missing: [String] = []
        var resolved: String?
        while resolved == nil {
            let path = "/" + parts.joined(separator: "/")
            var info = stat()
            if lstat(path, &info) == 0 {
                guard let real = realPath(path) else { return nil }
                resolved = real
            } else {
                guard errno == ENOENT, let last = parts.popLast() else { return nil }
                missing.insert(last, at: 0)
            }
        }
        guard let base = resolved else { return nil }
        let path = ([base == "/" ? "" : base] + missing).joined(separator: "/")
        var info = stat()
        let exists = missing.isEmpty && lstat(path, &info) == 0
        if exists, (info.st_mode & S_IFMT) == S_IFDIR { return nil }
        if path.hasPrefix(project + "/") {
            return Place(shown: String(path.dropFirst(project.count + 1)), inside: true, exists: exists)
        }
        if let home = realPath(home), path.hasPrefix(home + "/") {
            return Place(shown: "~/" + path.dropFirst(home.count + 1), inside: false, exists: exists)
        }
        return Place(shown: path, inside: false, exists: exists)
    }

    private static func realPath(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    // MARK: Text

    /// A text's lines, or nil if any character could hide or disguise text. Windows line endings count as
    /// plain ones.
    private static func textLines(_ text: String, droppingFinalBreak: Bool) -> [String]? {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard isPlain(unified) else { return nil }
        var lines = unified.components(separatedBy: "\n")
        if droppingFinalBreak, lines.count > 1, lines.last == "" { lines.removeLast() }
        return lines
    }

    /// No control characters (but tabs and line breaks), nothing invisible, no right-to-left overrides,
    /// no lookalike spaces.
    static func isPlain(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            if scalar == "\n" || scalar == "\t" || scalar == " " { return true }
            if scalar.isASCII { return (0x21...0x7E).contains(scalar.value) }
            let properties = scalar.properties
            switch properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned, .surrogate, .spaceSeparator:
                return false
            default:
                return !properties.isDefaultIgnorableCodePoint && !properties.isWhitespace
            }
        }
    }

    /// Lines cut at `columns`, tabs as four spaces, trailing spaces made visible (except in `plain`
    /// commands, where they change nothing). Nil if anything isn't plain.
    private static func wrapped(_ lines: [String], plain: Bool) -> [String]? {
        var result: [String] = []
        for line in lines {
            guard isPlain(line), !line.contains("\n") else { return nil }
            var text = line.replacingOccurrences(of: "\t", with: "    ")
            if !plain {
                let kept = text.reversed().drop { $0 == " " }.count
                text = String(text.prefix(kept)) + String(repeating: "·", count: text.count - kept)
            }
            var current = "", width = 0
            for character in text {
                let size = character.unicodeScalars.reduce(0) { $0 + ($1.isASCII ? 1 : 2) }
                if width + size > columns, !current.isEmpty {
                    result.append(current)
                    current = ""
                    width = 0
                }
                current.append(character)
                width += size
            }
            result.append(current)
            if result.count > changeLines + pathLines { return nil }
        }
        return result
    }
}

/// A permission request waiting for Allow / Deny in the notch: what it asks, fixed when it arrived. Later
/// events can't change it; Allow and Deny answer exactly this request, or nothing.
public struct PendingApproval: Equatable, Sendable {
    let requestID: Int
    public let review: AgentReview

    init(requestID: Int, review: AgentReview) {
        self.requestID = requestID
        self.review = review
    }
}
