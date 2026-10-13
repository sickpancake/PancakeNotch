import AppKit

/// MediaRemote command numbers, as the adapter lists them in `enabledCommands`.
public enum MediaCommand {
    public static let nextTrack = 4
    public static let previousTrack = 5
    /// Jumping to a position in the song (dragging the progress bar).
    public static let changePlaybackPosition = 24
    public static let changeRepeatMode = 25
    public static let changeShuffleMode = 26
}

/// Who carries out a shuffle or repeat change.
public enum ModeRoute: Equatable, Sendable {
    /// The backend: the helper (when the player reports the mode), the Music/Spotify fallback or the
    /// practice player.
    case player
    /// AppleScript straight to Music or Spotify, because the helper doesn't see the mode (Spotify never
    /// reports it to macOS).
    case script
}

/// Which player controls really work right now, for one song in one app. Buttons that don't work are
/// hidden (shuffle, repeat) or dimmed (back, forward, the progress bar): nothing shows and does nothing.
///
/// A pure value, worked out from what the player reports, so it's easy to test.
public struct PlayerAbilities: Equatable, Sendable {
    /// nil = no shuffle button.
    public var shuffleRoute: ModeRoute?
    /// nil = no repeat button.
    public var repeatRoute: ModeRoute?
    /// What the shuffle button shows; nil when it's hidden.
    public var shuffle: ShuffleMode?
    /// What the repeat button shows; nil when it's hidden.
    public var repeatMode: RepeatMode?
    /// The order the repeat button goes through. Spotify has no "repeat this song" for scripts.
    public var repeatCycle: [RepeatMode]
    public var canSkipForward: Bool
    public var canSkipBack: Bool
    /// The progress bar can be dragged or clicked.
    public var canSeek: Bool
    /// An ad plays: skipping and seeking are refused.
    public var isAdvertisement: Bool

    public var canShuffle: Bool { shuffleRoute != nil }
    public var canRepeat: Bool { repeatRoute != nil }

    /// Nothing playing: nothing works.
    public static let none = PlayerAbilities(
        shuffleRoute: nil, repeatRoute: nil, shuffle: nil, repeatMode: nil, repeatCycle: [],
        canSkipForward: false, canSkipBack: false, canSeek: false, isAdvertisement: false
    )

    static let fullRepeatCycle: [RepeatMode] = [.off, .playlist, .track]
    static let onOffRepeatCycle: [RepeatMode] = [.off, .playlist]

    /// Works out the controls for `track`.
    /// - Parameters:
    ///   - connection: where the track comes from (the practice player reports everything itself).
    ///   - scripted: shuffle and repeat read from Music or Spotify with AppleScript, when the helper
    ///     doesn't report them; nil when not read (or not allowed).
    public static func resolve(track: NowPlayingTrack?, connection: NowPlayingConnection, scripted: ScriptedModes?) -> PlayerAbilities {
        guard let track else { return .none }
        let isAd = track.isAdvertisement
        let commands = track.enabledCommands
        // Unknown commands (older helper, fallback, practice) count as accepted.
        func accepts(_ command: Int) -> Bool { commands?.contains(command) ?? true }

        let isSpotify = track.bundleID == ScriptablePlayers.spotify
        var abilities = PlayerAbilities(
            shuffleRoute: nil, repeatRoute: nil, shuffle: nil, repeatMode: nil,
            repeatCycle: isSpotify ? onOffRepeatCycle : fullRepeatCycle,
            canSkipForward: !isAd && accepts(MediaCommand.nextTrack),
            canSkipBack: !isAd && accepts(MediaCommand.previousTrack),
            canSeek: !isAd && (track.duration ?? 0) > 0 && accepts(MediaCommand.changePlaybackPosition),
            isAdvertisement: isAd
        )
        // No shuffle or repeat during an ad.
        guard !isAd else { return abilities }

        let mayScript = connection == .connected && ScriptablePlayers.contains(track.bundleID)
        if let shuffle = track.shuffle, accepts(MediaCommand.changeShuffleMode) {
            abilities.shuffleRoute = .player
            abilities.shuffle = shuffle
        } else if mayScript, let shuffle = scripted?.shuffle {
            abilities.shuffleRoute = .script
            abilities.shuffle = shuffle
        }
        if let mode = track.repeatMode, accepts(MediaCommand.changeRepeatMode) {
            abilities.repeatRoute = .player
            abilities.repeatMode = mode
        } else if mayScript, let mode = scripted?.repeatMode {
            abilities.repeatRoute = .script
            abilities.repeatMode = mode
        }
        // Spotify only knows "repeat on" (shown as the whole list).
        if isSpotify, abilities.repeatMode == .track { abilities.repeatMode = .playlist }
        return abilities
    }

    /// The repeat mode after `mode` in this app's cycle.
    public func nextRepeatMode(after mode: RepeatMode) -> RepeatMode {
        guard let index = repeatCycle.firstIndex(of: mode) else { return repeatCycle.first ?? .off }
        return repeatCycle[(index + 1) % repeatCycle.count]
    }

    /// Why back or forward is dimmed (for the tooltip and VoiceOver).
    public var skipBlockedReason: String {
        if isAdvertisement { return String(localized: "Can't skip during an ad") }
        return String(localized: "The app doesn't allow skipping right now")
    }

    /// Why the progress bar can't be moved (for the tooltip and VoiceOver).
    public var seekBlockedReason: String {
        isAdvertisement
            ? String(localized: "Can't move the position during an ad")
            : String(localized: "The app doesn't allow moving the position")
    }
}

/// Shuffle and repeat as Music or Spotify said over AppleScript.
public struct ScriptedModes: Equatable, Sendable {
    public var shuffle: ShuffleMode?
    public var repeatMode: RepeatMode?

    public init(shuffle: ShuffleMode?, repeatMode: RepeatMode?) {
        self.shuffle = shuffle
        self.repeatMode = repeatMode
    }
}

/// The apps PancakeNotch can control with AppleScript (Automation permission): Music and Spotify.
public enum ScriptablePlayers {
    public static let music = "com.apple.Music"
    public static let spotify = "com.spotify.client"
    public static let all = [music, spotify]

    public static func contains(_ bundleID: String?) -> Bool {
        bundleID.map(all.contains) ?? false
    }
}

/// What the "Resume" button in "Nothing playing" does.
public enum ResumeOption: Equatable, Sendable {
    /// The practice player plays again.
    case practice
    /// Music or Spotify is told to play with AppleScript (launching it if needed). Never the generic
    /// "play" of macOS: with no session that always starts Apple Music.
    case app(String)
    /// Music or Spotify refused the Automation permission: offer the way to allow it instead.
    case needsPermission(String)

    /// nil = no Resume button (the last player can't be told to play: a browser, Podcasts, …).
    public static func resolve(
        lastPlayer: String?, connection: NowPlayingConnection, deniedApps: Set<String>,
        isInstalled: (String) -> Bool
    ) -> ResumeOption? {
        switch connection {
        case .practice: return .practice
        case .unavailable: return nil
        case .starting, .connected, .limited: break
        }
        guard let lastPlayer, ScriptablePlayers.contains(lastPlayer), isInstalled(lastPlayer) else { return nil }
        return deniedApps.contains(lastPlayer) ? .needsPermission(lastPlayer) : .app(lastPlayer)
    }
}

/// The apps the "Open" button and its ▾ menu offer when nothing is playing.
public enum MediaApps {
    /// Well-known media apps, offered when they're installed (Music first: it's on every Mac).
    public static let known = [
        "com.apple.Music", "com.spotify.client", "com.apple.podcasts", "com.apple.TV",
        "com.tidal.desktop", "com.deezer.deezer-desktop", "com.amazon.music", "org.videolan.vlc", "com.colliderli.iina",
    ]

    /// Never offered: PancakeNotch itself and its practice player.
    static let excluded: Set<String> = ["io.github.sickpancake.PancakeNotch", "io.github.sickpancake.PancakeNotch.practice"]

    /// The app the main "Open" button opens: the last player if it's still installed, else the first
    /// installed well-known app. nil = nothing to open (the button is hidden).
    public static func mainApp(lastPlayer: String?, isInstalled: (String) -> Bool) -> String? {
        if let lastPlayer, !excluded.contains(lastPlayer), isInstalled(lastPlayer) { return lastPlayer }
        return known.first(where: isInstalled)
    }

    /// The ▾ menu: apps seen playing (most recent first), then the installed well-known ones. No
    /// duplicates, only installed apps, and not `main` (the button already opens it).
    public static func menuApps(seen: [String], main: String?, isInstalled: (String) -> Bool) -> [String] {
        var result: [String] = []
        var taken = excluded
        if let main { taken.insert(main) }
        for bundleID in seen + known where !bundleID.isEmpty && !taken.contains(bundleID) {
            taken.insert(bundleID)
            if isInstalled(bundleID) { result.append(bundleID) }
        }
        return result
    }
}

/// Whether apps are installed, looked up once per app and remembered for this run (no disk lookups per
/// redraw). `forget()` starts over, e.g. when the user opens the app menu.
@MainActor
public enum InstalledApps {
    private static var cache: [String: Bool] = [:]

    public static func isInstalled(_ bundleID: String) -> Bool {
        if let known = cache[bundleID] { return known }
        let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        cache[bundleID] = found
        return found
    }

    public static func forget() {
        cache = [:]
    }
}

/// Telling Spotify's ads apart from songs.
enum SpotifyAd {
    /// Spotify's ads have addresses like `spotify:ad:…` (songs: `spotify:track:…`).
    static func isAdAddress(_ address: String?) -> Bool {
        address?.hasPrefix("spotify:ad:") ?? false
    }

    /// From what AppleScript says about the current track: its address when there is one, else the
    /// tell-tale "popularity 0 and track number 0" of ads.
    static func isAd(address: String?, popularity: Int?, trackNumber: Int?) -> Bool {
        if let address, !address.isEmpty { return isAdAddress(address) }
        return popularity == 0 && trackNumber == 0
    }
}
