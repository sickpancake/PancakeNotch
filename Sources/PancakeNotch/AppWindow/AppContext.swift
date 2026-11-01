import AgentsCore
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
    var section: AppSection = .home
    /// The lesson shown on Learn; other pages pick one before switching there.
    var lesson: LessonID = .basics
    /// Where the window goes when the welcome ends; Home unless the welcome asked for Learn.
    var sectionAfterWelcome: AppSection = .home

    /// Opens a lesson on Learn.
    func open(_ lesson: LessonID) {
        self.lesson = lesson
        section = .learn
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
    let shelfSettings: ShelfSettings
    let shelfStore: ShelfStore
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
    /// The Timer's options, and its timer and stopwatch shared with the real notch.
    let timerSettings: TimerSettings
    let timers: TimerCenter
    let navigation = AppNavigation()
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
        timerSettings: TimerSettings,
        timers: TimerCenter,
        makeLiveModules: @escaping () -> [any NotchModule],
        detectTools: @escaping () -> [AgentTool] = { AgentsDetection.foundTools() }
    ) {
        self.preferences = preferences
        self.shortcuts = shortcuts
        self.stats = stats
        self.progress = progress
        self.arrangement = arrangement
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
        self.timerSettings = timerSettings
        self.timers = timers
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
        default: break
        }
    }

    /// The modules' names and symbols for the app window, by ID.
    static func moduleInfo(_ moduleID: String) -> (title: String, symbol: String) {
        switch moduleID {
        case "nowPlaying": (String(localized: "Now Playing", comment: "Module name"), "music.note")
        case "shelf": (String(localized: "Shelf", comment: "Module name"), "tray")
        case "agents": (String(localized: "Agents", comment: "Module name"), "sparkles")
        case "aiUsage": (String(localized: "AI Usage", comment: "Module name"), "gauge.with.dots.needle.50percent")
        case "timer": (String(localized: "Timer", comment: "Module name"), "timer")
        default: (moduleID, "square")
        }
    }
}
