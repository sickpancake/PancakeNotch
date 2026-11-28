import AgentsCore
import KeepAwakeCore
import NotesCore
import Learn
import ModuleNowPlaying
import ModuleShelf
import NotchCore
import NowPlayingCore
import Observation
import Stats
import TimerCore

/// Which page the app window shows, and the lesson open on Learn. Lives with the app so menus and
/// the notch can open the window on a particular page.
@MainActor
@Observable
final class AppNavigation {
    var section: AppSection = .overview
    /// The lesson shown on Learn; other pages pick one before switching there.
    var lesson: LessonID = .basics
    /// Where the window goes when the welcome ends; Home unless the welcome asked for Learn.
    var sectionAfterWelcome: AppSection = .overview

    /// A module whose card the Modules page shows next, with its settings open while it's on (the notch's
    /// Library and right-click menus, ADR-0045). The page clears it once it's there.
    var focusedModule: String?
    /// Goes up on every request, so asking for the same card again scrolls to it again.
    private(set) var moduleFocusRequest = 0

    /// Opens a lesson on Learn.
    func open(_ lesson: LessonID) {
        self.lesson = lesson
        section = .learn
    }

    /// Opens Modules on one module's card.
    func openModule(_ moduleID: String) {
        focusedModule = moduleID
        moduleFocusRequest &+= 1
        section = .modules
    }
}

/// Everything the app window's pages share: the settings, the real modules' data and the statistics.
/// Made once by the app; the window's views come and go around it.
@MainActor
final class AppContext {
    let preferences: Preferences
    let shortcuts: ShortcutController
    let stats: UsageStats
    let progress: LearnProgress
    /// Module ranking, favorites, ear sides and how the open notch moves between modules.
    let arrangement: ModuleArrangement
    /// Home's widgets and options, shared with the real notch (ADR-0042).
    let home: HomeSettings
    let shelfSettings: ShelfSettings
    let shelfStore: ShelfStore
    /// Where new screenshots are caught from, for Shelf settings. Nil in snapshots.
    let screenshots: ShelfScreenshots?
    let nowPlayingSettings: NowPlayingSettings
    /// What's playing, shared with the real notch (one helper process).
    let nowPlaying: NowPlayingCenter
    let statsStore: StatsStore
    /// Sparkle's update checks (released builds only).
    let updates: Updates
    /// Agents and AI Usage options, and their data shared with the real notch.
    let agentsSettings: AgentsSettings
    let agents: AgentsCenter
    let usage: UsageCenter
    /// Connect and Disconnect for the tools' hooks.
    let connector: AgentConnector
    /// The reminder to connect Devin (issue #78), shared with the real notch.
    let connectReminder: ConnectReminder
    /// The Timer's options, and its timer and stopwatch shared with the real notch.
    let timerSettings: TimerSettings
    let timers: TimerCenter
    /// Keep Awake's options, and its state shared with the real notch and the menu bar.
    let keepAwakeSettings: KeepAwakeSettings
    let keepAwake: KeepAwakeCenter
    let notesSettings: NotesSettings
    let notesStore: NotesStore
    let navigation = AppNavigation()
    /// Whether the real notch's bar has room for another favorite (ADR-0045). `nil` (snapshots, a notch not
    /// made yet) never refuses.
    var canAddFavorite: (@MainActor () -> Bool)?
    /// The real notch's favorites that have no tab for lack of room (Help says where they are).
    var favoritesWithoutTab: (@MainActor () -> [String])?
    /// Copies of the notch's modules on the real data, for Home's live notch.
    let makeLiveModules: () -> [any NotchModule]
    /// Which AI tools are on this Mac, for the offer to switch on Agents and AI Usage.
    let detectTools: () -> [AgentTool]

    init(
        preferences: Preferences,
        shortcuts: ShortcutController,
        stats: UsageStats,
        progress: LearnProgress,
        arrangement: ModuleArrangement,
        home: HomeSettings,
        shelfSettings: ShelfSettings,
        shelfStore: ShelfStore,
        nowPlayingSettings: NowPlayingSettings,
        nowPlaying: NowPlayingCenter,
        statsStore: StatsStore,
        updates: Updates,
        agentsSettings: AgentsSettings,
        agents: AgentsCenter,
        usage: UsageCenter,
        connector: AgentConnector,
        connectReminder: ConnectReminder? = nil,
        timerSettings: TimerSettings,
        timers: TimerCenter,
        keepAwakeSettings: KeepAwakeSettings,
        keepAwake: KeepAwakeCenter,
        notesSettings: NotesSettings,
        notesStore: NotesStore,
        makeLiveModules: @escaping () -> [any NotchModule],
        detectTools: @escaping () -> [AgentTool] = { AgentsDetection.foundTools() },
        screenshots: ShelfScreenshots? = nil
    ) {
        self.screenshots = screenshots
        self.preferences = preferences
        self.shortcuts = shortcuts
        self.stats = stats
        self.progress = progress
        self.arrangement = arrangement
        self.home = home
        self.shelfSettings = shelfSettings
        self.shelfStore = shelfStore
        self.nowPlayingSettings = nowPlayingSettings
        self.nowPlaying = nowPlaying
        self.statsStore = statsStore
        self.updates = updates
        self.agentsSettings = agentsSettings
        self.agents = agents
        self.usage = usage
        self.connector = connector
        self.connectReminder = connectReminder ?? .preview(nil, settings: agentsSettings)
        self.timerSettings = timerSettings
        self.timers = timers
        self.keepAwakeSettings = keepAwakeSettings
        self.keepAwake = keepAwake
        self.notesSettings = notesSettings
        self.notesStore = notesStore
        self.makeLiveModules = makeLiveModules
        self.detectTools = detectTools
    }

    /// Whether a module is switched on (its card's switch on the Modules page).
    func isEnabled(_ moduleID: String) -> Bool {
        switch moduleID {
        case "nowPlaying": nowPlayingSettings.isEnabled
        case "shelf": shelfSettings.isEnabled
        case "agents": agentsSettings.agentsEnabled
        case "aiUsage": agentsSettings.usageEnabled
        case "timer": timerSettings.isEnabled
        case "keepAwake": keepAwakeSettings.isEnabled
        case "notes": notesSettings.isEnabled
        default: false
        }
    }

    func setEnabled(_ moduleID: String, _ enabled: Bool) {
        switch moduleID {
        case "nowPlaying": nowPlayingSettings.isEnabled = enabled
        case "shelf": shelfSettings.isEnabled = enabled
        case "agents": agentsSettings.agentsEnabled = enabled
        case "aiUsage": agentsSettings.usageEnabled = enabled
        case "timer": timerSettings.isEnabled = enabled
        case "keepAwake": keepAwakeSettings.isEnabled = enabled
        case "notes": notesSettings.isEnabled = enabled
        default: break
        }
    }

    /// The modules' names and symbols for the app window, by ID.
    static func moduleInfo(_ moduleID: String) -> (title: String, symbol: String) {
        let info = ModuleCatalog.info(moduleID)
        return (info.title, info.symbol)
    }
}
