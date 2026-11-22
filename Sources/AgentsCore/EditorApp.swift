import AppKit

/// The code editor a finished agent's folder opens in (issue #65).
public struct EditorApp: Equatable, Sendable {
    public let name: String
    /// Nil in practice.
    public let url: URL?

    /// Editors that open a folder as a project, the usual ones first.
    static let editors: [String] = [
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.microsoft.VSCode",
        "com.exafunction.windsurf",
        "dev.zed.Zed",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.panic.Nova",
    ]

    /// Terminals that open a window in a folder dropped on them.
    static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    ]

    /// The first editor installed, nil when there's none.
    static func installed() -> EditorApp? {
        for bundleID in editors {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { continue }
            let name = FileManager.default.displayName(atPath: url.path)
            return EditorApp(name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name, url: url)
        }
        return nil
    }
}
