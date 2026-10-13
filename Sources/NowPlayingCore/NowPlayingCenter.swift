import AppKit
import Observation
import os

/// What's playing, for every Now Playing view (ADR-0012). One center serves several notches (the real
/// one and Home's live copy), so there's one helper process however many notches show it.
///
/// It applies the ignore list, remembers the last player (for "Resume") and the apps seen playing (for
/// the ignore list), updates the UI straight away when a button is pressed (the player confirms a moment
/// later), and measures listening time for the statistics.
///
/// While the helper shows what's playing, it also asks Music and Spotify with AppleScript what the helper
/// can't see: their shuffle and repeat (when the notch opens or the song changes while it's open) and
/// whether Spotify plays an ad (when its song changes, only once the user allowed it). Never on a timer.
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
    /// Music or Spotify said no to being controlled (Automation permission), learned from a script that
    /// was refused or from asking macOS when the notch opens. Their shuffle, repeat and Resume are hidden.
    public private(set) var automationDeniedApps: Set<String> = []
    /// Shuffle and repeat read with AppleScript from Music or Spotify (by app), for when the helper
    /// doesn't report them.
    private(set) var scriptedModes: [String: ScriptedModes] = [:]

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
    /// AppleScript to Music and Spotify beside the helper; nil for the practice player and snapshots.
    @ObservationIgnored private let scripting: (any PlayerScripting)?
    /// AppleScript said this song (by identity) is an ad.
    @ObservationIgnored private var scriptedAdIdentity: String?
    /// The open notches showing Now Playing right now (the real one, Home's copy).
    @ObservationIgnored private var openViewers: Set<ObjectIdentifier> = []
    /// After changing shuffle or repeat by script: the one look a moment later that confirms it.
    @ObservationIgnored private var modeCheckTask: Task<Void, Never>?
    static let modeCheckDelay: Duration = .milliseconds(400)
    /// Whether an app is installed (replaceable in tests).
    @ObservationIgnored var isInstalled: (String) -> Bool = { InstalledApps.isInstalled($0) }

    static let maxSeenApps = 12

    public convenience init(settings: NowPlayingSettings, backend: any NowPlayingBackend, now: @escaping () -> Date = Date.init) {
        self.init(settings: settings, backend: backend, scripting: nil, now: now)
    }

    init(settings: NowPlayingSettings, backend: any NowPlayingBackend, scripting: (any PlayerScripting)?, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.backend = backend
        self.scripting = scripting
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
        NowPlayingCenter(settings: settings, backend: CompositeBackend(), scripting: AppleScriptPlayerScripting())
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
    /// `empty` shows "Nothing playing"; `ad` shows an ad (`artwork: false` without a picture).
    public static func practiceSnapshot(playing: Bool, elapsed: TimeInterval, empty: Bool = false,
                                        ad: Bool = false, artwork: Bool = true) -> NowPlayingCenter {
        let settings = NowPlayingSettings(defaults: UserDefaults(suiteName: "io.github.sickpancake.PancakeNotch.snapshots.nowPlaying") ?? UserDefaults())
        let center = NowPlayingCenter(settings: settings, backend: SnapshotBackend())
        center.connection = .practice
        center.lastPlayerBundleID = nil
        guard !empty else { return center }
        let song = PracticePlayer.songs[0]
        var track = NowPlayingTrack(
            title: song.title, artist: song.artist, album: song.album, duration: song.duration,
            elapsed: elapsed, elapsedDate: Date(), isPlaying: playing, bundleID: PracticePlayer.bundleID,
            shuffle: .off, repeatMode: .off, artworkID: artwork ? "practice-0" : nil
        )
        if ad {
            track.title = String(localized: "Advertisement", comment: "Snapshot: the title an ad shows")
            track.artist = ""
            track.album = ""
            track.duration = 30
            track.elapsed = min(elapsed, 12)
            track.isAdvertisement = true
        }
        center.reportedTrack = track
        center.confirmedTrack = track
        center.reportedArtwork = artwork ? PracticeArtwork.image(for: ad ? 2 : 0) : nil
        center.track = track
        center.artwork = center.reportedArtwork
        center.pausedSince = playing ? nil : Date()
        return center
    }

    /// "Nothing playing" in the real notch, with `lastPlayer` as the app played last and `seen` as the
    /// apps seen playing, for off-screen snapshots.
    public static func snapshotNothingPlaying(lastPlayer: String?, seen: [String]) -> NowPlayingCenter {
        let settings = NowPlayingSettings(defaults: UserDefaults(suiteName: "io.github.sickpancake.PancakeNotch.snapshots.nowPlaying") ?? UserDefaults())
        let center = NowPlayingCenter(settings: settings, backend: SnapshotBackend())
        center.connection = .connected
        center.lastPlayerBundleID = lastPlayer
        center.seenApps = seen
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
        scriptedAdIdentity = nil
        modeCheckTask?.cancel()
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

    /// What "Resume" does while nothing plays; nil = no Resume button.
    public var resumeOption: ResumeOption? {
        ResumeOption.resolve(lastPlayer: lastPlayerBundleID, connection: connection, deniedApps: automationDeniedApps,
                             isInstalled: isInstalled)
    }

    /// Nothing playing: the practice player plays again, or Music or Spotify (whichever played last) is
    /// told to play with AppleScript, launching it if needed. Never macOS's generic "play": with nothing
    /// playing that starts Apple Music whatever played last.
    public func resume() {
        switch resumeOption {
        case .practice:
            (backend as? NowPlayingResumable)?.resume(preferring: nil)
        case .app(let bundleID):
            guard let scripting else { return }
            scripting.play(bundleID) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.allowAutomation(bundleID)
                case .failure(.notPermitted):
                    self.denyAutomation(bundleID)
                case .failure(.failed(let code)):
                    // Couldn't start it: bring the app forward so the user can press play there.
                    self.logger.notice("Couldn't resume \(bundleID, privacy: .public) (\(code)): opening it")
                    self.openApp(bundleID)
                }
            }
        case .needsPermission, nil:
            break
        }
    }

    // MARK: Shuffle and repeat

    /// Which controls work right now for the song that's showing.
    public var abilities: PlayerAbilities {
        PlayerAbilities.resolve(track: track, connection: connection, scripted: track?.bundleID.flatMap { scriptedModes[$0] })
    }

    /// Turns shuffle on or off, through the helper or with AppleScript, whichever works for this app.
    public func setShuffle(_ mode: ShuffleMode) {
        switch abilities.shuffleRoute {
        case .player: send(.setShuffle(mode))
        case .script: changeScripted(.setShuffle(mode)) { $0.shuffle = mode }
        case nil: break
        }
    }

    /// Changes repeat, through the helper or with AppleScript, whichever works for this app.
    public func setRepeat(_ mode: RepeatMode) {
        switch abilities.repeatRoute {
        case .player: send(.setRepeat(mode))
        case .script: changeScripted(.setRepeat(mode)) { $0.repeatMode = mode }
        case nil: break
        }
    }

    /// Whether `bundleID` refused the Automation permission.
    public func isAutomationDenied(_ bundleID: String?) -> Bool {
        bundleID.map(automationDeniedApps.contains) ?? false
    }

    /// An open notch started showing Now Playing: look at Music's or Spotify's shuffle and repeat now
    /// (the first time, macOS asks the user for permission; this is when we ask).
    public func viewerOpened(_ viewer: AnyObject) {
        openViewers.insert(ObjectIdentifier(viewer))
        refreshScriptedState(mayAsk: true)
    }

    /// That notch closed (or moved to another module).
    public func viewerClosed(_ viewer: AnyObject) {
        openViewers.remove(ObjectIdentifier(viewer))
    }

    /// Shows the change straight away, sends it, and looks again a moment later: the player's answer
    /// confirms it, or puts back what's true. A refused or failed change goes back at once.
    private func changeScripted(_ command: NowPlayingCommand, change: (inout ScriptedModes) -> Void) {
        guard let scripting, let bundleID = track?.bundleID, let before = scriptedModes[bundleID] else { return }
        var after = before
        change(&after)
        scriptedModes[bundleID] = after
        modeCheckTask?.cancel()
        scripting.send(command, to: bundleID) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.modeCheckTask?.cancel()
                self.modeCheckTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.modeCheckDelay)
                    guard !Task.isCancelled else { return }
                    self?.readScripted(bundleID)
                }
            case .failure(.notPermitted):
                self.denyAutomation(bundleID)
            case .failure(.failed(let code)):
                self.logger.info("Couldn't change a mode in \(bundleID, privacy: .public) (\(code))")
                if self.scriptedModes[bundleID] == after { self.scriptedModes[bundleID] = before }
            }
        }
    }

    /// Asks Music or Spotify what the helper can't tell: shuffle, repeat, and whether an ad plays.
    /// `mayAsk`: an open notch shows Now Playing, so macOS may ask the user for permission. Otherwise it
    /// only runs once the user allowed it (Spotify's ad check while the notch is closed).
    private func refreshScriptedState(mayAsk: Bool) {
        guard let scripting, connection != .practice else { return }
        guard let track else {
            // Nothing playing: find out whether Resume can work, without asking.
            guard let lastPlayer = lastPlayerBundleID, ScriptablePlayers.contains(lastPlayer) else { return }
            scripting.permission(for: lastPlayer) { [weak self] allowed in
                if allowed == true { self?.allowAutomation(lastPlayer) }
                if allowed == false { self?.denyAutomation(lastPlayer) }
            }
            return
        }
        // The fallback reads Music and Spotify itself.
        guard connection == .connected, let bundleID = track.bundleID, ScriptablePlayers.contains(bundleID) else { return }
        // Music with shuffle and repeat from the helper: nothing more to learn (it has no ads).
        let helperAbilities = PlayerAbilities.resolve(track: track, connection: connection, scripted: nil)
        if bundleID == ScriptablePlayers.music, helperAbilities.shuffleRoute == .player, helperAbilities.repeatRoute == .player {
            return
        }
        scripting.permission(for: bundleID) { [weak self] allowed in
            guard let self else { return }
            switch allowed {
            case true?:
                self.readScripted(bundleID)
            case false?:
                self.denyAutomation(bundleID)
            case nil:
                // Not decided yet: ask only while the notch shows Now Playing.
                if mayAsk, !self.openViewers.isEmpty { self.readScripted(bundleID) }
            }
        }
    }

    private func readScripted(_ bundleID: String) {
        guard let scripting, track?.bundleID == bundleID else { return }
        let identity = track?.identity
        scripting.read(bundleID) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let reading?):
                self.allowAutomation(bundleID)
                if self.scriptedModes[bundleID] != reading.modes { self.scriptedModes[bundleID] = reading.modes }
                // Only for the song it was asked about (a newer song gets its own look).
                if let identity, self.track?.identity == identity {
                    let adIdentity = reading.isAdvertisement ? identity : nil
                    if self.scriptedAdIdentity != adIdentity {
                        self.scriptedAdIdentity = adIdentity
                        self.publish()
                    }
                }
            case .success(nil):
                break
            case .failure(.notPermitted):
                self.denyAutomation(bundleID)
            case .failure(.failed(let code)):
                self.logger.info("Couldn't read \(bundleID, privacy: .public) (\(code))")
            }
        }
    }

    private func allowAutomation(_ bundleID: String) {
        if automationDeniedApps.contains(bundleID) { automationDeniedApps.remove(bundleID) }
    }

    private func denyAutomation(_ bundleID: String) {
        if !automationDeniedApps.contains(bundleID) { automationDeniedApps.insert(bundleID) }
        if scriptedModes[bundleID] != nil { scriptedModes[bundleID] = nil }
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
        var visible = reportedTrack.flatMap { isIgnored($0) ? nil : $0 }
        // AppleScript found an ad the helper didn't flag.
        if let shown = visible, !shown.isAdvertisement, shown.identity == scriptedAdIdentity {
            visible?.isAdvertisement = true
        }
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
        if let visible, visible.identity != previous?.identity {
            onSongChange?(visible)
            songChanged(visible)
        }
        if let record = listening.update(visible, at: now()) { onListened?(record) }
    }

    /// A new song: look at its modes if a notch shows it, and check Spotify for an ad (without asking).
    private func songChanged(_ track: NowPlayingTrack) {
        let watching = !openViewers.isEmpty
        guard watching || track.bundleID == ScriptablePlayers.spotify else { return }
        refreshScriptedState(mayAsk: watching)
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
