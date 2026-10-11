import AppKit
import HotKey
import Learn
import ModuleShelf
import SwiftUI

/// The app window (Home, Modules, Settings, About). It lives in the same process; the Dock icon
/// shows only while it's open, and the window is torn down on close to give its memory back
/// (ADR-0017). It is always dark, like the notch, whatever the system appearance.
@MainActor
final class AppWindowController: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private let shortcuts: ShortcutController
    private let stats: UsageStats
    private let shelfSettings: ShelfSettings
    private let shelfStore: ShelfStore
    private let progress: LearnProgress
    private var window: NSWindow?

    init(preferences: Preferences, shortcuts: ShortcutController, stats: UsageStats, shelfSettings: ShelfSettings, shelfStore: ShelfStore, progress: LearnProgress) {
        self.preferences = preferences
        self.shortcuts = shortcuts
        self.stats = stats
        self.shelfSettings = shelfSettings
        self.shelfStore = shelfStore
        self.progress = progress
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
            rootView: AppWindowView(
                preferences: preferences,
                shortcuts: shortcuts,
                stats: stats,
                shelfSettings: shelfSettings,
                shelfStore: shelfStore,
                progress: progress
            ),
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
    private static func makeWindow(rootView: some View, windowClass: NSWindow.Type, size: CGSize) -> NSWindow {
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
        // Closing the window during the welcome counts as having seen it: it shows once (ADR-0020).
        progress.onboardingDone = true
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
        let shelfSettings = ShelfSettings(defaults: defaults)
        let shelfFolder = FileManager.default.temporaryDirectory.appending(path: "PancakeNotch-snapshot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: shelfFolder) }
        let shelfStore = ShelfStore(directory: shelfFolder)
        let progress = LearnProgress(defaults: defaults)
        progress.onboardingDone = true
        shelfStore.add(
            [.text("Meeting notes"), .link(URL(string: "https://github.com")!), .text("Call back at 4"), .text("Address")],
            duplicates: .addAgain
        )

        func render(_ name: String, section: AppSection, lesson: LessonID = .basics, shortcuts: ShortcutController = noShortcut,
                    size: CGSize = AppWindowView.defaultSize) throws {
            try render(name, rootView: AppWindowView(
                preferences: preferences,
                shortcuts: shortcuts,
                stats: stats,
                shelfSettings: shelfSettings,
                shelfStore: shelfStore,
                progress: progress,
                section: section,
                lesson: lesson
            ), size: size)
        }

        /// `then` runs once the page has settled, before a second wait (e.g. to open an item).
        func render(_ name: String, rootView: some View, size: CGSize = AppWindowView.defaultSize, settle: TimeInterval = 0.3,
                    then: (() -> Void)? = nil) throws {
            let window = makeWindow(rootView: rootView, windowClass: SnapshotWindow.self, size: size)
            // The frame view also draws the traffic lights, so the image looks like the real window.
            guard let view = window.contentView?.superview ?? window.contentView else { return }
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(settle))
            if let then {
                then()
                RunLoop.main.run(until: Date().addingTimeInterval(settle))
            }
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("app-\(name).png"))
        }

        for section in AppSection.allCases {
            try render(section.rawValue, section: section)
        }
        try render("home-small", section: .home, size: AppWindowView.minimumSize)
        try render("learn-shelf", section: .learn, lesson: .shelf)

        // The welcome, one image per step, the way a first launch shows it.
        for step in OnboardingView.Step.allCases {
            try render("onboarding-\(step.rawValue + 1)", rootView: OnboardingView(
                preferences: preferences, shortcuts: noShortcut, stats: stats, progress: progress, step: step
            ).appWindowStyle())
        }

        // The practice Shelf working: open with the example items, then with one item opened.
        let practice = PracticeShelf(seeded: true)
        defer { practice.close() }
        let stage = NotchStage(behavior: preferences.notchBehavior, practice: practice, startState: .expanded)
            .background(AppPalette.background)
        try render("stage-open", rootView: stage.appWindowStyle(), size: CGSize(width: 900, height: 600), settle: 1.2)
        try render("stage-item", rootView: stage.appWindowStyle(), size: CGSize(width: 900, height: 600), settle: 1.2) {
            practice.openItem(at: 1)
        }

        progress.markDone(.basics)
        progress.markDone(.shelf)
        try render("home-learned", section: .home)
        progress.reset(.basics)
        progress.reset(.shelf)

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
