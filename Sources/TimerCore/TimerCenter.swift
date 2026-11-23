import AppKit
import Foundation
import Observation

/// Something the user did with the timer or stopwatch, for a lesson's practice notch.
public enum TimerEvent: Sendable {
    case started, customStarted, paused, resumed, cancelled, finished, stopped, addedMinute, repeated
    case stopwatchStarted, stopwatchStopped, lapped, stopwatchReset
    case modeShown(TimerMode)
}

/// Timer or Stopwatch: the open notch's switch.
public enum TimerMode: String, CaseIterable, Sendable {
    case timer, stopwatch
}

/// The timer and the stopwatch, shared by the real notch and Home's live copy (ADR-0040). Saved after
/// every change, so both carry on after quitting. Several named timers (issue #70) and one stopwatch can
/// run at once.
///
/// No polling (AGENTS.md rule 2): one sleeping Task waits for the soonest timer's end. A timer that ends while
/// the Mac sleeps finishes on wake; a clock change (by hand or network time) checks it again. Each of
/// those asks `CountdownTimer.finishIfDue`, so the sound plays once (TimerAlarm.tla, RingsOnce).
@MainActor
@Observable
public final class TimerCenter {
    /// Every timer that runs, waits or shows Done, in the order they were started. Never an idle one.
    public private(set) var timers: [CountdownTimer]
    public private(set) var stopwatch: Stopwatch
    /// The most timers at once.
    public static let mostTimers = 10
    /// The mode used last; the open notch shows it when neither (or both) run.
    public var lastMode: TimerMode { didSet { defaults?.set(lastMode.rawValue, forKey: Keys.lastMode) } }
    /// The wheels' time, as last set or started (5 minutes at first).
    public var customSeconds: TimeInterval { didSet { defaults?.set(customSeconds, forKey: Keys.customSeconds) } }
    /// Timers that ran out while the app wasn't running (found at launch): Done without ringing.
    private var awayIDs: Set<UUID> = []
    /// Goes up each time the Mac woke or the clock changed. Things that follow the time on their own
    /// (the ring's animation) start from the new time when it changes.
    public private(set) var clockEpoch = 0

    /// A timer just finished: play the sound, open the notch. Called once per finish, per timer.
    @ObservationIgnored public var onFinish: ((CountdownTimer) -> Void)?
    /// Told about each thing the user does (a lesson's practice notch).
    @ObservationIgnored public var onEvent: ((TimerEvent) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let uptime: () -> TimeInterval
    /// The wall clock and the uptime clock read together while the stopwatch runs: a clock change shows as
    /// the two moving apart.
    @ObservationIgnored private var stopwatchAnchor: (wall: Date, uptime: TimeInterval)?
    @ObservationIgnored private var alarmTask: Task<Void, Never>?
    @ObservationIgnored private var activity: (any NSObjectProtocol)?
    @ObservationIgnored private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    /// - Parameters:
    ///   - defaults: where to keep it; `nil` keeps it in memory only (practice, tests, snapshots).
    ///   - now: the current time; injectable for tests.
    ///   - uptime: seconds on a clock that counts through sleep and ignores clock changes; injectable for tests.
    public init(defaults: UserDefaults? = nil, now: @escaping () -> Date = Date.init,
                uptime: @escaping () -> TimeInterval = { TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1e9 }) {
        self.defaults = defaults
        self.clock = now
        self.uptime = uptime
        let saved = defaults?.data(forKey: Keys.state).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        timers = (saved?.timers ?? saved?.timer.map { [$0] } ?? []).filter { !$0.isIdle }
        stopwatch = saved?.stopwatch ?? Stopwatch()
        lastMode = defaults?.string(forKey: Keys.lastMode).flatMap(TimerMode.init(rawValue:)) ?? .timer
        let custom = defaults?.object(forKey: Keys.customSeconds) as? NSNumber
        let seconds = custom?.doubleValue ?? .nan
        customSeconds = seconds.isFinite && seconds >= 0 ? min(seconds, CountdownTimer.longest) : 5 * 60
        // Ran out while the app was quit: Done, quietly (it isn't ringing for something long past).
        let launched = now()
        for index in timers.indices where timers[index].finishIfDue(now: launched) {
            awayIDs.insert(timers[index].id)
        }
        if !awayIDs.isEmpty { save() }
        anchorStopwatch()
        scheduleAlarm()
    }

    /// Follows wake and clock changes. The real center only; practice timers are short and on screen.
    public func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.timeMayHaveJumped() }
        }))
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.timeMayHaveJumped() }
        }))
        // A restored timer was scheduled before these observers existed; now it is the real center
        // and needs the same App Nap protection as one started in this session.
        scheduleAlarm()
    }

    public func stop() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
        endActivity()
    }

    public var now: Date { clock() }

    /// Something runs or waits: the module wants its ear.
    public var hasActivity: Bool { !timers.isEmpty || !stopwatch.isIdle }

    // MARK: Timers

    /// The timer the notch is about: the Done one waiting longest (Done alerts queue up, one at a time),
    /// else the one ending soonest, else the paused one with least left. Idle when there are none. The
    /// one-timer controls below act on it.
    public var timer: CountdownTimer { Self.ordered(timers, at: now).first ?? CountdownTimer() }

    /// Done first (oldest first), then running by end, then paused by time left: the open notch's list
    /// and the ear's pick.
    public var sortedTimers: [CountdownTimer] { Self.ordered(timers, at: now) }

    /// Timers showing Done, oldest first: the queue of Done alerts.
    public var doneTimers: [CountdownTimer] { sortedTimers.filter(\.isDone) }

    /// Room for another timer.
    public var canAddTimer: Bool { timers.count < Self.mostTimers }

    /// The focused timer ran out while the app was quit: it shows Done without ringing.
    public var finishedWhileAway: Bool { timer.isDone && awayIDs.contains(timer.id) }

    public func timer(id: UUID) -> CountdownTimer? { timers.first { $0.id == id } }

    static func ordered(_ timers: [CountdownTimer], at now: Date) -> [CountdownTimer] {
        func rank(_ timer: CountdownTimer) -> (Int, TimeInterval) {
            switch timer.phase {
            case .done(let endedAt): (0, endedAt.timeIntervalSinceReferenceDate)
            case .running(let end): (1, end.timeIntervalSinceReferenceDate)
            case .paused(let remaining): (2, remaining)
            case .idle: (3, 0)
            }
        }
        // Stable: equal ranks keep the order they were started.
        return timers.enumerated().sorted {
            let (a, b) = (rank($0.element), rank($1.element))
            return a != b ? a < b : $0.offset < $1.offset
        }.map(\.element)
    }

    /// Starts another timer beside any that run. A Done timer stays until it's stopped. Ignored once
    /// `mostTimers` are going. Returns the new timer's id.
    @discardableResult
    public func startTimer(seconds: TimeInterval, name: String = "") -> UUID? {
        guard canAddTimer else { return nil }
        var timer = CountdownTimer(name: TimerSettings.cleanName(name))
        timer.start(seconds, now: now)
        guard !timer.isIdle else { return nil }
        timers.append(timer)
        lastMode = .timer
        changed()
        onEvent?(.started)
        return timer.id
    }

    /// Starts the wheels' time and remembers it for next time.
    @discardableResult
    public func startCustom(seconds: TimeInterval, name: String = "") -> UUID? {
        guard seconds >= 1 else { return nil }
        customSeconds = min(seconds.rounded(), CountdownTimer.longest)
        let id = startTimer(seconds: customSeconds, name: name)
        if id != nil { onEvent?(.customStarted) }
        return id
    }

    public func pauseTimer() { pauseTimer(id: timer.id) }
    public func resumeTimer() { resumeTimer(id: timer.id) }
    public func cancelTimer() { cancelTimer(id: timer.id) }
    public func stopTimer() { stopTimer(id: timer.id) }
    public func addMinute() { addMinute(id: timer.id) }
    public func repeatTimer() { repeatTimer(id: timer.id) }

    public func pauseTimer(id: UUID) { update(id, .paused) { $0.pause(now: now) } }
    public func resumeTimer(id: UUID) { update(id, .resumed) { $0.resume(now: now) } }
    /// Cancel while running or paused: it leaves the list.
    public func cancelTimer(id: UUID) { update(id, .cancelled) { $0.cancel() } }
    /// Stop on a Done card: it leaves the list, and the next Done one (if any) shows.
    public func stopTimer(id: UUID) { update(id, .stopped) { $0.stop() } }
    /// +1 min while running or paused adds a minute; on a Done card it's a one-minute timer.
    public func addMinute(id: UUID) {
        update(id, .addedMinute) { timer in
            if timer.isDone { timer.addMinute(now: now) } else { timer.extend(by: 60) }
        }
    }
    public func repeatTimer(id: UUID) { update(id, .repeated) { $0.restart(now: now) } }

    private func update(_ id: UUID, _ event: TimerEvent, _ change: (inout CountdownTimer) -> Void) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let before = timers[index]
        change(&timers[index])
        guard timers[index] != before else { return }
        if !timers[index].isDone { awayIDs.remove(id) }
        if timers[index].isIdle { timers.remove(at: index) }
        changed(event)
    }

    // MARK: Stopwatch

    public func startStopwatch() { stopwatch.start(now: now); lastMode = .stopwatch; anchorStopwatch(); changed(.stopwatchStarted) }
    public func stopStopwatch() { stopwatch.stop(now: now); anchorStopwatch(); changed(.stopwatchStopped) }
    public func lap() { stopwatch.lap(now: now); changed(.lapped) }
    public func resetStopwatch() { stopwatch.reset(); anchorStopwatch(); changed(.stopwatchReset) }

    private func anchorStopwatch() {
        stopwatchAnchor = stopwatch.isRunning ? (now, uptime()) : nil
    }

    /// The wall clock moved (by hand, or network time after a wake): a running stopwatch keeps the time
    /// the uptime clock measured. Only for jumps seen while running; one made while the app was quit
    /// can't be told apart.
    private func correctStopwatch() {
        guard stopwatch.isRunning else { return }
        guard let anchor = stopwatchAnchor else { return anchorStopwatch() }
        let jump = now.timeIntervalSince(anchor.wall) - (uptime() - anchor.uptime)
        if abs(jump) >= 0.5 {
            stopwatch.clockJumped(by: jump)
            save()
        }
        anchorStopwatch()
    }

    // MARK: The alarm

    /// The Mac woke or the clock changed: a timer that's due finishes now, otherwise the alarm is set
    /// again for the end date on the new clock.
    public func timeMayHaveJumped() {
        clockEpoch += 1
        correctStopwatch()
        if !checkFinished() { scheduleAlarm() }
    }

    /// Finishes every timer whose end has come, each once, in the order they ended. Returns whether
    /// any finished now.
    @discardableResult
    func checkFinished() -> Bool {
        let checked = now
        var finished: [CountdownTimer] = []
        for index in timers.indices where timers[index].finishIfDue(now: checked) {
            finished.append(timers[index])
        }
        guard !finished.isEmpty else { return false }
        scheduleAlarm()
        save()
        for timer in finished.sorted(by: { ($0.endedAt ?? checked) < ($1.endedAt ?? checked) }) {
            onFinish?(timer)
            onEvent?(.finished)
        }
        return true
    }

    private func changed(_ event: TimerEvent? = nil) {
        save()
        scheduleAlarm()
        if let event { onEvent?(event) }
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    /// One Task sleeps until the end date. Task.sleep's clock counts sleep time, so after a long sleep it
    /// wakes at once. If the wall clock moved meanwhile, it sleeps again for what's left. While a real
    /// timer runs, App Nap is held off (the notch may be hidden), so the alarm isn't late.
    private func scheduleAlarm() {
        alarmTask?.cancel()
        alarmTask = nil
        guard timers.contains(where: \.isRunning) else { return endActivity() }
        // Only the real center (started): a practice timer is on screen, and it may be dropped mid-run.
        if activity == nil, !observers.isEmpty {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "A timer is running")
        }
        alarmTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let wait = self?.secondsLeft else { return }
                if wait <= 0 {
                    self?.checkFinished()
                    return
                }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private var secondsLeft: TimeInterval? {
        timers.compactMap(\.end).min().map { $0.timeIntervalSince(now) }
    }

    private func save() {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(Saved(timers: timers, stopwatch: stopwatch)) {
            defaults.set(data, forKey: Keys.state)
        }
    }

    /// `timer` is how saves looked before several timers; read, never written.
    private struct Saved: Codable {
        var timers: [CountdownTimer]?
        var timer: CountdownTimer?
        var stopwatch: Stopwatch

        init(timers: [CountdownTimer], stopwatch: Stopwatch) {
            self.timers = timers
            self.stopwatch = stopwatch
        }
    }

    enum Keys {
        static let state = "timer.state"
        static let lastMode = "timer.lastMode"
        static let customSeconds = "timer.customSeconds"
    }
}
