import AppKit
import Observation
import os

/// What's playing, for every Now Playing view (ADR-0012). One center serves several notches (the real
/// one and Home's live copy), so there's one helper process however many notches show it.
///
/// It applies the ignore list, remembers the last player (for "Resume") and the apps seen playing (for
/// the ignore list), updates the UI straight away when a button is pressed (the player confirms a moment
/// later), and measures listening time for the statistics.
@MainActor
@Observable
public final class NowPlayingCenter {
    public let settings: NowPlayingSettings
    /// nil = nothing playing (or only an ignored app).
    public private(set) var track: NowPlayingTrack?
    /// The current song's artwork, at most 256 px.
    public private(set) var artwork: NSImage?
    public private(set) var connection: NowPlayingConnection = .starting
    /// When the current song paused; nil while it plays.
    public private(set) var pausedSince: Date?
    /// The app to resume or open when nothing is playing.
    public private(set) var lastPlayerBundleID: String?
    /// Apps seen playing, most recent first (for the ignore list in the app window).
    public private(set) var seenApps: [String]
    /// The Music/Spotify fallback was refused the Automation permission.
    public private(set) var needsAutomationPermission = false
    public private(set) var isRunning = false

    /// A stretch of listening ended (statistics).
    @ObservationIgnored public var onListened: ((ListeningRecord) -> Void)?
    /// A different song started.
    @ObservationIgnored public var onSongChange: ((NowPlayingTrack) -> Void)?

    @ObservationIgnored private let backend: any NowPlayingBackend
    /// What the backend reports, before the ignore list.
    @ObservationIgnored private var reportedTrack: NowPlayingTrack?
    @ObservationIgnored private var reportedArtwork: NSImage?
    /// The player's own last word, before any button press was shown ahead of it.
    @ObservationIgnored private var confirmedTrack: NowPlayingTrack?
    /// After a button press: if the player says nothing within a moment, the press didn't take
    /// (failed, or another app is in charge) and what it last said shows again.
    @ObservationIgnored private var confirmTask: Task<Void, Never>?
    static let confirmTimeout: Duration = .milliseconds(1500)
    @ObservationIgnored private var listening = ListeningTracker()
    @ObservationIgnored private let now: () -> Date
    /// Run once on `stop()` (the practice player removes its throwaway settings).
    @ObservationIgnored private var cleanUp: (() -> Void)?
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "nowplaying")

    static let maxSeenApps = 12

    public init(settings: NowPlayingSettings, backend: any NowPlayingBackend, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.backend = backend
        self.now = now
        lastPlayerBundleID = settings.defaults.string(forKey: NowPlayingSettings.Keys.lastPlayer)
        seenApps = settings.defaults.stringArray(forKey: NowPlayingSettings.Keys.seenApps) ?? []
        backend.onUpdate = { [weak self] update in self?.receive(update) }
        backend.onConnectionChange = { [weak self] connection in
            guard let self, self.connection != connection else { return }
            self.connection = connection
        }
        if let reporting = backend as? NowPlayingAutomationReporting {
            reporting.onAutomationPermissionChange = { [weak self] needed in
                guard let self, self.needsAutomationPermission != needed else { return }
                self.needsAutomationPermission = needed
            }
        }
        observeIgnoreList()
    }

    /// Every app through the mediaremote-adapter helper, with Music and Spotify as the fallback.
    public static func live(settings: NowPlayingSettings) -> NowPlayingCenter {
        NowPlayingCenter(settings: settings, backend: CompositeBackend())
    }

    /// The pretend player for lessons and the Modules page, with throwaway settings of its own.
    public static func practice() -> NowPlayingCenter {
        let suite = "io.github.sickpancake.PancakeNotch.practice.nowPlaying.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? UserDefaults()
        let center = NowPlayingCenter(settings: NowPlayingSettings(defaults: defaults), backend: PracticePlayer())
        center.cleanUp = { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return center
    }

    /// A pretend song set up at once, with nothing running or scheduled, for off-screen snapshots.
    /// `empty` shows "Nothing playing".
    public static func practiceSnapshot(playing: Bool, elapsed: TimeInterval, empty: Bool = false) -> NowPlayingCenter {
        let settings = NowPlayingSettings(defaults: UserDefaults(suiteName: "io.github.sickpancake.PancakeNotch.snapshots.nowPlaying") ?? UserDefaults())
        let center = NowPlayingCenter(settings: settings, backend: SnapshotBackend())
        center.connection = .practice
        center.lastPlayerBundleID = nil
        guard !empty else { return center }
        let song = PracticePlayer.songs[0]
        let track = NowPlayingTrack(
            title: song.title, artist: song.artist, album: song.album, duration: song.duration,
            elapsed: elapsed, elapsedDate: Date(), isPlaying: playing, bundleID: PracticePlayer.bundleID,
            shuffle: .off, repeatMode: .off, artworkID: "practice-0"
        )
        center.reportedTrack = track
        center.confirmedTrack = track
        center.reportedArtwork = PracticeArtwork.image(for: 0)
        center.track = track
        center.artwork = center.reportedArtwork
        center.pausedSince = playing ? nil : Date()
        return center
    }

    /// The long-running helper's process (its memory counts towards ours), while there is one.
    public var helperProcessID: pid_t? { backend.processID }

    // MARK: Running

    /// Starts listening (idempotent). The app does this while Now Playing is switched on.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        if connection != .practice { connection = .starting }
        backend.start()
    }

    /// Stops the helper and ends the current listening stretch.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        confirmTask?.cancel()
        backend.stop()
        if let record = listening.flush(at: now()) { onListened?(record) }
        reportedTrack = nil
        confirmedTrack = nil
        reportedArtwork = nil
        if track != nil { track = nil }
        if artwork != nil { artwork = nil }
        pausedSince = nil
        cleanUp?()
        cleanUp = nil
    }

    /// Starts over with the helper ("Try Again").
    public func retryConnection() {
        guard isRunning else { return start() }
        backend.stop()
        connection = .starting
        backend.start()
    }

    // MARK: Controls

    /// Sends a command, showing its effect right away; the player's next report confirms (or corrects) it.
    public func send(_ command: NowPlayingCommand) {
        if var updated = reportedTrack {
            let date = now()
            switch command {
            case .play:
                updated = updated.reanchored(at: date)
                updated.isPlaying = true
                updated.playbackRate = 1
            case .pause:
                updated = updated.reanchored(at: date)
                updated.isPlaying = false
                updated.playbackRate = 0
            case .togglePlayPause:
                let playing = !updated.isPlaying
                updated = updated.reanchored(at: date)
                updated.isPlaying = playing
                updated.playbackRate = playing ? 1 : 0
            case .seek(let time):
                updated.elapsed = max(0, updated.duration.map { min(time, $0) } ?? time)
                updated.elapsedDate = date
            case .setShuffle(let mode):
                updated.shuffle = mode
            case .setRepeat(let mode):
                updated.repeatMode = mode
            case .next, .previous:
                break
            }
            reportedTrack = updated
            publish()
            expectConfirmation()
        }
        backend.send(command)
    }

    private func expectConfirmation() {
        confirmTask?.cancel()
        confirmTask = Task { [weak self] in
            try? await Task.sleep(for: Self.confirmTimeout)
            guard !Task.isCancelled, let self, self.isRunning else { return }
            self.reportedTrack = self.confirmedTrack
            self.publish()
        }
    }

    /// Nothing playing: start the app that played last (or whatever macOS plays next).
    public func resume() {
        if let resumable = backend as? NowPlayingResumable {
            resumable.resume(preferring: lastPlayerBundleID)
        } else {
            backend.send(.play)
        }
    }

    /// Brings the playing app (or the last one) to the front, launching it if needed.
    public func openPlayerApp() {
        guard connection != .practice else { return }
        openApp(track?.bundleID ?? lastPlayerBundleID ?? "com.apple.Music")
    }

    /// Brings an app to the front, launching it if needed. Goes through Launch Services like the Dock:
    /// macOS ignores `NSRunningApplication.activate()` from an app that isn't active itself, and the
    /// notch never is.
    public func openApp(_ bundleID: String) {
        guard connection != .practice else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        guard let url = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            logger.notice("No app found for \(bundleID, privacy: .public)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [logger] _, error in
            if let error { logger.notice("Couldn't open \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)") }
        }
    }

    // MARK: Reports from the backend

    private func receive(_ update: NowPlayingUpdate) {
        let previousArtworkID = reportedTrack?.artworkID
        if let artwork = update.artwork {
            reportedArtwork = artwork
        } else if update.track?.artworkID != previousArtworkID || update.track?.artworkID == nil {
            reportedArtwork = nil
        }
        confirmTask?.cancel()
        confirmTask = nil
        reportedTrack = update.track
        confirmedTrack = update.track
        if let track = update.track, !isIgnored(track), let bundleID = track.bundleID, connection != .practice {
            remember(bundleID)
        }
        publish()
    }

    /// Applies the ignore list and updates what the views see (only what changed, so they don't redraw
    /// for nothing).
    private func publish() {
        let visible = reportedTrack.flatMap { isIgnored($0) ? nil : $0 }
        let previous = track
        if let visible {
            if visible.isPlaying {
                if pausedSince != nil { pausedSince = nil }
            } else if pausedSince == nil || previous?.identity != visible.identity {
                // A paused song's position was measured when it paused.
                pausedSince = min(now(), visible.elapsedDate)
            }
        } else if pausedSince != nil {
            pausedSince = nil
        }
        if track != visible { track = visible }
        let newArtwork = visible == nil ? nil : reportedArtwork
        if artwork !== newArtwork { artwork = newArtwork }
        if let visible, visible.identity != previous?.identity { onSongChange?(visible) }
        if let record = listening.update(visible, at: now()) { onListened?(record) }
    }

    private func isIgnored(_ track: NowPlayingTrack) -> Bool {
        [track.bundleID, track.sourceBundleID].contains { $0.map(settings.isIgnored) ?? false }
    }

    /// The last player (for "Resume") and the apps seen playing (for the ignore list), kept on this Mac.
    private func remember(_ bundleID: String) {
        if lastPlayerBundleID != bundleID {
            lastPlayerBundleID = bundleID
            settings.defaults.set(bundleID, forKey: NowPlayingSettings.Keys.lastPlayer)
        }
        guard seenApps.first != bundleID else { return }
        seenApps = Array(([bundleID] + seenApps.filter { $0 != bundleID }).prefix(Self.maxSeenApps))
        settings.defaults.set(seenApps, forKey: NowPlayingSettings.Keys.seenApps)
    }

    /// Hides or shows the current song as soon as the ignore list changes. Observation only.
    private func observeIgnoreList() {
        withObservationTracking {
            _ = settings.ignoredApps
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.publish()
                self.observeIgnoreList()
            }
        }
    }
}

/// Does nothing: snapshots set the center's state directly.
@MainActor
private final class SnapshotBackend: NowPlayingBackend {
    var onUpdate: ((NowPlayingUpdate) -> Void)?
    var onConnectionChange: ((NowPlayingConnection) -> Void)?
    func start() {}
    func stop() {}
    func send(_ command: NowPlayingCommand) {}
    var processID: pid_t? { nil }
}
