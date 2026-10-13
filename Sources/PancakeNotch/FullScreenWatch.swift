import AppKit
import NotchCore
import NowPlayingCore
import os

/// Hides the notch in full screen as the user chose (ADR-0030):
/// - **While watching**: while an app in the full-screen Space plays (Now Playing says so when it's that
///   app, else Core Audio hears it) and the user sits still. Music from a background app doesn't count;
///   scrolling or moving the pointer brings the notch back until the user has been still for a moment.
/// - **Always**: whenever the built-in display shows a full-screen app.
/// Apps on the hide list hide it completely, the shortcut included.
///
/// Event-driven: Space and app switches, Now Playing changes, Core Audio callbacks, and mouse monitors
/// that run only while a full-screen video hides the notch.
@MainActor
final class FullScreenWatch {
    /// A pause counts only after a moment, so scrubbing or the gap between videos doesn't flash the notch.
    static let pauseGrace: Duration = .seconds(3)
    /// How long the user sits still before the notch hides again.
    static let idleDelay: Duration = .seconds(5)

    private let preferences: Preferences
    private let nowPlaying: NowPlayingCenter
    private let notch: NotchWindowController
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "app")

    private var isFullScreen = false
    /// The apps in the full-screen Space, while "While watching" needs to know whether they play.
    private var apps: [SoundSourceID] = []
    private let sound = AppSoundWatcher()
    /// An app in the full-screen Space plays (a pause counts after `pauseGrace`).
    private var isPlaying = false
    private var pauseTask: Task<Void, Never>?
    private let activity = UserActivityWatcher()
    /// The user scrolled or moved the pointer less than `idleDelay` ago.
    private var isUserActive = false
    private var lastActivity = ContinuousClock.now
    private var idleTask: Task<Void, Never>?

    init(preferences: Preferences, nowPlaying: NowPlayingCenter, notch: NotchWindowController) {
        self.preferences = preferences
        self.nowPlaying = nowPlaying
        self.notch = notch
        sound.onChange = { [weak self] in self?.playingMayHaveChanged() }
        activity.onActivity = { [weak self] in self?.userActed() }
        observeNowPlaying()
    }

    /// Checks the Space again: call on Space, app, screen and setting changes.
    func update() {
        let hiding = preferences.fullScreenHiding
        var fullScreenApps: [pid_t]?
        if hiding != .never || !NotchSettings.appsHiddenInFullScreen.isEmpty, let screen = NSScreen.builtIn {
            fullScreenApps = FullScreenDetector.fullScreenApps(displayID: screen.displayID)
        }
        isFullScreen = fullScreenApps != nil
        apps = hiding == .whileWatching
            ? (fullScreenApps ?? []).compactMap { pid in
                SoundSourceID(processID: pid, bundleIDs: [NSRunningApplication(processIdentifier: pid)?.bundleIdentifier])
            }
            : []
        sound.watch(apps)
        playingMayHaveChanged()
    }

    /// Follows Now Playing (no polling: Observation).
    private func observeNowPlaying() {
        withObservationTracking {
            _ = nowPlaying.track
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeNowPlaying()
                self?.playingMayHaveChanged()
            }
        }
    }

    /// Whether an app in the full-screen Space plays right now. Now Playing knows best when the song is
    /// that app's (a pause shows at once); otherwise Core Audio tells whether the app makes sound.
    private var isPlayingNow: Bool {
        guard !apps.isEmpty else { return false }
        if let track = nowPlaying.track, apps.contains(where: { $0.plays(track) }) { return track.isPlaying }
        return sound.isMakingSound
    }

    private func playingMayHaveChanged() {
        if isPlayingNow {
            pauseTask?.cancel()
            pauseTask = nil
            isPlaying = true
        } else if apps.isEmpty {
            // Left full screen (or the setting changed): nothing to wait for.
            pauseTask?.cancel()
            pauseTask = nil
            isPlaying = false
        } else if isPlaying, pauseTask == nil {
            pauseTask = Task { [weak self] in
                try? await Task.sleep(for: Self.pauseGrace)
                guard !Task.isCancelled, let self else { return }
                self.pauseTask = nil
                self.isPlaying = false
                self.apply()
            }
        }
        apply()
    }

    private func userActed() {
        lastActivity = .now
        if !isUserActive {
            isUserActive = true
            apply()
        }
        guard idleTask == nil else { return }
        idleTask = Task { [weak self] in
            // Sleeps until `idleDelay` after the latest activity, however many came meanwhile.
            while !Task.isCancelled {
                guard let wake = self.map({ $0.lastActivity + Self.idleDelay }) else { return }
                guard ContinuousClock.now < wake else { break }
                try? await Task.sleep(until: wake, clock: .continuous)
            }
            guard let self, !Task.isCancelled else { return }
            self.idleTask = nil
            self.isUserActive = false
            self.apply()
        }
    }

    private func apply() {
        let hiding = preferences.fullScreenHiding
        // Scrolling and pointer moves matter only while a full-screen video could hide the notch.
        if hiding == .whileWatching, isFullScreen, isPlaying {
            activity.start()
        } else if activity.isRunning || isUserActive {
            activity.stop()
            idleTask?.cancel()
            idleTask = nil
            isUserActive = false
        }
        let hiddenApps = NotchSettings.appsHiddenInFullScreen
        let suppress = isFullScreen
            && NSWorkspace.shared.frontmostApplication?.bundleIdentifier.map(hiddenApps.contains) == true
        let hide = hiding.hides(isFullScreen: isFullScreen, isPlaying: isPlaying, isUserActive: isUserActive)
        if suppress != notch.isSuppressed || hide != notch.isHiddenForFullScreen {
            logger.info("Notch \(suppress ? "hidden for a listed full-screen app" : hide ? "hidden in full screen" : "shown", privacy: .public)")
        }
        notch.isSuppressed = suppress
        notch.isHiddenForFullScreen = hide
    }
}
