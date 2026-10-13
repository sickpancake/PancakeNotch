import Foundation

/// How the player shuffles. The numbers match what macOS reports (MediaRemote).
public enum ShuffleMode: Int, Sendable, CaseIterable {
    case off = 1, albums = 2, tracks = 3
}

/// How the player repeats. The numbers match what macOS reports (MediaRemote).
public enum RepeatMode: Int, Sendable, CaseIterable {
    case off = 1, track = 2, playlist = 3
}

/// The song (or video, podcast, …) that's playing or paused right now.
public struct NowPlayingTrack: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    /// The length in seconds; nil when unknown (e.g. a live stream).
    public var duration: TimeInterval?
    /// Seconds into the song at `elapsedDate`.
    public var elapsed: TimeInterval
    /// When `elapsed` was measured. While playing, the position moves on from here (see `elapsed(at:)`).
    public var elapsedDate: Date
    /// How fast it plays: 1 is normal speed. Greater than 0 while playing, 0 while paused.
    public var playbackRate: Double
    public var isPlaying: Bool
    /// The app to show and open: for music playing in a web page that's the browser, otherwise the player itself.
    public var bundleID: String?
    /// The app that actually reports the music (for a web page this can be a helper process of the browser).
    /// Usually the same as `bundleID`. The ignore list checks both.
    public var sourceBundleID: String?
    /// nil = the app doesn't say, so the shuffle button is hidden.
    public var shuffle: ShuffleMode?
    /// nil = the app doesn't say, so the repeat button is hidden.
    public var repeatMode: RepeatMode?
    /// Changes whenever the artwork changes; nil = no artwork.
    public var artworkID: String?
    /// The process that plays it, as macOS reports it (for a web page this can be a helper of the
    /// browser); nil when unknown. The sound bars listen to its sound.
    public var processID: Int32?
    /// An ad is playing (Next, Previous and moving the position are refused by the player).
    public var isAdvertisement: Bool
    /// The MediaRemote commands the player accepts right now (see `MediaCommand`); nil when unknown,
    /// which counts as "accepts everything".
    public var enabledCommands: Set<Int>?

    public init(
        title: String,
        artist: String = "",
        album: String = "",
        duration: TimeInterval? = nil,
        elapsed: TimeInterval = 0,
        elapsedDate: Date = Date(),
        playbackRate: Double? = nil,
        isPlaying: Bool = true,
        bundleID: String? = nil,
        sourceBundleID: String? = nil,
        shuffle: ShuffleMode? = nil,
        repeatMode: RepeatMode? = nil,
        artworkID: String? = nil,
        processID: Int32? = nil,
        isAdvertisement: Bool = false,
        enabledCommands: Set<Int>? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.elapsedDate = elapsedDate
        // Some apps say "playing" with a rate of 0: treat that as normal speed.
        let rate = playbackRate ?? (isPlaying ? 1 : 0)
        self.playbackRate = isPlaying ? (rate > 0 ? rate : 1) : 0
        self.isPlaying = isPlaying
        self.bundleID = bundleID
        self.sourceBundleID = sourceBundleID ?? bundleID
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.artworkID = artworkID
        self.processID = processID
        self.isAdvertisement = isAdvertisement
        self.enabledCommands = enabledCommands
    }

    /// Title, artist, album and app together: when this changes, a different song is on.
    public var identity: String {
        [title, artist, album, bundleID ?? ""].joined(separator: "\u{1F}")
    }

    /// Where the song is at `date`: moves on from `elapsed` while playing, kept between 0 and the length.
    public func elapsed(at date: Date) -> TimeInterval {
        var value = elapsed
        if isPlaying { value += date.timeIntervalSince(elapsedDate) * playbackRate }
        value = max(0, value)
        if let duration, duration > 0 { value = min(value, duration) }
        return value
    }

    /// The same track with its position measured again at `date` (keeps the clock arithmetic in one place).
    func reanchored(at date: Date) -> NowPlayingTrack {
        var copy = self
        copy.elapsed = elapsed(at: date)
        copy.elapsedDate = date
        return copy
    }
}

/// Where Now Playing gets its information from.
public enum NowPlayingConnection: Equatable, Sendable {
    /// Just started; the first answer hasn't arrived yet.
    case starting
    /// The helper works: every app that plays media is shown.
    case connected
    /// The helper doesn't work, so only Music and Spotify are shown (they're asked directly).
    case limited
    /// Nothing works. `reason` is short, localized text for the app window.
    case unavailable(reason: String)
    /// The pretend player of the lessons and the Modules page.
    case practice
}

/// What the player controls ask for.
public enum NowPlayingCommand: Equatable, Sendable {
    case play, pause, togglePlayPause, next, previous
    case seek(to: TimeInterval)
    case setShuffle(ShuffleMode)
    case setRepeat(RepeatMode)
}

/// One stretch of listening, reported when playback of a song stops (pause, song change, app quit, stop()).
public struct ListeningRecord: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var bundleID: String?
    /// When this stretch began playing.
    public var started: Date
    /// Wall-clock seconds actually playing.
    public var seconds: TimeInterval

    public init(title: String, artist: String, album: String, bundleID: String?, started: Date, seconds: TimeInterval) {
        self.title = title
        self.artist = artist
        self.album = album
        self.bundleID = bundleID
        self.started = started
        self.seconds = seconds
    }
}
