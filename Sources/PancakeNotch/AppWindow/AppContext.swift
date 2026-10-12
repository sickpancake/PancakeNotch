import Learn
import ModuleNowPlaying
import ModuleShelf
import NotchCore
import NowPlayingCore
import Stats

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
    /// Copies of the notch's modules on the real data, for Home's live notch.
    let makeLiveModules: () -> [any NotchModule]

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
        makeLiveModules: @escaping () -> [any NotchModule]
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
        self.makeLiveModules = makeLiveModules
    }

    /// Whether a module is switched on (its card's switch on the Modules page).
    func isEnabled(_ moduleID: String) -> Bool {
        switch moduleID {
        case "nowPlaying": nowPlayingSettings.isEnabled
        case "shelf": shelfSettings.isEnabled
        default: false
        }
    }

    func setEnabled(_ moduleID: String, _ enabled: Bool) {
        switch moduleID {
        case "nowPlaying": nowPlayingSettings.isEnabled = enabled
        case "shelf": shelfSettings.isEnabled = enabled
        default: break
        }
    }

    /// The modules' names and symbols for the app window, by ID.
    static func moduleInfo(_ moduleID: String) -> (title: String, symbol: String) {
        switch moduleID {
        case "nowPlaying": (String(localized: "Now Playing", comment: "Module name"), "music.note")
        case "shelf": (String(localized: "Shelf", comment: "Module name"), "tray")
        default: (moduleID, "square")
        }
    }
}
