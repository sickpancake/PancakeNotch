import Foundation

/// Runs a coding service's own command-line tool for a moment (issue #55): `codex cloud list` for Codex
/// cloud, `gh agent-task list` and `gh pr checks` for GitHub. Each tool uses its own sign-in, so
/// PancakeNotch never sees a token. Blocking, so it runs on a background queue.
enum CloudCommand {
    /// How long a tool gets to answer before it's stopped.
    static let timeout: TimeInterval = 20

    /// What a run gives back: its exit status and what it printed.
    struct Output: Equatable, Sendable {
        var status: Int32
        var data: Data
    }

    enum Program: String, Sendable {
        case gh, codex
    }

    /// Runs `program` with `arguments`; nil when the program isn't installed or couldn't start.
    typealias Run = @Sendable (Program, [String]) async -> Output?

    static let live: Run = { program, arguments in
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: run(program, arguments))
            }
        }
    }

    private static func run(_ program: Program, _ arguments: [String]) -> Output? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let binary = binary(program, home: home) else { return nil }
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        // A clean environment: only what the tool needs to find its sign-in.
        process.environment = ["HOME": home.path, "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                               "GH_PROMPT_DISABLED": "1", "NO_COLOR": "1", "GH_NO_UPDATE_NOTIFIER": "1"]
        let output = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak process] in
            if process?.isRunning == true { process?.terminate() }
        }
        var data = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            // The answers are a few KB: far more isn't one.
            if data.count > 4 * 1024 * 1024 { process.terminate(); break }
        }
        process.waitUntilExit()
        return Output(status: process.terminationStatus, data: data)
    }

    /// The tool's program: Homebrew's, then a manual install; Codex also from inside its app.
    static func binary(_ program: Program, home: URL) -> URL? {
        switch program {
        case .codex:
            return CodexLimitsRequest.binary(home: home)
        case .gh:
            let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", home.appending(path: ".local/bin/gh").path]
            return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        }
    }
}
