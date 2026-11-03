import AppKit
import Foundation
import Observation

/// A session you started: until a time, or until you turn it off.
public struct KeepAwakeSession: Codable, Equatable, Sendable {
    public var start: Date
    /// `nil` keeps going until you turn it off.
    public var end: Date?
    /// When the Mac started up, so a session isn't carried on after a restart (unless the setting says so).
    public var boot: Date?

    /// The whole length, for the ring (it grows with +30 min).
    public var total: TimeInterval? { end.map { $0.timeIntervalSince(start) } }
}

/// Why Keep Awake stopped by itself: the only ends that show a strip (ADR-0041).
public enum KeepAwakeEnd: Equatable, Sendable {
    case timeUp
    case batteryLow
}

/// Something the user did, for a lesson's practice notch.
public enum KeepAwakeEvent: Sendable {
    case turnedOn, extended, turnedOff
}

/// What runs and keeps the Mac awake by itself.
public enum KeepAwakeWork: Equatable, Sendable {
    case agents, converting, both
    /// The work ended; it stops at `until` (2 minutes later), so a short pause between steps doesn't let
    /// the screen go dark.
    case finishing(until: Date)
}

/// Keep Awake's state (ADR-0041), shared by the real notch, Home's live copy and the menu bar menu. It holds
/// the Mac awake while you asked for it, or while work runs (an AI agent works or waits for you, the Shelf
/// converts a file, and 2 minutes after), unless the module is off or the battery is low.
///
/// No polling (AGENTS.md rule 2): a session's end and the 2-minute tail are each one sleeping Task; the
/// battery comes from IOKit's power-source notification; a wake or a clock change checks them again.
/// The rules are checked with a TLA+ model (the local skill `verify-keep-awake`).
@MainActor
@Observable
public final class KeepAwakeCenter {
    /// How long work's tail keeps the Mac awake after the last work ends.
    public static let tail: TimeInterval = 2 * 60
    /// What +30 min adds.
    public static let extraTime: TimeInterval = 30 * 60
    /// A session never runs more than this far ahead (+30 min stops adding there).
    public static let longest: TimeInterval = 24 * 3600
    /// A session's end that comes more than this late (the Mac slept through it) ends quietly.
    static let lateness: TimeInterval = 60

    public let settings: KeepAwakeSettings
    /// The session you started, if any.
    public private(set) var session: KeepAwakeSession?
    /// An AI agent works or waits for you (the Agents module tells).
    public private(set) var agentsBusy = false
    /// The Shelf converts a file.
    public private(set) var converting = false
    /// When the tail after work ends, while it runs.
    public private(set) var tailEnd: Date?
    /// You turned it off while work kept it awake: it stays off until that work ends.
    public private(set) var pausedForWork = false
    public private(set) var power: PowerState
    /// Goes up each time the Mac woke or the clock changed: the ring starts again from the new time.
    public private(set) var clockEpoch = 0

    /// It stopped by itself (time up, battery low) while it was keeping the Mac awake: show a strip.
    @ObservationIgnored public var onEndedByItself: ((KeepAwakeEnd) -> Void)?
    /// Told about each thing the user does (a lesson's practice notch).
    @ObservationIgnored public var onEvent: ((KeepAwakeEvent) -> Void)?

    /// A practice copy works even while the module is switched off (it holds nothing anyway).
    @ObservationIgnored private let isPractice: Bool
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let holder: any PowerHolding
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let readPower: () -> PowerState
    @ObservationIgnored private let bootTime: () -> Date?
    /// The battery was low, and it kept the Mac awake, as of the last `update()`: each change is measured
    /// against them, so a setting, the power source or the clock all end things the same way.
    @ObservationIgnored private var wasLow = false
    @ObservationIgnored private var wasHolding = false
    @ObservationIgnored private var endTask: Task<Void, Never>?
    @ObservationIgnored private var tailTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: PowerSourceWatcher?
    @ObservationIgnored private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    /// - Parameters:
    ///   - defaults: where to keep a session; `nil` keeps it in memory only (practice, tests, snapshots).
    ///   - holder: what holds the Mac awake; practice and tests pass a `PretendPowerHold`.
    ///   - power: reads the battery now; a practice copy is always plugged in.
    ///   - bootTime: when the Mac started up.
    public init(settings: KeepAwakeSettings, defaults: UserDefaults? = nil, holder: any PowerHolding = PretendPowerHold(),
                now: @escaping () -> Date = Date.init, power: @escaping () -> PowerState = { .pluggedIn },
                bootTime: @escaping () -> Date? = KeepAwakeCenter.systemBootTime, isPractice: Bool = false) {
        self.settings = settings
        self.isPractice = isPractice
        self.defaults = defaults
        self.holder = holder
        self.clock = now
        self.readPower = power
        self.bootTime = bootTime
        self.power = power()
        session = restoredSession()
        save()
        // A battery already low at launch ends nothing it should tell about.
        wasLow = batteryLow
        settings.addListener(self)
        update()
    }

    /// Follows the battery, wakes and clock changes. The real center only.
    public func start() {
        guard observers.isEmpty else { return }
        let watcher = PowerSourceWatcher()
        watcher.start { [weak self] in self?.powerChanged() }
        self.watcher = watcher
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.timeMayHaveJumped() }
        }))
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.timeMayHaveJumped() }
        }))
        powerChanged()
    }

    /// Stops following, and lets the Mac sleep (quitting, or the module switched off).
    public func stop() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
        watcher?.stop()
        watcher = nil
        endTask?.cancel()
        tailTask?.cancel()
        holder.hold(nil)
    }

    public var now: Date { clock() }

    // MARK: What it does now

    /// Work that keeps it awake by itself runs now (its switch is on).
    public var workRuns: Bool {
        (settings.whileAgentsWork && agentsBusy) || (settings.whileConverting && converting)
    }

    /// Work runs, or its 2-minute tail does.
    public var automatic: Bool { workRuns || tailEnd != nil }

    /// On battery at or below the cutoff: it can't keep the Mac awake until it's plugged in.
    public var batteryLow: Bool {
        guard let cutoff = settings.batteryCutoff, power.onBattery, let percent = power.percent else { return false }
        return percent <= cutoff
    }

    /// The module is on (a practice copy always is).
    public var isEnabled: Bool { isPractice || settings.isEnabled }

    /// It keeps the Mac awake right now.
    public var isHolding: Bool {
        isEnabled && !batteryLow && (session != nil || (automatic && !pausedForWork))
    }

    /// What runs by itself now, if it keeps the Mac awake (for the page's "why").
    public var work: KeepAwakeWork? {
        let agents = settings.whileAgentsWork && agentsBusy, files = settings.whileConverting && converting
        if agents && files { return .both }
        if agents { return .agents }
        if files { return .converting }
        return tailEnd.map { .finishing(until: $0) }
    }

    /// Turn On can start a session now.
    public var canTurnOn: Bool { isEnabled && !batteryLow }

    /// How long a session has left, or `nil` for none or one until you stop.
    public func remaining(at date: Date) -> TimeInterval? {
        session?.end.map { max(0, $0.timeIntervalSince(date)) }
    }

    // MARK: What you do

    /// Starts a session (replacing one that runs) and remembers the length for next time.
    public func turnOn(_ length: KeepAwakeLength? = nil) {
        guard canTurnOn else { return }
        let length = length ?? settings.lastLength
        // A practice copy shares the user's settings but doesn't change their next plain Turn On.
        if !isPractice { settings.lastLength = length }
        let start = now
        session = KeepAwakeSession(start: start, end: length.seconds.map { start.addingTimeInterval($0) }, boot: bootTime())
        change(\.pausedForWork, false)
        changed(.turnedOn)
    }

    /// +30 min on a timed session (from now if it's somehow past its end), up to a day ahead.
    public func extend() {
        guard var session, let end = session.end else { return }
        let next = max(end, now).addingTimeInterval(Self.extraTime)
        session.end = min(next, now.addingTimeInterval(Self.longest))
        self.session = session
        changed(.extended)
    }

    /// Ends a session. While work keeps it awake, it stays off until that work ends.
    public func turnOff() {
        change(\.session, nil)
        if workRuns { change(\.pausedForWork, true) }
        change(\.tailEnd, nil)
        changed(.turnedOff)
    }

    /// The agents or a conversion started or stopped (from the app's wiring).
    public func setWork(agents: Bool, converting: Bool) {
        let wasRunning = workRuns
        change(\.agentsBusy, agents)
        change(\.converting, converting)
        if workRuns {
            change(\.tailEnd, nil)
        } else {
            // The work you paused for is over: the next run turns it on again, without a tail.
            if wasRunning, !pausedForWork { change(\.tailEnd, now.addingTimeInterval(Self.tail)) }
            change(\.pausedForWork, false)
        }
        update()
    }

    // MARK: Time and power

    /// The Mac woke or the clock changed: a session or tail that's due ends now (quietly when it's long
    /// past), otherwise each is set again on the new clock.
    public func timeMayHaveJumped() {
        clockEpoch += 1
        update()
    }

    /// The battery or the power source changed.
    public func powerChanged() {
        setPower(readPower())
    }

    /// The new power state. Going low while it keeps the Mac awake ends everything, with a strip (`update`).
    public func setPower(_ state: PowerState) {
        change(\.power, state)
        update()
    }

    /// A setting changed (told at once by the settings, so the hold never lags behind what they say).
    /// Switching both automatic sources off drops the tail; switching one on while it runs ends a tail.
    func settingsChanged() {
        if workRuns {
            change(\.tailEnd, nil)
        } else {
            if !settings.whileAgentsWork && !settings.whileConverting { change(\.tailEnd, nil) }
            // No pause for work that no longer counts.
            change(\.pausedForWork, false)
        }
        update()
    }

    // MARK: Inner workings

    /// Writes a value only when it changes. Older Observation (the macOS 15 toolchain) tells observers about
    /// every write, equal or not, and the app's wiring writes the same work again on each change: an
    /// unchanged write would loop (KeepAwakeModelTests, identicalWorkInputDoesNotRetriggerHoldingObservation).
    private func change<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<KeepAwakeCenter, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    private func changed(_ event: KeepAwakeEvent) {
        save()
        update()
        onEvent?(event)
    }

    /// Ends what's due, then holds the Mac (or lets it go) and sets the Tasks for what ends next. Every change
    /// comes through here. In order: the module switched off ends everything quietly; the battery going low
    /// ends everything, with a strip if it was keeping the Mac awake; a session at its end ends, with a strip
    /// if the Mac can sleep now and it isn't long past (the Mac slept through it); a tail at its end ends.
    private func update() {
        let moment = now
        var told: KeepAwakeEnd?
        if !isEnabled {
            change(\.session, nil)
            change(\.tailEnd, nil)
            change(\.pausedForWork, false)
        } else if batteryLow, !wasLow {
            change(\.session, nil)
            change(\.tailEnd, nil)
            if wasHolding { told = .batteryLow }
        }
        if let end = session?.end, end <= moment {
            change(\.session, nil)
            if moment.timeIntervalSince(end) <= Self.lateness { told = .timeUp }
        }
        if let tail = tailEnd, tail <= moment { change(\.tailEnd, nil) }
        save()
        let holding = isHolding
        holder.hold(holding ? (settings.screen == .staysOn ? .screen : .system) : nil)
        schedule()
        wasLow = batteryLow
        wasHolding = holding
        // Time up tells only when the Mac can sleep again: work may still keep it awake.
        if let told, told == .batteryLow || !holding { onEndedByItself?(told) }
    }

    private func schedule() {
        endTask?.cancel()
        endTask = session?.end.map(sleepTask(until:))
        tailTask?.cancel()
        tailTask = tailEnd.map(sleepTask(until:))
    }

    /// Sleeps until `date`, then updates. Task.sleep's clock counts sleep, so after a long sleep it wakes
    /// at once; if the wall clock moved meanwhile, it sleeps again for what's left.
    private func sleepTask(until date: Date) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait = date.timeIntervalSince(self.now)
                if wait <= 0 {
                    self.update()
                    return
                }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// The saved session, if the Reopen setting carries it on and it hasn't run out.
    private func restoredSession() -> KeepAwakeSession? {
        guard let defaults, isEnabled,
              let data = defaults.data(forKey: Keys.session),
              let saved = try? JSONDecoder().decode(KeepAwakeSession.self, from: data) else { return nil }
        switch settings.reopen {
        case .startOff: return nil
        case .carryOnAfterRestart: break
        case .carryOn:
            guard let then = saved.boot, let boot = bootTime(), abs(then.timeIntervalSince(boot)) < 60 else { return nil }
        }
        if let end = saved.end, end <= now { return nil }
        // A battery already low ends it quietly: there was nobody to tell.
        if batteryLow { return nil }
        return saved
    }

    private func save() {
        guard let defaults else { return }
        if let session, let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: Keys.session)
        } else {
            defaults.removeObject(forKey: Keys.session)
        }
    }

    /// When this Mac started up (`kern.boottime`).
    public nonisolated static func systemBootTime() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1e6)
    }

    enum Keys {
        static let session = "keepAwake.session"
    }
}
