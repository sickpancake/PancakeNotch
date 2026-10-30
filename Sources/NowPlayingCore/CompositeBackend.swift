import AppKit
import os

/// The real Now Playing source: the mediaremote-adapter helper (every app), and when that doesn't work,
/// Music and Spotify asked directly (ADR-0012). `FallbackPolicy` decides; this class carries it out.
@MainActor
final class CompositeBackend: NowPlayingBackend, NowPlayingAutomationReporting {
    /// After launching the helper, wait this long for something playing before believing "nothing plays"
    /// (its first line is often empty, right before the real data).
    static let startupGrace: TimeInterval = 1

    var onUpdate: ((NowPlayingUpdate) -> Void)?
    var onConnectionChange: ((NowPlayingConnection) -> Void)?
    var onAutomationPermissionChange: ((Bool) -> Void)?

    private let location: AdapterLocation?
    private let adapter = AdapterProcess()
    private let players: ScriptedPlayers
    private let watcher = PlayerNotificationWatcher()
    private var policy = FallbackPolicy()
    private var isRunning = false
    private var connection: NowPlayingConnection = .starting {
        didSet { if connection != oldValue { onConnectionChange?(connection) } }
    }
    /// True from launching the helper until it reports something playing or the grace period ends.
    private var awaitingFirstContent = false
    private var startupTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    /// Spotify's own announcement says when it plays an ad (its address starts with "spotify:ad:"),
    /// which the helper doesn't: the ad's title, added to the helper's reports. Needs no permission.
    /// Any app can post that announcement, so it only ever marks the song the helper reports from a
    /// running Spotify, and never changes anything else.
    private var spotifyAdTitle: String?
    /// The helper's last report as it came (to add or remove the ad mark when Spotify's word changes).
    private var lastAdapterUpdate: NowPlayingUpdate?
    private let now: () -> Date
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "nowplaying")

    init(location: AdapterLocation? = AdapterLocation.find(), now: @escaping () -> Date = Date.init) {
        self.location = location
        self.now = now
        players = ScriptedPlayers(now: now)

        adapter.onOutput = { [weak self] update in self?.adapterOutput(update) }
        adapter.onExit = { [weak self] _ in
            guard let self else { return }
            // Until it's back, nothing is known to play (no stale song dancing in the ears).
            self.startupTask?.cancel()
            self.awaitingFirstContent = false
            if self.isRunning, self.policy.source == .adapter { self.onUpdate?(NowPlayingUpdate(track: nil)) }
            self.perform(self.policy.handle(.adapterExited(at: self.now())))
        }
        players.onUpdate = { [weak self] update in
            guard let self, self.policy.source == .fallback else { return }
            self.onUpdate?(update)
        }
        players.onAutomationPermissionChange = { [weak self] needed in self?.onAutomationPermissionChange?(needed) }
        watcher.onInfo = { [weak self] info in self?.playerAnnounced(info) }
        watcher.onQuit = { [weak self] bundleID in self?.players.playerQuit(bundleID) }
    }

    var processID: pid_t? { policy.source == .adapter ? adapter.processID : nil }

    /// Starts over with the helper (also how "Try again" works).
    func start() {
        guard !isRunning else { return }
        isRunning = true
        connection = .starting
        onAutomationPermissionChange?(false)
        watcher.start()
        perform(policy.handle(.start))
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cancelTasks()
        awaitingFirstContent = false
        adapter.stop()
        players.stop()
        watcher.stop()
        spotifyAdTitle = nil
        lastAdapterUpdate = nil
    }

    func send(_ command: NowPlayingCommand) {
        switch policy.source {
        case .adapter:
            if let location { adapter.send(command, location: location) }
        case .fallback:
            players.send(command)
        }
    }

    // MARK: Private

    private func perform(_ action: FallbackPolicy.Action) {
        guard isRunning else { return }
        switch action {
        case .none:
            break
        case .startAdapter:
            launchAdapter()
        case .restartAdapter(let delay):
            logger.notice("Restarting the Now Playing helper in \(delay) s")
            restartTask?.cancel()
            restartTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, self.isRunning, self.policy.source == .adapter else { return }
                self.launchAdapter()
            }
        case .useFallback(let reason):
            useFallback(reason)
        case .scheduleSilenceCheck(let bundleID, let notifiedAt, let delay):
            silenceTask?.cancel()
            silenceTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.perform(self.policy.handle(.silenceCheck(bundleID: bundleID, notifiedAt: notifiedAt)))
            }
        }
    }

    private func launchAdapter() {
        guard let location else {
            perform(policy.handle(.adapterUnavailable))
            return
        }
        do {
            try adapter.launch(location)
        } catch {
            perform(policy.handle(.adapterUnavailable))
            return
        }
        awaitingFirstContent = true
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.startupGrace))
            guard !Task.isCancelled, let self, self.isRunning, self.awaitingFirstContent else { return }
            // Nothing arrived in time: nothing is playing.
            self.awaitingFirstContent = false
            self.connection = .connected
            self.onUpdate?(NowPlayingUpdate(track: nil))
        }
    }

    private func adapterOutput(_ update: NowPlayingUpdate) {
        guard isRunning, policy.source == .adapter else { return }
        _ = policy.handle(.adapterReported(update.track, at: now()))
        // Don't flash "nothing playing" for the empty line the helper often sends first.
        if awaitingFirstContent && update.track == nil { return }
        awaitingFirstContent = false
        startupTask?.cancel()
        connection = .connected
        lastAdapterUpdate = update
        onUpdate?(Self.marking(update, spotifyAdTitle: spotifyAdTitle))
    }

    /// The helper's report with Spotify's ad flagged when Spotify announced this title as an ad.
    static func marking(_ update: NowPlayingUpdate, spotifyAdTitle: String?) -> NowPlayingUpdate {
        guard var track = update.track, !track.isAdvertisement, let spotifyAdTitle, track.title == spotifyAdTitle,
              track.bundleID == ScriptablePlayers.spotify || track.sourceBundleID == ScriptablePlayers.spotify
        else { return update }
        track.isAdvertisement = true
        return NowPlayingUpdate(track: track, artwork: update.artwork)
    }

    /// Spotify announced a new item: remember whether it's an ad, and fix the shown song if that changes it.
    private func spotifyAnnounced(_ info: PlayerNotificationInfo) {
        let adTitle = SpotifyAd.isAdAddress(info.trackID) ? info.title : nil
        guard adTitle != spotifyAdTitle else { return }
        let before = lastAdapterUpdate.map { Self.marking($0, spotifyAdTitle: spotifyAdTitle) }
        spotifyAdTitle = adTitle
        guard let last = lastAdapterUpdate else { return }
        let after = Self.marking(last, spotifyAdTitle: adTitle)
        if after.track?.isAdvertisement != before?.track?.isAdvertisement { onUpdate?(after) }
    }

    /// Music or Spotify announced a change (the watcher drops announcements from a player that isn't running).
    private func playerAnnounced(_ info: PlayerNotificationInfo) {
        guard isRunning else { return }
        switch policy.source {
        case .adapter:
            if info.bundleID == ScriptablePlayers.spotify { spotifyAnnounced(info) }
            if info.state == .playing {
                perform(policy.handle(.playerStartedPlaying(bundleID: info.bundleID, at: now())))
            }
        case .fallback:
            players.handle(info)
        }
    }

    private func useFallback(_ reason: FallbackPolicy.Reason) {
        logger.notice("Now Playing helper not usable (\(String(describing: reason), privacy: .public)): asking Music and Spotify directly")
        cancelTasks()
        awaitingFirstContent = false
        adapter.stop()
        lastAdapterUpdate = nil
        onUpdate?(NowPlayingUpdate(track: nil))
        if ScriptedPlayers.isAvailable {
            connection = .limited
            players.start()
        } else {
            connection = .unavailable(reason: String(localized: "Can't see what's playing", comment: "Now Playing connection problem"))
        }
    }

    private func cancelTasks() {
        startupTask?.cancel()
        restartTask?.cancel()
        silenceTask?.cancel()
        startupTask = nil
        restartTask = nil
        silenceTask = nil
    }
}
