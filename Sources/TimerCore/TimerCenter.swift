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
/// every change, so both carry on after quitting. One timer and one stopwatch can run at once.
///
/// No polling (AGENTS.md rule 2): one sleeping Task waits for the timer's end. A timer that ends while
/// the Mac sleeps finishes on wake; a clock change (by hand or network time) checks it again. Each of
/// those asks `CountdownTimer.finishIfDue`, so the sound plays once (TimerAlarm.tla, RingsOnce).
@MainActor
@Observable
public final class TimerCenter {
    public private(set) var timer: CountdownTimer
    public private(set) var stopwatch: Stopwatch
    /// The mode used last; the open notch shows it when neither (or both) run.
    public var lastMode: TimerMode { didSet { defaults?.set(lastMode.rawValue, forKey: Keys.lastMode) } }
    /// The wheels' time: the last custom time used (5 minutes at first).
    public var customSeconds: TimeInterval { didSet { defaults?.set(customSeconds, forKey: Keys.customSeconds) } }
    /// The timer ran out while the app wasn't running (found at launch): it shows Done without ringing.
    public private(set) var finishedWhileAway = false

    /// A timer just finished: play the sound, open the notch. Called once per finish.
    @ObservationIgnored public var onFinish: (() -> Void)?
    /// Told about each thing the user does (a lesson's practice notch).
    @ObservationIgnored public var onEvent: ((TimerEvent) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var alarmTask: Task<Void, Never>?
    @ObservationIgnored private var activity: (any NSObjectProtocol)?
    @ObservationIgnored private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    /// - Parameters:
    ///   - defaults: where to keep it; `nil` keeps it in memory only (practice, tests, snapshots).
    ///   - now: the current time; injectable for tests.
    public init(defaults: UserDefaults? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.clock = now
        let saved = defaults?.data(forKey: Keys.state).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        timer = saved?.timer ?? CountdownTimer()
        stopwatch = saved?.stopwatch ?? Stopwatch()
        lastMode = defaults?.string(forKey: Keys.lastMode).flatMap(TimerMode.init(rawValue:)) ?? .timer
        let custom = defaults?.double(forKey: Keys.customSeconds) ?? 0
        customSeconds = custom >= 1 ? min(custom, CountdownTimer.longest) : 5 * 60
        // Ran out while the app was quit: Done, quietly (it isn't ringing for something long past).
        if timer.finishIfDue(now: now()) {
            finishedWhileAway = true
            save()
        }
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
    }

    public func stop() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
    }

    public var now: Date { clock() }

    /// Something runs or waits: the module wants its ear.
    public var hasActivity: Bool { !timer.isIdle || !stopwatch.isIdle }

    // MARK: Timer

    public func startTimer(seconds: TimeInterval) {
        guard timer.isIdle || timer.isDone else { return }
        timer.start(seconds, now: now)
        finishedWhileAway = false
        lastMode = .timer
        changed()
        onEvent?(.started)
    }

    /// Starts the wheels' time and remembers it for next time.
    public func startCustom(seconds: TimeInterval) {
        guard seconds >= 1 else { return }
        customSeconds = min(seconds.rounded(), CountdownTimer.longest)
        startTimer(seconds: customSeconds)
        onEvent?(.customStarted)
    }

    public func pauseTimer() { timer.pause(now: now); changed(.paused) }
    public func resumeTimer() { timer.resume(now: now); changed(.resumed) }
    public func cancelTimer() { timer.cancel(); changed(.cancelled) }
    public func stopTimer() { timer.stop(); finishedWhileAway = false; changed(.stopped) }
    public func addMinute() { timer.addMinute(now: now); finishedWhileAway = false; changed(.addedMinute) }
    public func repeatTimer() { timer.restart(now: now); finishedWhileAway = false; changed(.repeated) }

    // MARK: Stopwatch

    public func startStopwatch() { stopwatch.start(now: now); lastMode = .stopwatch; changed(.stopwatchStarted) }
    public func stopStopwatch() { stopwatch.stop(now: now); changed(.stopwatchStopped) }
    public func lap() { stopwatch.lap(now: now); changed(.lapped) }
    public func resetStopwatch() { stopwatch.reset(); changed(.stopwatchReset) }

    // MARK: The alarm

    /// The Mac woke or the clock changed: a timer that's due finishes now, otherwise the alarm is set
    /// again for the end date on the new clock.
    public func timeMayHaveJumped() {
        if !checkFinished() { scheduleAlarm() }
    }

    /// Finishes the timer if its end has come. Returns whether it finished now.
    @discardableResult
    func checkFinished() -> Bool {
        guard timer.finishIfDue(now: now) else { return false }
        scheduleAlarm()
        save()
        onFinish?()
        onEvent?(.finished)
        return true
    }

    private func changed(_ event: TimerEvent? = nil) {
        save()
        scheduleAlarm()
        if let event { onEvent?(event) }
    }

    /// One Task sleeps until the end date. Task.sleep's clock counts sleep time, so after a long sleep it
    /// wakes at once. If the wall clock moved meanwhile, it sleeps again for what's left. While a timer
    /// runs, App Nap is held off (the notch may be hidden), so the alarm isn't late; nothing else runs.
    private func scheduleAlarm() {
        alarmTask?.cancel()
        alarmTask = nil
        guard timer.isRunning else {
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            activity = nil
            return
        }
        if activity == nil {
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
        timer.end.map { $0.timeIntervalSince(now) }
    }

    private func save() {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(Saved(timer: timer, stopwatch: stopwatch)) {
            defaults.set(data, forKey: Keys.state)
        }
    }

    private struct Saved: Codable {
        var timer: CountdownTimer
        var stopwatch: Stopwatch
    }

    enum Keys {
        static let state = "timer.state"
        static let lastMode = "timer.lastMode"
        static let customSeconds = "timer.customSeconds"
    }
}
