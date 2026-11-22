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

/// Reads a `DoneSummary` with local `git`: once when a turn starts (where HEAD was) and once when it
/// ends. Event-driven, never on a timer, no network; each run has a short time limit.
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

    /// The commit HEAD points at, or nil outside a repository.
    static func head(cwd: String) async -> String? {
        await Task.detached(priority: .utility) {
            run(["rev-parse", "--verify", "-q", "HEAD"], cwd: cwd)?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }.value
    }

    /// What changed since `start` (the commit HEAD was on when the work began; HEAD when unknown): commits
    /// and uncommitted changes to tracked files, plus new files not ignored. Nil outside a repository.
    static func summary(cwd: String, since start: String?, branch: String?) async -> DoneSummary? {
        await Task.detached(priority: .utility) {
            guard run(["rev-parse", "--is-inside-work-tree"], cwd: cwd)?.hasPrefix("true") == true else { return nil }
            let base = start ?? "HEAD"
            var summary = parseShortstat(run(["diff", "--shortstat", base, "--"], cwd: cwd) ?? "")
            summary.branch = branch
            let untracked = run(["ls-files", "--others", "--exclude-standard", "-z"], cwd: cwd) ?? ""
            summary.filesChanged += untracked.split(separator: "\0").count
            if let start {
                summary.lastCommit = run(["log", "-1", "--format=%s", "\(start)..HEAD", "--"], cwd: cwd)?
                    .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            return summary
        }.value
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
    private static func run(_ arguments: [String], cwd: String) -> String? {
        guard let executable, cwd.hasPrefix("/"), FileManager.default.fileExists(atPath: cwd) else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--no-pager", "-c", "core.quotepath=off"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var environment = ProcessInfo.processInfo.environment
        // Don't take the index lock the agent or the user's own git may need.
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        // Read while it runs so a full pipe can't stall it; at most 1 MB.
        let reader = OutputReader(output.fileHandleForReading)
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        let data = reader.wait()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Reads a pipe to its end on another thread.
private final class OutputReader: @unchecked Sendable {
    private var data = Data()
    private let done = DispatchSemaphore(value: 0)

    init(_ handle: FileHandle) {
        DispatchQueue.global(qos: .utility).async { [self] in
            data = (try? handle.read(upToCount: 1 << 20)) ?? Data()
            done.signal()
        }
    }

    func wait() -> Data {
        done.wait()
        return data
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
