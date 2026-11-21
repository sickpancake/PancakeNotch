import Darwin
import Foundation

/// One process's memory and CPU time at a moment.
public struct ProcessReading: Sendable, Equatable {
    public var pid: pid_t
    /// Physical footprint in bytes: the memory figure Activity Monitor shows.
    public var footprintBytes: UInt64
    /// User plus system CPU time since the process started, in seconds.
    public var cpuTime: TimeInterval
    /// How long the process has been running (awake time), in seconds.
    public var uptime: TimeInterval

    public init(pid: pid_t, footprintBytes: UInt64, cpuTime: TimeInterval, uptime: TimeInterval) {
        self.pid = pid
        self.footprintBytes = footprintBytes
        self.cpuTime = cpuTime
        self.uptime = uptime
    }
}

/// Reads this process's (and a helper's) memory and CPU time. No polling inside: callers sample
/// when they want.
public enum AppHealth {
    /// Physical footprint in bytes. nil `pid` (or our own) reads this process via `task_info`;
    /// another pid (the Now Playing helper) via `proc_pid_rusage`. nil if it can't be read.
    public static func footprint(pid: pid_t? = nil) -> UInt64? {
        guard let pid, pid != getpid() else { return ownFootprint() }
        return rusage(pid)?.ri_phys_footprint
    }

    /// User plus system CPU seconds since the process started.
    public static func cpuTime(pid: pid_t? = nil) -> TimeInterval? {
        guard let info = rusage(pid ?? getpid()) else { return nil }
        return seconds(machTime: info.ri_user_time &+ info.ri_system_time)
    }

    /// Memory, CPU time and uptime in one read.
    public static func reading(pid: pid_t? = nil) -> ProcessReading? {
        let pid = pid ?? getpid()
        guard let info = rusage(pid) else { return nil }
        let now = mach_absolute_time()
        let started = info.ri_proc_start_abstime
        return ProcessReading(
            pid: pid,
            footprintBytes: pid == getpid() ? (ownFootprint() ?? info.ri_phys_footprint) : info.ri_phys_footprint,
            cpuTime: seconds(machTime: info.ri_user_time &+ info.ri_system_time),
            uptime: now > started ? seconds(machTime: now - started) : 0
        )
    }

    private static func ownFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    private static func rusage(_ pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info : nil
    }

    /// CPU times from `proc_pid_rusage` are in Mach time units, not nanoseconds, on Apple silicon.
    static func seconds(machTime: UInt64) -> TimeInterval {
        Double(machTime) * nanosecondsPerTick / 1_000_000_000
    }

    private static let nanosecondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else { return 1 }
        return Double(info.numer) / Double(info.denom)
    }()
}

/// The app's (and the Now Playing helper's) readings at one moment.
public struct HealthReading: Sendable, Equatable {
    public var app: ProcessReading
    public var helper: ProcessReading?

    public init(app: ProcessReading, helper: ProcessReading?) {
        self.app = app
        self.helper = helper
    }

    /// Reads both processes now; nil only if the app can't read itself.
    public static func current(helperPID: pid_t?) -> HealthReading? {
        guard let app = AppHealth.reading() else { return nil }
        return HealthReading(app: app, helper: helperPID.flatMap { AppHealth.reading(pid: $0) })
    }
}

/// Turns two CPU-time readings into a percentage of one core, and decides when a historical
/// sample is due (at most one per `interval`, default 10 min). Samples are taken on events
/// (notch opens, the window opening), never on a timer.
///
/// CPU % is the average since the previous sample, so it covers the whole gap between events.
/// The first sample averages since each process started. With `interval: 0` every call returns a
/// sample, which suits a live read-out that's refreshed while it's on screen.
public struct HealthSampler: Sendable {
    public var interval: TimeInterval
    private var lastSampleDate: Date?
    private var previous: (date: Date, reading: HealthReading)?

    public init(interval: TimeInterval = 600) {
        self.interval = interval
    }

    /// Whether a sample taken at `now` would be kept.
    public func isDue(at now: Date) -> Bool {
        guard let lastSampleDate else { return true }
        return now.timeIntervalSince(lastSampleDate) >= interval || now < lastSampleDate
    }

    /// Reads the processes and returns a sample if one is due, else nil (and reads nothing).
    public mutating func sample(now: Date, helperPID: pid_t?) -> HealthSample? {
        guard isDue(at: now), let reading = HealthReading.current(helperPID: helperPID) else { return nil }
        return sample(now: now, reading: reading)
    }

    /// Same, with a reading you made yourself (tests, or reusing a reading).
    public mutating func sample(now: Date, reading: HealthReading) -> HealthSample? {
        guard isDue(at: now) else { return nil }
        let elapsed = previous.map { now.timeIntervalSince($0.date) } ?? 0
        var cpu = Self.cpuPercent(previous: previous?.reading.app, current: reading.app, elapsed: elapsed)
        if let helper = reading.helper {
            cpu += Self.cpuPercent(previous: previous?.reading.helper, current: helper, elapsed: elapsed)
        }
        previous = (now, reading)
        lastSampleDate = now
        return HealthSample(
            date: now,
            footprintBytes: reading.app.footprintBytes,
            helperFootprintBytes: reading.helper?.footprintBytes ?? 0,
            cpuPercent: cpu
        )
    }

    /// CPU seconds used over wall-clock seconds, as a percentage of one core (100 = one core busy).
    public static func cpuPercent(cpuSeconds: TimeInterval, over elapsed: TimeInterval) -> Double {
        guard elapsed > 0, cpuSeconds.isFinite, elapsed.isFinite else { return 0 }
        return max(cpuSeconds, 0) / elapsed * 100
    }

    /// Since the previous reading of the same process; since it started when there's none (or the
    /// process was restarted and has a new pid).
    static func cpuPercent(previous: ProcessReading?, current: ProcessReading, elapsed: TimeInterval) -> Double {
        if let previous, previous.pid == current.pid, elapsed >= 0.001, current.cpuTime >= previous.cpuTime {
            return cpuPercent(cpuSeconds: current.cpuTime - previous.cpuTime, over: elapsed)
        }
        return cpuPercent(cpuSeconds: current.cpuTime, over: current.uptime)
    }
}
