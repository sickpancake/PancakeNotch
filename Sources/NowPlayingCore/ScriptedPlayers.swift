import AppKit
import os

/// What a player said when asked with AppleScript.
struct ScriptedPlayerState: Equatable, Sendable {
    var state: PlayerNotificationInfo.State
    var title = ""
    var artist = ""
    var album = ""
    var duration: TimeInterval?
    var position: TimeInterval?
    var shuffle: ShuffleMode?
    var repeatMode: RepeatMode?
    /// Spotify only: the current item is an ad.
    var isAdvertisement = false
}

/// The AppleScript we send to Music and Spotify. Every script first checks the app is running:
/// `tell application` would launch it otherwise.
enum PlayerScripts {
    static func wrap(_ bundleID: String, _ body: String) -> String {
        """
        if application id "\(bundleID)" is running then
        tell application id "\(bundleID)"
        \(body)
        end tell
        end if
        """
    }

    /// Returns `{"stopped"}` or `{state, name, artist, album, duration (s), position (s), shuffle, repeat}`,
    /// and for Spotify also `address, popularity, track number` (to tell ads apart, see `SpotifyAd`).
    static func state(for bundleID: String) -> String {
        let body = bundleID == PlayerNotificationInfo.spotifyBundleID
            ? """
            if player state is stopped then return {"stopped"}
            set s to "paused"
            if player state is playing then set s to "playing"
            set t to current track
            set sm to "off"
            if shuffling then set sm to "tracks"
            set r to "off"
            if repeating then set r to "playlist"
            set u to ""
            try
            set u to spotify url of t
            end try
            set p to -1
            try
            set p to popularity of t
            end try
            set n to -1
            try
            set n to track number of t
            end try
            return {s, name of t, artist of t, album of t, (duration of t) / 1000, player position, sm, r, u, p, n}
            """
            : """
            if player state is stopped then return {"stopped"}
            set s to "paused"
            if player state is playing or player state is fast forwarding or player state is rewinding then set s to "playing"
            set t to current track
            set sm to "off"
            if shuffle enabled then
            if shuffle mode is albums then
            set sm to "albums"
            else
            set sm to "tracks"
            end if
            end if
            set r to "off"
            if song repeat is one then
            set r to "track"
            else if song repeat is all then
            set r to "playlist"
            end if
            return {s, name of t, artist of t, album of t, duration of t, player position, sm, r}
            """
        return wrap(bundleID, body) + "\nreturn {\"stopped\"}"
    }

    /// Music only: the current song's artwork bytes, or missing value.
    static let musicArtwork = wrap(PlayerNotificationInfo.musicBundleID, """
        if (count of artworks of current track) is 0 then return missing value
        return raw data of artwork 1 of current track
        """) + "\nreturn missing value"

    static func command(_ command: NowPlayingCommand, bundleID: String) -> String {
        let spotify = bundleID == PlayerNotificationInfo.spotifyBundleID
        let body: String = switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        case .seek(let seconds):
            // String(format:) always writes a dot, which is what AppleScript expects.
            "set player position to \(String(format: "%.2f", max(0, seconds)))"
        case .setShuffle(let mode):
            if spotify {
                "set shuffling to \(mode != .off)"
            } else if mode == .off {
                "set shuffle enabled to false"
            } else {
                "set shuffle mode to \(mode == .albums ? "albums" : "songs")\nset shuffle enabled to true"
            }
        case .setRepeat(let mode):
            if spotify {
                "set repeating to \(mode != .off)"
            } else {
                "set song repeat to \(mode == .off ? "off" : mode == .track ? "one" : "all")"
            }
        }
        return wrap(bundleID, body)
    }

    /// Reads the list `state(for:)` returns.
    static func parseState(_ descriptor: NSAppleEventDescriptor) -> ScriptedPlayerState? {
        let items = descriptor.listItems
        guard let first = items.first?.stringValue else { return nil }
        guard first != "stopped", items.count >= 8 else { return ScriptedPlayerState(state: .stopped) }
        func text(_ index: Int) -> String { items[index].nonMissing?.stringValue ?? "" }
        func number(_ index: Int) -> Double? { items[index].nonMissing.map(\.doubleValue) }
        func whole(_ index: Int) -> Int? { number(index).flatMap { $0 < 0 ? nil : Int(exactly: $0) } }
        let isAd = items.count >= 11 && SpotifyAd.isAd(address: text(8), popularity: whole(9), trackNumber: whole(10))
        return ScriptedPlayerState(
            state: first == "playing" ? .playing : .paused,
            title: text(1),
            artist: text(2),
            album: text(3),
            duration: number(4).flatMap { $0 > 0 ? $0 : nil },
            position: number(5).map { max(0, $0) },
            shuffle: shuffleMode(text(6)),
            repeatMode: repeatMode(text(7)),
            isAdvertisement: isAd
        )
    }

    static func shuffleMode(_ text: String) -> ShuffleMode? {
        switch text {
        case "off": .off
        case "albums": .albums
        case "tracks": .tracks
        default: nil
        }
    }

    static func repeatMode(_ text: String) -> RepeatMode? {
        switch text {
        case "off": .off
        case "track": .track
        case "playlist": .playlist
        default: nil
        }
    }
}

/// A picture made on the script queue and handed to the main thread once.
private struct ArtworkBox: @unchecked Sendable {
    let image: NSImage
}

/// The fallback when the helper doesn't work (ADR-0012): Music and Spotify only, from their announcements
/// plus AppleScript (position, shuffle/repeat, controls, and Music's artwork). Spotify's artwork is a
/// web address, which we never fetch (no network, ADR-0016).
///
/// Doesn't listen by itself: `CompositeBackend` forwards the announcements with `handle(_:)`.
@MainActor
final class ScriptedPlayers {
    static let bundleIDs = [PlayerNotificationInfo.musicBundleID, PlayerNotificationInfo.spotifyBundleID]

    var onUpdate: ((NowPlayingUpdate) -> Void)?
    var onAutomationPermissionChange: ((Bool) -> Void)?
    private(set) var needsAutomationPermission = false

    private struct Entry {
        var track: NowPlayingTrack
        var artwork: NSImage?
        /// The song whose artwork we already asked for (so a song without artwork isn't asked again).
        var artworkChecked: String?
    }

    private let runner = AppleScriptRunner()
    private var entries: [String: Entry] = [:]
    /// Players by when they last changed, most recent first.
    private var recent: [String] = []
    /// Bumped per player on every request, so late answers to old questions are dropped.
    private var tokens: [String: Int] = [:]
    private var isActive = false
    private let now: () -> Date
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "nowplaying")

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Music or Spotify is installed (Music always is, unless removed by hand).
    static var isAvailable: Bool {
        bundleIDs.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        publish()
        for bundleID in Self.bundleIDs where Self.isRunning(bundleID) {
            runner.checkPermission(for: bundleID) { [weak self] allowed in
                if allowed == false { self?.setNeedsPermission(true) }
            }
            refresh(bundleID)
        }
    }

    func stop() {
        isActive = false
        entries = [:]
        recent = []
        // Asked again on the next start: a stale "denied" would hide a later denial (the guard in
        // setNeedsPermission) and leave "Allow Control…" missing.
        setNeedsPermission(false)
        // Tokens keep counting, so answers to questions asked before a restart are still dropped.
    }

    /// Music or Spotify announced a change.
    func handle(_ info: PlayerNotificationInfo) {
        guard isActive else { return }
        let bundleID = info.bundleID
        let previous = entries[bundleID]
        if let track = info.track(previous: previous?.track, at: now()) {
            let sameSong = previous?.track.identity == track.identity
            entries[bundleID] = Entry(track: track, artwork: sameSong ? previous?.artwork : nil,
                                      artworkChecked: sameSong ? previous?.artworkChecked : nil)
            touch(bundleID)
            publish()
            refresh(bundleID)
        } else {
            remove(bundleID)
        }
    }

    func playerQuit(_ bundleID: String) {
        remove(bundleID)
    }

    func send(_ command: NowPlayingCommand) {
        guard let bundleID = current?.track.bundleID else { return }
        send(command, to: bundleID)
    }

    // MARK: Private

    /// The track to show: the most recent player that's playing, else the most recently changed one.
    private var current: Entry? {
        let playing = recent.first { entries[$0]?.track.isPlaying == true }
        return (playing ?? recent.first).flatMap { entries[$0] }
    }

    private func publish() {
        guard isActive else { return }
        let entry = current
        onUpdate?(NowPlayingUpdate(track: entry?.track, artwork: entry?.artwork))
    }

    private func touch(_ bundleID: String) {
        recent.removeAll { $0 == bundleID }
        recent.insert(bundleID, at: 0)
    }

    private func remove(_ bundleID: String) {
        guard entries[bundleID] != nil else { return }
        entries[bundleID] = nil
        recent.removeAll { $0 == bundleID }
        tokens[bundleID, default: 0] += 1
        publish()
    }

    private func send(_ command: NowPlayingCommand, to bundleID: String) {
        guard Self.isRunning(bundleID) else { return }
        // The command and the refresh after it run in order on the script queue.
        runner.run(PlayerScripts.command(command, bundleID: bundleID)) { [weak self] result in
            self?.noteResult(result)
        }
        refresh(bundleID)
    }

    /// Asks the player where it is (position, modes); fetches Music's artwork for a new song.
    private func refresh(_ bundleID: String) {
        guard isActive, Self.isRunning(bundleID) else { return }
        tokens[bundleID, default: 0] += 1
        let token = tokens[bundleID]
        runner.run(PlayerScripts.state(for: bundleID), parse: PlayerScripts.parseState) { [weak self] result in
            guard let self, self.isActive, self.tokens[bundleID] == token else { return }
            self.noteResult(result.map { _ in () })
            guard case .success(let state?) = result else { return }
            self.apply(state, from: bundleID)
        }
    }

    private func apply(_ state: ScriptedPlayerState, from bundleID: String) {
        guard state.state != .stopped, !state.title.isEmpty else {
            remove(bundleID)
            return
        }
        let date = now()
        let previous = entries[bundleID]
        var track = NowPlayingTrack(
            title: state.title, artist: state.artist, album: state.album, duration: state.duration,
            elapsed: 0, elapsedDate: date, isPlaying: state.state == .playing, bundleID: bundleID,
            shuffle: state.shuffle, repeatMode: state.repeatMode, isAdvertisement: state.isAdvertisement
        )
        let sameSong = previous?.track.identity == track.identity
        // Spotify's announcement may have said "ad" already.
        if sameSong, previous?.track.isAdvertisement == true { track.isAdvertisement = true }
        if let position = state.position {
            track.elapsed = position
        } else if let previous, sameSong {
            track.elapsed = previous.track.elapsed(at: date)
        }
        if sameSong { track.artworkID = previous?.track.artworkID }
        var entry = Entry(track: track, artwork: sameSong ? previous?.artwork : nil,
                          artworkChecked: sameSong ? previous?.artworkChecked : nil)
        let needsArtwork = bundleID == PlayerNotificationInfo.musicBundleID && entry.artworkChecked != track.identity
        if needsArtwork { entry.artworkChecked = track.identity }
        entries[bundleID] = entry
        if previous == nil { touch(bundleID) }
        publish()
        if needsArtwork { fetchMusicArtwork(for: track.identity) }
    }

    private func fetchMusicArtwork(for identity: String) {
        let bundleID = PlayerNotificationInfo.musicBundleID
        runner.run(PlayerScripts.musicArtwork, parse: { descriptor -> ArtworkBox? in
            guard let data = descriptor.nonMissing?.data, let image = ArtworkImage.downsample(data) else { return nil }
            return ArtworkBox(image: image)
        }) { [weak self] result in
            guard let self, self.isActive, var entry = self.entries[bundleID], entry.track.identity == identity,
                  case .success(let box?) = result
            else { return }
            entry.artwork = box.image
            entry.track.artworkID = ArtworkImage.id(for: identity, count: 0)
            self.entries[bundleID] = entry
            self.publish()
        }
    }

    private func noteResult(_ result: Result<Void, ScriptFailure>) {
        switch result {
        case .success: setNeedsPermission(false)
        case .failure(.notPermitted): setNeedsPermission(true)
        case .failure(.failed(let code)): logger.info("A player script failed (\(code))")
        }
    }

    private func setNeedsPermission(_ value: Bool) {
        guard needsAutomationPermission != value else { return }
        needsAutomationPermission = value
        onAutomationPermissionChange?(value)
    }
}
