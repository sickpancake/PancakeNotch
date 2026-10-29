import Foundation

/// Where the hook helper (`pancakenotch-hook`, Sources/AgentHook) lives and how it talks to the app.
///
/// Connect copies it out of the app to Application Support, so the tools' hook settings keep working
/// when the app moves, and a helper left behind by a deleted app just steps aside (it finds no socket).
enum HookHelper {
    /// Every hook entry PancakeNotch adds contains this; Disconnect removes exactly those.
    static let marker = "pancakenotch-hook"
    /// How long a tool waits for Allow / Deny before asking in its own window (seconds).
    static let answerTimeout = 600

    static var supportFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "PancakeNotch", directoryHint: .isDirectory)
    }

    static var installedURL: URL { supportFolder.appending(path: "bin/pancakenotch-hook") }

    /// The socket the helper writes to. The helper finds it the same way (`$HOME/Library/Application
    /// Support/PancakeNotch/agents.sock`); in testing builds `PANCAKENOTCH_AGENTS_SOCKET` moves both.
    static var socketPath: String {
        #if PANCAKENOTCH_INTERNAL_TESTING
        if let path = ProcessInfo.processInfo.environment["PANCAKENOTCH_AGENTS_SOCKET"] { return path }
        #endif
        return supportFolder.appending(path: "agents.sock").path
    }

    /// The helper shipped with this app: in the bundle (Contents/MacOS), or beside the executable when
    /// running from `.build`.
    static var bundledURL: URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: marker) { return url }
        let beside = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: marker)
        return beside.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
    }

    /// Copies the bundled helper into place when it's missing or different. Returns whether a working
    /// helper is installed.
    static func install() -> Bool {
        let fm = FileManager.default
        guard let source = bundledURL else { return fm.isExecutableFile(atPath: installedURL.path) }
        if let installed = try? Data(contentsOf: installedURL), let bundled = try? Data(contentsOf: source), installed == bundled {
            return true
        }
        do {
            try fm.createDirectory(at: installedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = installedURL.appendingPathExtension("new")
            try? fm.removeItem(at: temporary)
            try fm.copyItem(at: source, to: temporary)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
            // A downloaded app's files carry the download mark; the tools run this copy from Terminal,
            // where that mark would stop it with a warning the person can't see.
            removexattr(temporary.path, "com.apple.quarantine", 0)
            _ = try fm.replaceItemAt(installedURL, withItemAt: temporary)
            return true
        } catch {
            return fm.isExecutableFile(atPath: installedURL.path)
        }
    }
}
