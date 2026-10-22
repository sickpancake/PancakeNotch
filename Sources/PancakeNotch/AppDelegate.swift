import AgentsCore
import AppKit
import Learn
import ModuleAgents
import ModuleNowPlaying
import ModuleShelf
import NotchCore
import NowPlayingCore
import os
import Stats

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "app")

    /// Set `PANCAKENOTCH_SIMULATE_NOTCH=1` to fake a notch on screens without one (CI, external displays).
    private let simulateNotch = ProcessInfo.processInfo.environment["PANCAKENOTCH_SIMULATE_NOTCH"] == "1"

    /// Module ranking, favorites, ear sides and navigation, shared by the notch and the app window.
    private let arrangement = ModuleArrangement(defaults: .standard)

    /// Set `PANCAKENOTCH_DEBUG_STATE=compact|expanded` to pin the notch in that state (screenshots, design work).
    private lazy var notchController = NotchWindowController(
        initialState: ProcessInfo.processInfo.environment["PANCAKENOTCH_DEBUG_STATE"].flatMap(NotchState.init(rawValue:)),
        arrangement: arrangement
    )

    private let preferences = Preferences()
    private let stats = UsageStats()
    private let shelfSettings = ShelfSettings()
    /// Loads only the saved item list; files are checked when the notch opens.
    private lazy var shelfStore = ShelfStore()
    /// Exists only while the Shelf is switched on.
    private var shelf: ShelfModule?
    private let nowPlayingSettings = NowPlayingSettings()
    /// What's playing. Its helper process runs only while Now Playing is switched on.
    /// `PANCAKENOTCH_DEBUG_PLAYER=practice` plays the silent practice songs instead (benchmark: CI has
    /// no music), without recording them in the statistics.
    private lazy var nowPlaying: NowPlayingCenter = {
        if ProcessInfo.processInfo.environment["PANCAKENOTCH_DEBUG_PLAYER"] == "practice" { return .practice() }
        let center = NowPlayingCenter.live(settings: nowPlayingSettings)
        center.onListened = { [weak self] record in
            self?.statistics.recordListening(
                title: record.title, artist: record.artist, album: record.album,
                bundleID: record.bundleID, started: record.started, seconds: record.seconds
            )
        }
        return center
    }()
    /// Exists only while Now Playing is switched on.
    private var nowPlayingModule: NowPlayingModule?
    /// Listening, usage and app-health statistics, in a local file (ADR-0018).
    private let statistics = StatsStore(url: StatsStore.defaultURL())
    private let agentsSettings = AgentsSettings()
    /// Agent threads. Follows the tools only while Agents is switched on.
    private lazy var agents = AgentsCenter(settings: agentsSettings)
    /// AI accounts, limits and token history. Follows them only while AI Usage is switched on.
    private lazy var usage = UsageCenter(settings: agentsSettings, stats: statistics)
    /// Reads the tools' hook files when first asked (Agents switched on, or its settings shown).
    private lazy var connector = AgentConnector(settings: agentsSettings)
    /// Exists only while Agents is switched on.
    private var agentsModule: AgentsModule?
    /// Exists only while AI Usage is switched on.
    private var usageModule: AIUsageModule?
    private var followedAccountFolders: [String] = []
    /// Keeps at most one app-health sample per 10 minutes, taken when the notch or window opens.
    private var healthSampler = HealthSampler()
    private var lastStatisticsCleanup: Date?
    /// The Shelf's item count, to count items put on it.
    private var shelfCount: Int?
    private lazy var shortcuts = ShortcutController { [weak self] in self?.notchController.toggle() }
    /// Finished lessons and whether the welcome has been seen.
    private let learnProgress = LearnProgress()
    /// Sparkle's daily update check (released builds only).
    private let updates = Updates()
    private lazy var appWindow: AppWindowController = {
        let controller = AppWindowController(context: AppContext(
            preferences: preferences,
            shortcuts: shortcuts,
            stats: stats,
            progress: learnProgress,
            arrangement: arrangement,
            shelfSettings: shelfSettings,
            shelfStore: shelfStore,
            nowPlayingSettings: nowPlayingSettings,
            nowPlaying: nowPlaying,
            statsStore: statistics,
            updates: updates,
            agentsSettings: agentsSettings,
            agents: agents,
            usage: usage,
            connector: connector,
            makeLiveModules: { [weak self] in self?.makeLiveModules() ?? [] }
        ))
        controller.onShow = { [weak self] in self?.sampleHealth() }
        return controller
    }()
    private lazy var menuBar = MenuBarController(
        preferences: preferences,
        updates: updates,
        openApp: { [weak self] in self?.showAppWindow() }
    )

    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var appObserver: NSObjectProtocol?
    /// Hides the notch in full screen as the user chose.
    private lazy var fullScreen = FullScreenWatch(preferences: preferences, nowPlaying: nowPlaying, notch: notchController)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = ProcessInfo.processInfo.environment["PANCAKENOTCH_SNAPSHOT"] {
            writeSnapshot(to: path)
            return
        }
        if let path = ProcessInfo.processInfo.environment["PANCAKENOTCH_SNAPSHOT_SETTINGS"] {
            try? AppWindowController.writeSnapshots(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
            return
        }
        NSApp.mainMenu = MainMenu.make(target: self, settingsAction: #selector(showSettings),
                                       updatesAction: updates.isAvailable ? #selector(checkForUpdates) : nil)
        notchController.onOpen = { [weak self] in
            guard let self else { return }
            self.stats.recordOpen()
            self.statistics.recordNotchOpen()
            self.sampleHealth()
            self.removeOldStatisticsDaily()
        }
        notchController.onModuleShown = { [weak self] moduleID in self?.statistics.recordModuleShown(moduleID) }
        notchController.openSettings = { [weak self] in self?.showSettings() }
        observePreferences()
        seedShelfIfRequested()
        observeModules()
        cycleNotchIfRequested()
        _ = shortcuts // registers the saved shortcut
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateGeometry() }
        }
        // Entering or leaving a full-screen app switches Spaces. macOS hides the notch during the swipe,
        // so a pointer that left meanwhile sent no hover exit: check it now.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fullScreen.update()
                self?.notchController.model?.pointerMayHaveLeft()
            }
        }
        // Switching apps can bring a listed app to the front within the same Space.
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fullScreen.update() }
        }
        updateGeometry()
        updates.onPendingChange = { [weak self] in self?.menuBar.updatePending() }
        updates.start()
        showWelcomeIfNeeded()
        // Housekeeping waits until the notch has drawn. Old statistics go on the first open of the day
        // (removeOldStatisticsDaily), so the statistics file isn't opened at launch.
        DispatchQueue.main.async { [shelfStore] in
            ShelfModule.removeTemporaryFiles()
            PracticeShelf.removeLeftovers()
            shelfStore.removeOrphanedFiles()
        }
    }

    /// The first launch (or the first since the welcome was added) opens the window on the welcome.
    /// Only once: a welcome paused by closing the window waits until the window is opened again.
    /// `PANCAKENOTCH_SKIP_ONBOARDING=1` keeps it closed, e.g. for the idle memory check.
    private func showWelcomeIfNeeded() {
        guard !learnProgress.onboardingDone, !learnProgress.onboardingShown,
              ProcessInfo.processInfo.environment["PANCAKENOTCH_SKIP_ONBOARDING"] == nil else { return }
        showAppWindow()
    }

    /// Writes text typed in the Shelf's editor that's still waiting to be saved.
    func applicationWillTerminate(_ notification: Notification) {
        shelfStore.saveEdits()
        // Ends the Now Playing helper and the current listening stretch, then lets it reach the file.
        if nowPlayingModule != nil { nowPlaying.stop() }
        agents.stop()
        usage.stop()
        statistics.waitForWrites()
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows the app window — the way back
    /// when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showAppWindow()
        return false
    }

    @objc private func showAppWindow() {
        appWindow.show()
    }

    /// Settings… (⌘,) and the notch's gear: the window on General.
    @objc private func showSettings() {
        appWindow.show(section: .general)
    }

    @objc private func checkForUpdates() {
        updates.checkNow()
    }

    /// Applies preferences now and again whenever one changes (no polling). Only the preferences are
    /// read while tracking: applying them touches the notch, whose changes mustn't re-run this.
    private func observePreferences() {
        let (enabled, behavior, menuBarIcon, _) = withObservationTracking {
            (preferences.notchEnabled, preferences.notchBehavior, preferences.showMenuBarIcon, preferences.fullScreenHiding)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observePreferences() }
        }
        notchController.isEnabled = enabled
        notchController.behavior = behavior
        menuBar.isVisible = menuBarIcon
        fullScreen.update()
    }

    /// `PANCAKENOTCH_SHELF_SEED=/folder` fills an empty Shelf with that folder's files (memory checks;
    /// pair it with `PANCAKENOTCH_SHELF_DIR` so the real Shelf isn't touched).
    private func seedShelfIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["PANCAKENOTCH_SHELF_SEED"], shelfStore.items.isEmpty,
              let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)
        else { return }
        let inputs = files.sorted { $0.path < $1.path }.map { ShelfInput.file($0, owned: false) }
        shelfStore.add(inputs, duplicates: .addAgain)
    }

    /// `PANCAKENOTCH_DEBUG_CYCLE=<seconds>` opens and closes the notch on that beat (benchmark: what the
    /// animations cost). A debug switch only: normal use has no such loop (AGENTS.md rule 2).
    private func cycleNotchIfRequested() {
        guard let value = ProcessInfo.processInfo.environment["PANCAKENOTCH_DEBUG_CYCLE"],
              let seconds = Double(value), seconds > 0 else { return }
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(seconds))
                guard let self else { return }
                guard let model = notchController.model else { continue }
                if model.state == .expanded { model.close() } else { model.open() }
            }
        }
    }

    /// A second copy of what the real notch shows, on the same real data, for the live notch on Home.
    /// Each copy has its own open/selected state; items, the song and settings are shared.
    private func makeLiveModules() -> [any NotchModule] {
        var modules: [any NotchModule] = []
        if nowPlayingSettings.isEnabled { modules.append(NowPlayingModule(center: nowPlaying)) }
        if shelfSettings.isEnabled { modules.append(ShelfModule(store: shelfStore, settings: shelfSettings)) }
        if agentsSettings.agentsEnabled { modules.append(AgentsModule(center: agents, peeks: false)) }
        if agentsSettings.usageEnabled { modules.append(AIUsageModule(center: usage, peeks: false)) }
        return modules
    }

    /// Creates each module while it's switched on and drops it when it's off (Now Playing's helper
    /// stops; the Shelf takes no drops). Runs again whenever a switch changes (no polling).
    private func observeModules() {
        let (nowPlayingOn, shelfOn, agentsOn, usageOn, accountFolders) = withObservationTracking {
            (nowPlayingSettings.isEnabled, shelfSettings.isEnabled, agentsSettings.agentsEnabled,
             agentsSettings.usageEnabled, agentsSettings.addedFolders)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeModules() }
        }
        let accountsChanged = accountFolders != followedAccountFolders
        followedAccountFolders = accountFolders
        if nowPlayingOn {
            if nowPlayingModule == nil { nowPlayingModule = NowPlayingModule(center: nowPlaying) }
            nowPlaying.start()
        } else if nowPlayingModule != nil {
            nowPlayingModule = nil
            nowPlaying.stop()
        }
        if shelfOn {
            if shelf == nil {
                let module = ShelfModule(store: shelfStore, settings: shelfSettings)
                shelfCount = shelfStore.items.count
                module.onEvent = { [weak self] event in self?.shelfChanged(event) }
                shelf = module
            }
        } else {
            shelf = nil
        }
        if agentsOn {
            if agentsModule == nil {
                agentsModule = AgentsModule(center: agents)
                agents.start()
                connector.updateHelperIfConnected()
            } else if accountsChanged {
                agents.refreshAccounts()
            }
        } else if agentsModule != nil {
            agentsModule = nil
            agents.stop()
        }
        if usageOn {
            if usageModule == nil {
                usageModule = AIUsageModule(center: usage)
                usage.start()
            } else if accountsChanged {
                usage.refreshAccounts()
            }
        } else if usageModule != nil {
            usageModule = nil
            usage.stop()
        }
        notchController.modules = [nowPlayingModule as (any NotchModule)?, shelf, agentsModule, usageModule].compactMap { $0 }
    }

    /// Counts items put on the Shelf and sent with AirDrop, for the statistics.
    private func shelfChanged(_ event: ShelfEvent) {
        switch event {
        case .itemsChanged(let count):
            if let before = shelfCount, count > before { statistics.recordShelved(count: count - before) }
            shelfCount = count
        case .airDropped(let count):
            statistics.recordAirDropped(count: count)
        default:
            break
        }
    }

    /// Statistics older than 90 days go on the first notch open of each day (the app can run for
    /// weeks), never on a timer.
    private func removeOldStatisticsDaily() {
        let today = Calendar.current.startOfDay(for: Date())
        guard lastStatisticsCleanup != today else { return }
        lastStatisticsCleanup = today
        statistics.removeOld()
    }

    /// An app-health sample (memory and CPU, the Now Playing helper included), at most every 10 minutes.
    private func sampleHealth() {
        let helper = nowPlayingModule != nil ? nowPlaying.helperProcessID : nil
        if let sample = healthSampler.sample(now: Date(), helperPID: helper) {
            statistics.recordHealth(sample)
        }
    }

    private func updateGeometry() {
        let geometry = currentGeometry()
        if let geometry {
            logger.info("Notch at \(String(describing: geometry.notchRect), privacy: .public) simulated=\(geometry.isSimulated)")
        } else {
            logger.info("No notch available; idling")
        }
        notchController.update(geometry: geometry)
        fullScreen.update()
    }

    /// Renders all notch states to a PNG and quits. See `NotchSnapshot`.
    private func writeSnapshot(to path: String) {
        let geometry = currentGeometry() ?? .simulated(in: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982))
        do {
            try NotchSnapshot.write(geometry: geometry, to: URL(fileURLWithPath: path)) { layout in
                NowPlayingSnapshot.models(layout: layout) + Self.moduleSnapshots(layout: layout) + ShelfSnapshot.models(layout: layout)
                    + AgentsSnapshot.models(layout: layout)
            }
        } catch {
            logger.error("Snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
        NSApp.terminate(nil)
    }

    /// Now Playing and the Shelf together: both ears, the tabs, the Menu, the Shelf picked, "Menu only".
    private static func moduleSnapshots(layout: NotchLayout) -> [NotchViewModel] {
        func model(_ state: NotchState, navigation: NotchNavigation = .tabsAndMenu, swapped: Bool = false,
                   shelf: any NotchModule = ShelfPreviewModule(), setUp: (NotchViewModel) -> Void = { _ in }) -> NotchViewModel {
            let arrangement = ModuleArrangement()
            arrangement.navigation = navigation
            arrangement.swapsEarSides = swapped
            let model = NotchViewModel(layout: layout, state: state, arrangement: arrangement)
            model.modules = [NowPlayingSnapshot.module(), shelf]
            setUp(model)
            return model
        }
        return [
            model(.compact, shelf: ShelfSnapshot.module(itemCount: 16)),
            model(.compact, swapped: true, shelf: ShelfSnapshot.module(itemCount: 20)),
            model(.expanded),
            model(.expanded) { $0.toggleMenu() },
            model(.expanded) { $0.select("shelf") },
            model(.expanded, navigation: .tabs) { $0.select("shelf") },
            model(.expanded, navigation: .menu),
        ]
    }

    private func currentGeometry() -> NotchGeometry? {
        if let geometry = NSScreen.builtIn?.notchGeometry { return geometry }
        if simulateNotch, let screen = NSScreen.main { return .simulated(in: screen.frame) }
        return nil
    }
}
