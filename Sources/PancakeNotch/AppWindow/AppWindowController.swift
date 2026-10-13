import AppKit
import HotKey
import Learn
import ModuleNowPlaying
import ModuleShelf
import NotchCore
import NowPlayingCore
import Stats
import SwiftUI

/// The app window (Home, Modules, Settings, About). It lives in the same process; the Dock icon
/// shows only while it's open, and the window is torn down on close to give its memory back
/// (ADR-0017). It is always dark, like the notch, whatever the system appearance.
@MainActor
final class AppWindowController: NSObject, NSWindowDelegate {
    private let context: AppContext
    /// Called each time the window opens (an app-health sample for the statistics).
    var onShow: (() -> Void)?
    private var window: NSWindow?

    init(context: AppContext) {
        self.context = context
    }

    func show() {
        onShow?()
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = Self.makeWindow(
            rootView: AppWindowView(context: context),
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
        context.progress.onboardingDone = true
        NSApp.setActivationPolicy(.accessory)
        // Release after AppKit finishes closing, so the SwiftUI view tree is freed (unless it was
        // opened again straight away).
        let closing = notification.object as? NSWindow
        DispatchQueue.main.async { [weak self] in
            guard let self, let closing, self.window === closing, !closing.isVisible else { return }
            closing.contentView = nil
            self.window = nil
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

        let arrangement = ModuleArrangement()
        let nowPlayingSettings = NowPlayingSettings(defaults: defaults)
        let nowPlaying = NowPlayingCenter.practiceSnapshot(playing: true, elapsed: 74)
        let statsStore = StatsStore(url: nil)
        sampleStatistics(statsStore)
        let context = AppContext(
            preferences: preferences,
            shortcuts: noShortcut,
            stats: stats,
            progress: progress,
            arrangement: arrangement,
            shelfSettings: shelfSettings,
            shelfStore: shelfStore,
            nowPlayingSettings: nowPlayingSettings,
            nowPlaying: nowPlaying,
            statsStore: statsStore,
            makeLiveModules: {
                var modules: [any NotchModule] = []
                if nowPlayingSettings.isEnabled { modules.append(NowPlayingSnapshot.module()) }
                if shelfSettings.isEnabled { modules.append(ShelfModule(store: shelfStore, settings: shelfSettings)) }
                return modules
            }
        )

        func render(_ name: String, section: AppSection, lesson: LessonID = .basics, shortcuts: ShortcutController = noShortcut,
                    size: CGSize = AppWindowView.defaultSize) throws {
            let pageContext = shortcuts === noShortcut ? context : AppContext(
                preferences: preferences, shortcuts: shortcuts, stats: stats, progress: progress, arrangement: arrangement,
                shelfSettings: shelfSettings, shelfStore: shelfStore, nowPlayingSettings: nowPlayingSettings,
                nowPlaying: nowPlaying, statsStore: statsStore, makeLiveModules: context.makeLiveModules
            )
            try render(name, rootView: AppWindowView(context: pageContext, section: section, lesson: lesson), size: size)
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
        try render("learn-nowplaying", section: .learn, lesson: .nowPlaying)
        try render("modules-long", section: .modules, size: CGSize(width: 1000, height: 2200))
        try render("statistics-long", section: .statistics, size: CGSize(width: 1000, height: 2000))
        try render("notch-long", section: .notch, size: CGSize(width: 1000, height: 2000))
        // "While playing" with Now Playing off points to the Modules page.
        preferences.fullScreenHiding = .whilePlaying
        nowPlayingSettings.isEnabled = false
        try render("notch-long-playing-off", section: .notch, size: CGSize(width: 1000, height: 2000))
        nowPlayingSettings.isEnabled = true
        preferences.fullScreenHiding = .always

        // Now Playing's settings in each sound-bar state (the practice center: nothing is listened to).
        let soundBarStates: [(String, SoundBarsStyle, SoundBarsAccess)] = [
            ("gentle", .gentle, .unknown), ("still", .still, .unknown), ("follow", .followMusic, .unknown),
            ("follow-allowed", .followMusic, .allowed), ("follow-denied", .followMusic, .denied),
        ]
        for (name, style, access) in soundBarStates {
            nowPlayingSettings.soundBars = style
            nowPlayingSettings.soundBarsAccess = access
            let rows = NowPlayingSettingsRows(settings: nowPlayingSettings, center: nowPlaying)
                .frame(width: 760)
                .glassPanel()
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(AppPalette.background)
            try render("nowplaying-settings-\(name)", rootView: rows.appWindowStyle(), size: CGSize(width: 820, height: 900))
        }
        nowPlayingSettings.soundBars = .gentle
        nowPlayingSettings.soundBarsAccess = .unknown

        // The welcome, one image per step, the way a first launch shows it.
        for step in OnboardingView.Step.allCases {
            try render("onboarding-\(step.rawValue + 1)", rootView: OnboardingView(
                preferences: preferences, shortcuts: noShortcut, stats: stats, progress: progress, step: step
            ).appWindowStyle())
        }

        // The practice Shelf working: open with the example items, then with one item opened.
        let practice = PracticeShelf(seeded: true)
        defer { practice.close() }
        let stage = NotchStage(behavior: preferences.notchBehavior, modules: [practice.module], startState: .expanded)
            .background(AppPalette.background)
        try render("stage-open", rootView: stage.appWindowStyle(), size: CGSize(width: 900, height: 600), settle: 1.2)
        try render("stage-item", rootView: stage.appWindowStyle(), size: CGSize(width: 900, height: 600), settle: 1.2) {
            practice.openItem(at: 1)
        }

        // Home's live notch, open, showing the (sample) real Shelf.
        let live = NotchStage(
            behavior: preferences.notchBehavior,
            arrangement: arrangement,
            modules: context.makeLiveModules(),
            startState: .expanded
        )
        .background(AppPalette.background)
        try render("stage-live", rootView: live.appWindowStyle(), size: CGSize(width: 900, height: 600), settle: 1.2)

        for lesson in LessonID.allCases { progress.markDone(lesson) }
        try render("home-learned", section: .home)
        for lesson in LessonID.allCases { progress.reset(lesson) }

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
                try render("notch-long-shortcut", section: .notch, shortcuts: withShortcut, size: CGSize(width: 1000, height: 2000))
            }
        }
    }

    /// A week of made-up listening, notch use and memory samples, for the Statistics page snapshot.
    private static func sampleStatistics(_ store: StatsStore) {
        let songs: [(String, String, String)] = [
            ("Pancake Sunrise", "The Flipsides", "com.apple.Music"),
            ("Golden Edges", "Maple & Co.", "com.spotify.client"),
            ("Night Owl", "Syrup Static", "com.apple.Music"),
            ("Butter Blues", "The Flipsides", "com.spotify.client"),
        ]
        for day in 0..<7 {
            let date = Date().addingTimeInterval(-Double(day) * 86_400)
            for (index, song) in songs.enumerated() where (day + index) % 3 != 0 {
                store.recordListening(title: song.0, artist: song.1, album: "", bundleID: song.2,
                                      started: date.addingTimeInterval(-Double(index) * 600), seconds: Double(180 * (index + 1 + day % 3)))
            }
            for _ in 0..<(12 + day * 3) { store.recordNotchOpen(at: date) }
            for _ in 0..<(8 + day) { store.recordModuleShown("nowPlaying", at: date) }
            for _ in 0..<(4 + day) { store.recordModuleShown("shelf", at: date) }
            store.recordShelved(count: day + 1, at: date)
            store.recordHealth(HealthSample(date: date, footprintBytes: UInt64(31 + day) << 20, helperFootprintBytes: 6 << 20, cpuPercent: 0.2))
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
