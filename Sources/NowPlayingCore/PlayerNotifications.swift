import AppKit

/// What Music or Spotify announce system-wide whenever playback changes (no permission needed).
struct PlayerNotificationInfo: Equatable, Sendable {
    enum State: Equatable, Sendable { case playing, paused, stopped }

    static let musicBundleID = "com.apple.Music"
    static let spotifyBundleID = "com.spotify.client"
    static let musicNotification = Notification.Name("com.apple.Music.playerInfo")
    static let spotifyNotification = Notification.Name("com.spotify.client.PlaybackStateChanged")

    var bundleID: String
    var state: State
    var title: String
    var artist: String
    var album: String
    /// Seconds; nil when unknown.
    var duration: TimeInterval?
    /// Seconds into the song; only Spotify says.
    var position: TimeInterval?
    var trackID: String?

    /// Music's `com.apple.Music.playerInfo`: "Player State", "Name", "Artist", "Album",
    /// "Total Time" (milliseconds), "Persistent ID".
    static func music(_ userInfo: [AnyHashable: Any]?) -> PlayerNotificationInfo? {
        guard let userInfo, let state = state(userInfo["Player State"]) else { return nil }
        return PlayerNotificationInfo(
            bundleID: musicBundleID,
            state: state,
            title: userInfo["Name"] as? String ?? "",
            artist: userInfo["Artist"] as? String ?? "",
            album: userInfo["Album"] as? String ?? "",
            duration: number(userInfo["Total Time"]).flatMap { $0 > 0 ? $0 / 1000 : nil },
            position: nil,
            trackID: userInfo["Persistent ID"].map { "\($0)" }
        )
    }

    /// Spotify's `com.spotify.client.PlaybackStateChanged`: "Player State", "Name", "Artist", "Album",
    /// "Track ID", "Duration" (milliseconds, or seconds in old versions), "Playback Position" (seconds).
    static func spotify(_ userInfo: [AnyHashable: Any]?) -> PlayerNotificationInfo? {
        guard let userInfo, let state = state(userInfo["Player State"]) else { return nil }
        let duration = number(userInfo["Duration"]).flatMap { value -> TimeInterval? in
            guard value > 0 else { return nil }
            return value > 10_000 ? value / 1000 : value
        }
        return PlayerNotificationInfo(
            bundleID: spotifyBundleID,
            state: state,
            title: userInfo["Name"] as? String ?? "",
            artist: userInfo["Artist"] as? String ?? "",
            album: userInfo["Album"] as? String ?? "",
            duration: duration,
            position: number(userInfo["Playback Position"]).map { max(0, $0) },
            trackID: userInfo["Track ID"] as? String
        )
    }

    private static func state(_ value: Any?) -> State? {
        switch (value as? String)?.lowercased() {
        case "playing", "fast forwarding", "rewinding": .playing
        case "paused": .paused
        case "stopped": .stopped
        default: nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }

    /// The track to show for this notification. Music doesn't say where the song is, so the position
    /// carries on from `previous` when it's the same song (and starts at 0 for a new one).
    func track(previous: NowPlayingTrack?, at date: Date) -> NowPlayingTrack? {
        guard state != .stopped, !title.isEmpty else { return nil }
        var track = NowPlayingTrack(
            title: title, artist: artist, album: album, duration: duration,
            elapsed: 0, elapsedDate: date, isPlaying: state == .playing, bundleID: bundleID,
            isAdvertisement: bundleID == Self.spotifyBundleID && SpotifyAd.isAdAddress(trackID)
        )
        let sameSong = previous?.identity == track.identity
        if let position {
            track.elapsed = position
        } else if let previous, sameSong {
            track.elapsed = previous.elapsed(at: date)
        }
        if let previous, sameSong {
            track.shuffle = previous.shuffle
            track.repeatMode = previous.repeatMode
            track.artworkID = previous.artworkID
            if previous.isAdvertisement { track.isAdvertisement = true }
        }
        return track
    }
}

/// Listens for Music's and Spotify's announcements and for either app quitting.
///
/// Uses the selector-based API with `.deliverImmediately`: AppKit holds back distributed notifications
/// while an app is in the background (which this accessory app almost always is) unless asked not to.
@MainActor
final class PlayerNotificationWatcher: NSObject {
    var onInfo: ((PlayerNotificationInfo) -> Void)?
    var onQuit: ((_ bundleID: String) -> Void)?

    private var isWatching = false
    private var quitObserver: NSObjectProtocol?

    func start() {
        guard !isWatching else { return }
        isWatching = true
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(musicChanged(_:)), name: PlayerNotificationInfo.musicNotification,
                           object: nil, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(spotifyChanged(_:)), name: PlayerNotificationInfo.spotifyNotification,
                           object: nil, suspensionBehavior: .deliverImmediately)
        quitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let bundleID = app?.bundleIdentifier,
                  bundleID == PlayerNotificationInfo.musicBundleID || bundleID == PlayerNotificationInfo.spotifyBundleID
            else { return }
            MainActor.assumeIsolated { self?.onQuit?(bundleID) }
        }
    }

    func stop() {
        guard isWatching else { return }
        isWatching = false
        DistributedNotificationCenter.default().removeObserver(self)
        if let quitObserver { NSWorkspace.shared.notificationCenter.removeObserver(quitObserver) }
        quitObserver = nil
    }

    @objc nonisolated private func musicChanged(_ note: Notification) {
        guard let info = PlayerNotificationInfo.music(note.userInfo) else { return }
        deliver(info)
    }

    @objc nonisolated private func spotifyChanged(_ note: Notification) {
        guard let info = PlayerNotificationInfo.spotify(note.userInfo) else { return }
        deliver(info)
    }

    nonisolated private func deliver(_ info: PlayerNotificationInfo) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                // Any app can post these: only one from a player that's really running counts.
                guard let self, self.isWatching, ScriptedPlayers.isRunning(info.bundleID) else { return }
                self.onInfo?(info)
            }
        }
    }
}
