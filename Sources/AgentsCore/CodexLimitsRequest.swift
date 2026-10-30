import Foundation
import Security
import os

/// Asks Codex itself for an account's current limits, so AI Usage is up to date without a new prompt
/// (ADR-0037, amended 2026-10-22). It starts `codex app-server` for a moment and sends one
/// `account/rateLimits/read` request: Codex checks with OpenAI using its own sign-in, and PancakeNotch
/// never sees a token. Blocking, so it runs on a background queue, and only when AI Usage is opened.
enum CodexLimitsRequest {
    /// How long Codex gets to answer before it's stopped.
    static let timeout: TimeInterval = 15

    static func read(folder: URL, home: URL) -> CodexRateLimits? {
        guard let binary = binary(home: home) else { return nil }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["app-server"]
        // A clean environment: only what Codex needs to find its folder.
        var environment = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        if folder.standardizedFileURL.path != home.appending(path: ".codex").standardizedFileURL.path {
            environment["CODEX_HOME"] = folder.path
        }
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"pancakenotch","title":"PancakeNotch","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","method":"initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read"}"#,
        ]
        try? input.fileHandleForWriting.write(contentsOf: Data((requests.joined(separator: "\n") + "\n").utf8))
        // Stopping Codex ends its output, which ends the reading below.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak process] in
            if process?.isRunning == true { process?.terminate() }
        }
        var buffer = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
            // The answer is a few KB: a far longer line isn't it.
            if buffer.count > 4 * 1024 * 1024 { return nil }
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      (object["id"] as? NSNumber)?.intValue == 2 else { continue }
                return (object["result"] as? [String: Any]).flatMap(limits)
            }
        }
    }

    /// The answer's `rateLimits` (Codex's own limit, "codex", when it lists several), in the rollouts' shape.
    static func limits(_ result: [String: Any]) -> CodexRateLimits? {
        let byID = result["rateLimitsByLimitId"] as? [String: Any]
        guard let limits = byID?["codex"] as? [String: Any] ?? result["rateLimits"] as? [String: Any] else { return nil }
        func window(_ key: String) -> [String: Any]? {
            guard let value = limits[key] as? [String: Any] else { return nil }
            return ["used_percent": value["usedPercent"] as Any, "window_minutes": value["windowDurationMins"] as Any,
                    "resets_at": value["resetsAt"] as Any]
        }
        var converted: [String: Any] = [:]
        converted["primary"] = window("primary")
        converted["secondary"] = window("secondary")
        converted["plan_type"] = limits["planType"]
        return CodexRateLimits(converted, at: .now)
    }

    /// Codex's own program: a command-line install first (the version the person uses), then the one inside
    /// the Codex or ChatGPT app. Only real programs count: npm's `codex` is a script that needs Node.
    static func binary(home: URL) -> URL? {
        let npmPackage = "lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"
        let nvm = home.appending(path: ".nvm/versions/node")
        let nodeVersions = ((try? FileManager.default.contentsOfDirectory(atPath: nvm.path)) ?? [])
            .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            .map { nvm.appending(path: $0).path }
        let prefixes = ["/opt/homebrew", "/usr/local", home.appending(path: ".npm-global").path, home.appending(path: ".local").path] + nodeVersions
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", home.appending(path: ".local/bin/codex").path,
                          home.appending(path: ".cargo/bin/codex").path]
            + prefixes.map { "\($0)/\(npmPackage)" }
            + ["/Applications/Codex.app/Contents/Resources/codex",
               "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"]
        // Only OpenAI's own: a program someone put in one of these (mostly user-writable) places never runs
        // as PancakeNotch's child. A Codex built elsewhere still shows its limits from its files.
        return candidates.lazy.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
            .first { isProgram($0) && isSignedByOpenAI($0) }
    }

    /// OpenAI's Developer ID team.
    static let openAITeam = "2DC432GLL2"
    private static let checked = OSAllocatedUnfairLock(initialState: [String: (stamp: [Int], signed: Bool)]())

    /// Signed with OpenAI's Developer ID and unchanged since. Checked once per version of the file (it's
    /// large), and again whenever it changes.
    static func isSignedByOpenAI(_ url: URL, team: String = openAITeam) -> Bool {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return false }
        let stamp = [Int(info.st_dev), Int(info.st_ino), Int(info.st_size), info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec, Int(info.st_ctimespec.tv_sec)]
        let key = url.path + "|" + team
        if let known = checked.withLock({ $0[key] }), known.stamp == stamp { return known.signed }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" as CFString
        let signed = SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess
            && SecRequirementCreateWithString(text, [], &requirement) == errSecSuccess
            && code.map { SecStaticCodeCheckValidity($0, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess } == true
        checked.withLock { $0[key] = (stamp, signed) }
        return signed
    }

    /// An arm64 or universal Mach-O file that can be run.
    private static func isProgram(_ url: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let magic = (try? handle.read(upToCount: 4)).map { [UInt8]($0) } ?? []
        return magic == [0xCF, 0xFA, 0xED, 0xFE] || magic == [0xCA, 0xFE, 0xBA, 0xBE]
    }
}
