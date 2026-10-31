import Foundation

/// The Timer module's stopwatch, with laps (ADR-0040). Keeps the date it started, so it counts on through
/// sleep and quitting.
public struct Stopwatch: Codable, Equatable, Sendable {
    public enum Phase: Codable, Equatable, Sendable {
        case idle
        /// Counting since `since`, on top of `banked` from before the last stop.
        case running(since: Date, banked: TimeInterval)
        case stopped(elapsed: TimeInterval)
    }

    /// One lap in the list, newest first.
    public struct Lap: Equatable, Sendable, Identifiable {
        public enum Mark: Sendable { case fastest, slowest }
        /// 1 for the first lap.
        public let number: Int
        public let time: TimeInterval
        public let total: TimeInterval
        /// The lap still being timed (only while there are laps).
        public let isCurrent: Bool
        public let mark: Mark?
        public var id: Int { number }
    }

    /// Fastest and slowest get their tags once this many laps are done.
    public static let lapsForMarks = 3
    /// Laps kept; the list stops growing after this.
    public static let mostLaps = 999

    public private(set) var phase: Phase = .idle
    /// The total time at each Lap press, oldest first.
    public private(set) var lapTotals: [TimeInterval] = []

    public init() {}

    public var isRunning: Bool { if case .running = phase { true } else { false } }
    public var isStopped: Bool { if case .stopped = phase { true } else { false } }
    public var isIdle: Bool { phase == .idle }
    /// Running, with room for another lap.
    public var canLap: Bool { isRunning && lapTotals.count < Self.mostLaps }

    /// When it last started, while it runs (the ear's seconds tick on from it).
    public var runningSince: Date? { if case .running(let since, _) = phase { since } else { nil } }

    public func elapsed(at now: Date) -> TimeInterval {
        switch phase {
        case .idle: 0
        // A clock moved backward never makes it count backward, nor below the last lap.
        case .running(let since, let banked): max(banked + max(0, now.timeIntervalSince(since)), lapTotals.last ?? 0)
        case .stopped(let elapsed): elapsed
        }
    }

    public mutating func start(now: Date) {
        guard !isRunning else { return }
        phase = .running(since: now, banked: elapsed(at: now))
    }

    public mutating func stop(now: Date) {
        guard isRunning else { return }
        phase = .stopped(elapsed: elapsed(at: now))
    }

    public mutating func lap(now: Date) {
        guard canLap else { return }
        lapTotals.append(elapsed(at: now))
    }

    /// Reset while stopped: back to zero, laps gone.
    public mutating func reset() {
        guard isStopped else { return }
        phase = .idle
        lapTotals = []
    }

    /// The laps, newest first: the one being timed on top (once there are laps), then the done ones.
    /// With `lapsForMarks` done laps, the fastest and slowest are tagged (words, not colors: ADR-0029).
    public func laps(at now: Date) -> [Lap] {
        guard !lapTotals.isEmpty else { return [] }
        let times = lapTotals.enumerated().map { index, total in total - (index == 0 ? 0 : lapTotals[index - 1]) }
        var fastest: Int?
        var slowest: Int?
        if times.count >= Self.lapsForMarks, let low = times.min(), let high = times.max(), low < high {
            fastest = times.firstIndex(of: low)
            slowest = times.firstIndex(of: high)
        }
        let total = elapsed(at: now)
        let current = Lap(number: times.count + 1, time: max(0, total - (lapTotals.last ?? 0)), total: total, isCurrent: true, mark: nil)
        let done = times.enumerated().reversed().map { index, time in
            Lap(number: index + 1, time: time, total: lapTotals[index], isCurrent: false,
                mark: index == fastest ? .fastest : index == slowest ? .slowest : nil)
        }
        return [current] + done
    }
}
