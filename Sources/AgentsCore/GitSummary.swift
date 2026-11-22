import Foundation

/// What a local agent changed in its project folder during its last stretch of work (issue #65): the
/// branch, how many files and lines changed, and the last commit it made, if any.
public struct DoneSummary: Equatable, Sendable {
    public var branch: String?
    public var filesChanged: Int
    public var insertions: Int
    public var deletions: Int
    /// The subject of the last commit made during the work.
    public var lastCommit: String?

    public init(branch: String? = nil, filesChanged: Int, insertions: Int, deletions: Int, lastCommit: String? = nil) {
        self.branch = branch
        self.filesChanged = filesChanged
        self.insertions = insertions
        self.deletions = deletions
        self.lastCommit = lastCommit
    }

    public var hasChanges: Bool { filesChanged > 0 || insertions > 0 || deletions > 0 }
}

/// Reads a `DoneSummary` with local `git`: once when a turn starts (a snapshot of the folder) and once
/// when it ends. Event-driven, never on a timer, no network; each run has a short time limit.
enum GitSummary {
    /// `git` from the Command Line Tools, Xcode or Homebrew. Never `/usr/bin/git`: without the tools it
    /// asks to install them.
    nonisolated(unsafe) static var executable: URL? = [
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
    ].lazy.map { URL(fileURLWithPath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }

    static let timeout: TimeInterval = 2

    /// The folder as a stretch of work begins: the commit HEAD is on, and a tree of every file in it then
    /// (uncommitted edits and new files not ignored included), so only what changes after counts.
    struct Start: Equatable, Sendable {
        var commit: String?
        var tree: String?
    }

    /// Where the folder is now, or nil outside a repository.
    static func start(cwd: String) async -> Start? {
        await Task.detached(priority: .utility) {
            guard insideWorkTree(cwd) else { return nil }
            let start = Start(commit: line(["rev-parse", "--verify", "-q", "HEAD"], cwd: cwd), tree: snapshot(cwd: cwd))
            return start.commit == nil && start.tree == nil ? nil : start
        }.value
    }

    /// What changed since `start`: commits, edits and new files not ignored. Not knowing the start, it
    /// counts from HEAD. Nil outside a repository.
    static func summary(cwd: String, since start: Start?, branch: String?) async -> DoneSummary? {
        await Task.detached(priority: .utility) {
            guard insideWorkTree(cwd), let now = snapshot(cwd: cwd) else { return nil }
            let base = start?.tree ?? start?.commit ?? line(["rev-parse", "--verify", "-q", "HEAD^{tree}"], cwd: cwd) ?? emptyTree
            var summary = parseShortstat(run(["diff", "--shortstat", base, now, "--"], cwd: cwd) ?? "")
            summary.branch = branch
            if let commit = start?.commit {
                summary.lastCommit = line(["log", "-1", "--format=%s", "\(commit)..HEAD", "--"], cwd: cwd)
            }
            return summary
        }.value
    }

    /// The tree object of the folder as it is, tracked and new files alike, written through a copy of
    /// the index so the user's own index, stash and refs stay untouched.
    private static func snapshot(cwd: String) -> String? {
        guard let indexPath = line(["rev-parse", "--path-format=absolute", "--git-path", "index"], cwd: cwd) else { return nil }
        let index = FileManager.default.temporaryDirectory.appending(path: "PancakeNotch-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: index) }
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: indexPath), to: index)
        let environment = ["GIT_INDEX_FILE": index.path]
        guard run(["add", "-A"], cwd: cwd, environment: environment) != nil else { return nil }
        return line(["write-tree"], cwd: cwd, environment: environment)
    }

    private static let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    private static func insideWorkTree(_ cwd: String) -> Bool {
        run(["rev-parse", "--is-inside-work-tree"], cwd: cwd)?.hasPrefix("true") == true
    }

    private static func line(_ arguments: [String], cwd: String, environment: [String: String] = [:]) -> String? {
        run(arguments, cwd: cwd, environment: environment)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// " 3 files changed, 42 insertions(+), 7 deletions(-)" (either count may be missing; empty: nothing).
    static func parseShortstat(_ text: String) -> DoneSummary {
        var summary = DoneSummary(filesChanged: 0, insertions: 0, deletions: 0)
        for part in text.split(separator: ",") {
            let words = part.split(separator: " ")
            guard let count = words.first.flatMap({ Int($0) }), words.count > 1 else { continue }
            if words[1].hasPrefix("file") { summary.filesChanged = count }
            else if words[1].hasPrefix("insertion") { summary.insertions = count }
            else if words[1].hasPrefix("deletion") { summary.deletions = count }
        }
        return summary
    }

    /// Runs git in `cwd`, nil when it fails or takes longer than `timeout`.
    private static func run(_ arguments: [String], cwd: String, environment extra: [String: String] = [:]) -> String? {
        guard let executable, cwd.hasPrefix("/"), FileManager.default.fileExists(atPath: cwd) else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--no-pager", "-c", "core.quotepath=off"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var environment = ProcessInfo.processInfo.environment
        // Don't take the index lock the agent or the user's own git may need.
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment.merge(extra) { $1 }
        process.environment = environment
        // A file, not a pipe: a process started elsewhere at the same moment can inherit a pipe and keep it
        // open after git exits, so a read to its end could wait forever.
        let outputURL = FileManager.default.temporaryDirectory.appending(path: "PancakeNotch-git-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputURL) else { return nil }
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0,
              let reader = try? FileHandle(forReadingFrom: outputURL),
              let data = try? reader.read(upToCount: 1 << 20) ?? Data() else { return nil }
        try? reader.close()
        return String(data: data, encoding: .utf8)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
