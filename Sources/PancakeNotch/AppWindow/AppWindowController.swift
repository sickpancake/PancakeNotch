import AppKit
import HotKey
import SwiftUI

/// The app window (Home, Modules, Settings, About). It lives in the same process; the Dock icon
/// shows only while it's open, and the window is torn down on close to give its memory back
/// (ADR-0017). It is always dark, like the notch, whatever the system appearance.
@MainActor
final class AppWindowController: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private let shortcuts: ShortcutController
    private let stats: UsageStats
    private var window: NSWindow?

    init(preferences: Preferences, shortcuts: ShortcutController, stats: UsageStats) {
        self.preferences = preferences
        self.shortcuts = shortcuts
        self.stats = stats
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = Self.makeWindow(
            rootView: AppWindowView(preferences: preferences, shortcuts: shortcuts, stats: stats),
            windowClass: NSWindow.self,
            size: AppWindowView.defaultSize
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("AppWindow")
        return window
    }

    /// A dark window whose sidebar runs up under the traffic lights, with no visible title bar.
    private static func makeWindow(rootView: AppWindowView, windowClass: NSWindow.Type, size: CGSize) -> NSWindow {
        let window = windowClass.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "PancakeNotch") // still used by the Window menu and VoiceOver
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.contentMinSize = AppWindowView.minimumSize
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = [.minSize]
        window.contentView = hostingView
        window.setContentSize(size)
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Release after AppKit finishes closing, so the SwiftUI view tree is freed.
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentView = nil
            self?.window = nil
        }
    }
}

extension AppWindowController {
    /// Renders every page off-screen to `<directory>/app-<page>.png` without showing anything
    /// (design checks; `PANCAKENOTCH_SNAPSHOT_SETTINGS=<directory>`). Uses sample preferences and
    /// numbers kept in a throwaway defaults domain, never the user's real settings.
    static func writeSnapshots(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "io.github.sickpancake.PancakeNotch.snapshots"
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = Preferences(defaults: defaults)
        let stats = sampleStats(defaults: defaults)
        let noShortcut = ShortcutController(defaults: defaults) {}

        func render(_ name: String, section: AppSection, shortcuts: ShortcutController = noShortcut,
                    size: CGSize = AppWindowView.defaultSize) throws {
            let window = makeWindow(
                rootView: AppWindowView(preferences: preferences, shortcuts: shortcuts, stats: stats, section: section),
                windowClass: SnapshotWindow.self,
                size: size
            )
            // The frame view also draws the traffic lights, so the image looks like the real window.
            guard let view = window.contentView?.superview ?? window.contentView else { return }
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("app-\(name).png"))
        }

        for section in AppSection.allCases {
            try render(section.rawValue, section: section)
        }
        try render("home-small", section: .home, size: AppWindowView.minimumSize)

        preferences.notchEnabled = false
        try render("home-off", section: .home)
        preferences.notchEnabled = true

        // A saved shortcut, so Home shows key caps. Registering it may fail if it's taken; the
        // key caps still show.
        if let hotKey = HotKey(keyCode: 45, modifiers: [.option, .command], keyLabel: "N"),
           let data = try? JSONEncoder().encode(hotKey) {
            let shortcutDefaults = UserDefaults(suiteName: suite + ".shortcut")
            shortcutDefaults?.set(data, forKey: "toggleNotchShortcut")
            defer { shortcutDefaults?.removePersistentDomain(forName: suite + ".shortcut") }
            if let shortcutDefaults {
                let withShortcut = ShortcutController(defaults: shortcutDefaults) {}
                try render("home-shortcut", section: .home, shortcuts: withShortcut)
                try render("keyboard-shortcut", section: .keyboard, shortcuts: withShortcut)
            }
        }
    }

    /// Stats as if PancakeNotch had been around for a week and a bit.
    private static func sampleStats(defaults: UserDefaults) -> UsageStats {
        var clock = Date().addingTimeInterval(-8 * 86_400)
        let stats = UsageStats(defaults: defaults) { clock }
        clock = Date().addingTimeInterval(-86_400)
        for _ in 0..<336 { stats.recordOpen() }
        clock = Date()
        for _ in 0..<12 { stats.recordOpen() }
        return stats
    }
}

/// Draws as if it were the focused window, so snapshots show controls in their active colours.
private final class SnapshotWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}
