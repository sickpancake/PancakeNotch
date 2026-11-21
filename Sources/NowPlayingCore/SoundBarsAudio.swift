import AppKit
import CoreAudio
import Observation
import os

/// One set of sound bars asking about the playing app's sound: is it making sound right now, and (for
/// "Follow the music") how loud is it. Several bars showing the same app share one watcher and one tap.
@MainActor
public final class SoundBarsLink {
    public enum Hearing: Equatable, Sendable {
        /// Not listening.
        case off
        /// Just started listening: nothing heard yet.
        case waiting
        /// Sound is coming through: the bars follow it.
        case hearing
        /// Nothing heard (yet, or not allowed): the bars use gentle motion meanwhile.
        case notHearing
        /// This app's sound can't be listened to: gentle motion for it.
        case unavailable
    }

    /// Whether the app is making sound; nil = can't tell (then the bars go by "playing").
    public private(set) var isRunningOutput: Bool?
    public private(set) var hearing: Hearing = .off
    /// `isRunningOutput` or `hearing` changed.
    public var onChange: (() -> Void)?
    /// The latest levels, about 30 times a second while levels are wanted.
    public var onLevels: ((SoundLevels) -> Void)?

    public private(set) var source: SoundSourceID?
    public private(set) var wantsLevels = false
    /// Where "allowed" or "not allowed" is remembered (the user's settings).
    private(set) weak var settings: NowPlayingSettings?
    private let audio: SoundBarsAudio

    init(audio: SoundBarsAudio) {
        self.audio = audio
    }

    /// Watches `source` (nil = nothing), and listens to its sound too when `wantsLevels`.
    public func follow(_ source: SoundSourceID?, wantsLevels: Bool, settings: NowPlayingSettings?) {
        let wantsLevels = source != nil && wantsLevels
        guard source != self.source || wantsLevels != self.wantsLevels || settings !== self.settings else { return }
        let old = self.source
        self.source = source
        self.wantsLevels = wantsLevels
        self.settings = settings
        if source != old { set(isRunningOutput: nil, hearing: .off, notify: false) }
        audio.linkChanged(self, from: old)
    }

    /// Stops watching and listening.
    public func cancel() {
        follow(nil, wantsLevels: false, settings: nil)
    }

    func set(isRunningOutput: Bool?, hearing: Hearing, notify: Bool = true) {
        guard isRunningOutput != self.isRunningOutput || hearing != self.hearing else { return }
        self.isRunningOutput = isRunningOutput
        self.hearing = hearing
        if notify { onChange?() }
    }
}

/// Runs the sound bars' listening (ADR-0032 amendment): a watcher on the playing app's "making sound"
/// switch while bars show it, and a Core Audio tap while bars follow the music. Everything stops as
/// soon as no bars need it, while the displays sleep, and when the app quits.
///
/// The only repeating work: while a tap runs, a 30-per-second timer hands its levels to the bars. It
/// is created with the tap and cancelled with it.
@MainActor
@Observable
public final class SoundBarsAudio {
    public static let shared = SoundBarsAudio()

    /// A permission check started from the settings is listening right now.
    public private(set) var isChecking = false
    /// The last check couldn't listen to the playing app at all (not a permission problem).
    public private(set) var checkCouldNotListen = false

    @ObservationIgnored private var feeds: [SoundSourceID: Feed] = [:]
    @ObservationIgnored private var screensAsleep = false
    @ObservationIgnored private var checkLink: SoundBarsLink?
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// How long a permission check listens at most.
    static let checkDuration: Duration = .seconds(20)

    private init() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            (workspace, workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SoundBarsAudio.shared.setScreensAsleep(true) }
            }),
            (workspace, workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SoundBarsAudio.shared.setScreensAsleep(false) }
            }),
            (NotificationCenter.default, NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { SoundBarsAudio.shared.stopEverything() }
            }),
        ]
    }

    public func makeLink() -> SoundBarsLink {
        SoundBarsLink(audio: self)
    }

    /// Asks macOS for the permission right away by listening for a moment to what's playing, so the
    /// question shows up while the user is looking at the setting. Returns false when there's nothing
    /// to listen to (then macOS asks the first time the bars follow a song).
    @discardableResult
    public func checkAccess(track: NowPlayingTrack?, isPractice: Bool, settings: NowPlayingSettings) -> Bool {
        endCheck()
        checkCouldNotListen = false
        guard !isPractice, let track, track.isPlaying, let source = SoundSourceID(track: track) else { return false }
        let link = makeLink()
        link.onChange = { [weak self, weak link, weak settings] in
            guard let self, let link else { return }
            switch link.hearing {
            case .hearing:
                self.endCheck()
            case .unavailable:
                self.checkCouldNotListen = true
                self.endCheck()
            default:
                if settings?.soundBarsAccess == .denied { self.endCheck() }
            }
        }
        checkLink = link
        isChecking = true
        link.follow(source, wantsLevels: true, settings: settings)
        checkTask = Task { [weak self] in
            try? await Task.sleep(for: Self.checkDuration)
            guard !Task.isCancelled else { return }
            self?.endCheck()
        }
        return true
    }

    /// Stops a permission check early (the setting changed).
    public func endCheck() {
        checkTask?.cancel()
        checkTask = nil
        if let link = checkLink {
            checkLink = nil
            link.onChange = nil
            link.cancel()
        }
        if isChecking { isChecking = false }
    }

    // MARK: Feeds

    func linkChanged(_ link: SoundBarsLink, from old: SoundSourceID?) {
        if let old, old != link.source, let feed = feeds[old] {
            feed.remove(link)
            reconcile(feed)
        }
        if let source = link.source {
            let feed = feeds[source] ?? {
                let feed = Feed(source: source)
                feeds[source] = feed
                return feed
            }()
            feed.add(link)
            reconcile(feed)
        }
    }

    private func reconcile(_ feed: Feed) {
        feed.reconcile(screensAsleep: screensAsleep)
        if feed.isEmpty { feeds[feed.source] = nil }
    }

    private func setScreensAsleep(_ asleep: Bool) {
        guard asleep != screensAsleep else { return }
        screensAsleep = asleep
        for feed in Array(feeds.values) { reconcile(feed) }
    }

    private func stopEverything() {
        endCheck()
        for feed in feeds.values { feed.shutDown(waiting: true) }
        feeds = [:]
    }
}

/// Everything about one app's sound: its watcher, its tap while one is wanted, and what was heard.
@MainActor
private final class Feed {
    let source: SoundSourceID
    private var links: [WeakLink] = []
    private let watcher: AudioOutputWatcher
    private var isWatching = false
    private var meter: AudioLevelMeter?
    private var timer: DispatchSourceTimer?
    private var probe = AccessProbe()
    private var startedAt = Date()
    private var lastRestart = Date()
    private var lastAudioSeconds: TimeInterval = 0
    private var lastAudioChange = Date()
    private var hearing: SoundBarsLink.Hearing = .off
    /// This app's sound can't be listened to (until its processes change).
    private var isUnavailable = false
    private var screensAsleep = false
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "soundbars")

    private struct WeakLink {
        weak var link: SoundBarsLink?
    }

    init(source: SoundSourceID) {
        self.source = source
        watcher = AudioOutputWatcher(source: source)
    }

    var isEmpty: Bool { liveLinks.isEmpty }

    private var liveLinks: [SoundBarsLink] {
        links.compactMap(\.link).filter { $0.source == source }
    }

    private var settings: NowPlayingSettings? {
        liveLinks.lazy.compactMap(\.settings).first
    }

    func add(_ link: SoundBarsLink) {
        if !links.contains(where: { $0.link === link }) { links.append(WeakLink(link: link)) }
    }

    func remove(_ link: SoundBarsLink) {
        links.removeAll { $0.link == nil || $0.link === link }
    }

    func reconcile(screensAsleep: Bool) {
        self.screensAsleep = screensAsleep
        links.removeAll { $0.link == nil || $0.link?.source != source }
        guard !links.isEmpty else {
            shutDown(waiting: false)
            return
        }
        if !isWatching {
            isWatching = true
            watcher.onChange = { [weak self] tapChanged in self?.watcherChanged(tapChanged: tapChanged) }
            watcher.start()
        }
        let access = settings?.soundBarsAccess ?? .unknown
        let wantsLevels = !screensAsleep && !isUnavailable && access != .denied && liveLinks.contains(where: \.wantsLevels)
        if wantsLevels, meter == nil {
            startMeter(fresh: true)
        } else if !wantsLevels, meter != nil {
            stopMeter()
        }
        publish()
    }

    func shutDown(waiting: Bool) {
        if let meter {
            if waiting { meter.stopNow() } else { meter.stop() }
        }
        meter = nil
        timer?.cancel()
        timer = nil
        hearing = .off
        if isWatching {
            watcher.stop()
            isWatching = false
        }
        for link in links.compactMap(\.link) where link.source == source {
            link.set(isRunningOutput: nil, hearing: .off)
        }
        links = []
    }

    // MARK: The tap

    private func startMeter(fresh: Bool) {
        meter?.stop()
        meter = nil
        let processes = watcher.tapped
        guard !processes.isEmpty else {
            markUnavailable("no process of the playing app uses sound")
            return
        }
        let meter = AudioLevelMeter()
        meter.start(processes: processes)
        self.meter = meter
        let now = Date()
        if fresh {
            probe = AccessProbe()
            startedAt = now
            hearing = .waiting
            logger.debug("Sound bars listening to \(processes.count) process(es)")
        } else {
            probe.meterRestarted()
        }
        lastRestart = now
        lastAudioSeconds = 0
        lastAudioChange = now
        if timer == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + .milliseconds(33), repeating: .milliseconds(33), leeway: .milliseconds(8))
            timer.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.resume()
            self.timer = timer
        }
    }

    private func stopMeter() {
        meter?.stop()
        meter = nil
        timer?.cancel()
        timer = nil
        if hearing != .unavailable { hearing = .off }
        logger.debug("Sound bars stopped listening")
    }

    private func markUnavailable(_ reason: String) {
        if !isUnavailable {
            logger.notice("Sound bars can't listen to the playing app (\(reason, privacy: .public)); using gentle motion for it.")
        }
        isUnavailable = true
        stopMeter()
        hearing = .unavailable
        publish()
    }

    private func tick() {
        guard let meter else { return }
        let reading = meter.reading
        if reading.failed {
            markUnavailable("setting up the tap failed")
            return
        }
        let now = Date()
        if reading.audioSeconds != lastAudioSeconds {
            lastAudioSeconds = reading.audioSeconds
            lastAudioChange = now
        }
        let verdict = probe.update(
            heardSound: reading.heardSound,
            audioSeconds: reading.audioSeconds,
            elapsed: now.timeIntervalSince(startedAt),
            isOutputRunning: watcher.isRunningOutput
        )
        switch verdict {
        case .waiting:
            hearing = .waiting
        case .notHearing:
            hearing = .notHearing
        case .retry:
            hearing = .notHearing
            startMeter(fresh: false)
        case .denied:
            logger.notice("Sound bars heard only silence while the app played: System Audio Recording is off. Using gentle motion.")
            hearing = .notHearing
            stopMeter()
            // Remembered until the user presses Try Again; every bar showing it switches to gentle motion.
            settings?.soundBarsAccess = .denied
            publish()
            return
        case .hearing:
            if let settings, settings.soundBarsAccess != .allowed { settings.soundBarsAccess = .allowed }
            // Sound stopped coming although the app plays (e.g. the output device went away): gentle
            // motion meanwhile, and a fresh tap now and then.
            if now.timeIntervalSince(lastAudioChange) > 1.5, watcher.isRunningOutput != false {
                hearing = .notHearing
                if now.timeIntervalSince(lastRestart) > 5 { startMeter(fresh: false) }
            } else {
                hearing = .hearing
            }
        }
        publish()
        guard hearing == .hearing || hearing == .waiting else { return }
        for link in liveLinks where link.wantsLevels {
            link.onLevels?(reading.levels)
        }
    }

    private func watcherChanged(tapChanged: Bool) {
        if tapChanged {
            if isUnavailable, !watcher.tapped.isEmpty {
                // The app's processes changed: worth another try.
                isUnavailable = false
                hearing = .off
                reconcile(screensAsleep: screensAsleep)
                return
            }
            if meter != nil { startMeter(fresh: false) }
        }
        publish()
    }

    private func publish() {
        let running = watcher.isRunningOutput
        for link in liveLinks {
            link.set(isRunningOutput: running, hearing: link.wantsLevels ? hearing : .off)
        }
    }
}
