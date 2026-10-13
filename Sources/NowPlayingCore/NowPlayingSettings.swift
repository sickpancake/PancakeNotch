import Foundation
import Observation

/// Now Playing's options in the app window (Modules page). Stored in `UserDefaults`.
@MainActor
@Observable
public final class NowPlayingSettings {
    public var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Keys.enabled) } }
    /// Album art and sound bars beside the closed notch.
    public var showsInEars: Bool { didSet { defaults.set(showsInEars, forKey: Keys.showsInEars) } }
    /// Show a new song for a moment when it starts.
    public var peeksOnSongChange: Bool { didSet { defaults.set(peeksOnSongChange, forKey: Keys.peeksOnSongChange) } }
    /// The right-hand time shows what's left (-0:42) instead of the song's length.
    public var showsRemainingTime: Bool { didSet { defaults.set(showsRemainingTime, forKey: Keys.showsRemainingTime) } }
    /// How the sound bars beside the notch move.
    public var soundBars: SoundBarsStyle { didSet { defaults.set(soundBars.rawValue, forKey: Keys.soundBars) } }
    /// What the bars show while they follow the music.
    public var soundBarsShow: SoundBarsShow { didSet { defaults.set(soundBarsShow.rawValue, forKey: Keys.soundBarsShow) } }
    /// Whether macOS lets the bars hear the music ("System Audio Recording"), as far as PancakeNotch has
    /// seen. `.denied` is remembered so nobody is asked again until they press Try Again.
    public var soundBarsAccess: SoundBarsAccess {
        didSet { defaults.set(soundBarsAccess.rawValue, forKey: Keys.soundBarsAccess) }
    }

    /// Apps (bundle IDs) never shown in the notch. Always sorted, no duplicates.
    public var ignoredApps: [String] {
        get { storedIgnoredApps }
        set {
            let normalized = Self.normalized(newValue)
            guard normalized != storedIgnoredApps else { return }
            storedIgnoredApps = normalized
            defaults.set(normalized, forKey: Keys.ignoredApps)
        }
    }

    private var storedIgnoredApps: [String]

    /// Also holds what `NowPlayingCenter` remembers (the last player, the apps seen playing).
    @ObservationIgnored let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        showsInEars = defaults.object(forKey: Keys.showsInEars) as? Bool ?? true
        peeksOnSongChange = defaults.object(forKey: Keys.peeksOnSongChange) as? Bool ?? false
        showsRemainingTime = defaults.object(forKey: Keys.showsRemainingTime) as? Bool ?? true
        soundBars = defaults.string(forKey: Keys.soundBars).flatMap(SoundBarsStyle.init(rawValue:)) ?? .gentle
        soundBarsShow = defaults.string(forKey: Keys.soundBarsShow).flatMap(SoundBarsShow.init(rawValue:)) ?? .bands
        soundBarsAccess = defaults.string(forKey: Keys.soundBarsAccess).flatMap(SoundBarsAccess.init(rawValue:)) ?? .unknown
        storedIgnoredApps = Self.normalized(defaults.stringArray(forKey: Keys.ignoredApps) ?? [])
        if defaults == UserDefaults.standard { Self.user = self }
    }

    /// The user's own settings (the ones in the standard defaults), once they exist. The practice
    /// players keep throwaway settings, but their sound bars show the user's choice.
    public private(set) static weak var user: NowPlayingSettings?

    public func isIgnored(_ bundleID: String) -> Bool {
        storedIgnoredApps.contains(bundleID)
    }

    public func ignore(_ bundleID: String) {
        ignoredApps.append(bundleID)
    }

    public func unignore(_ bundleID: String) {
        ignoredApps.removeAll { $0 == bundleID }
    }

    static func normalized(_ apps: [String]) -> [String] {
        Array(Set(apps.filter { !$0.isEmpty })).sorted()
    }

    enum Keys {
        static let enabled = "nowPlaying.enabled"
        static let showsInEars = "nowPlaying.showsInEars"
        static let peeksOnSongChange = "nowPlaying.peeksOnSongChange"
        static let showsRemainingTime = "nowPlaying.showsRemainingTime"
        static let soundBars = "nowPlaying.soundBars"
        static let soundBarsShow = "nowPlaying.soundBarsShow"
        static let soundBarsAccess = "nowPlaying.soundBarsAccess"
        static let ignoredApps = "nowPlaying.ignoredApps"
        static let lastPlayer = "nowPlaying.lastPlayer"
        static let seenApps = "nowPlaying.seenApps"
    }
}
