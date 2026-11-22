import Foundation

/// The Timer's countdown (ADR-0040). It keeps the date it ends, not a running count, so sleep and quitting
/// don't lose time: the time left is always `end - now`.
public struct CountdownTimer: Codable, Equatable, Sendable {
    public enum Phase: Codable, Equatable, Sendable {
        case idle
        case running(end: Date)
        case paused(remaining: TimeInterval)
        /// Finished at `endedAt` (its end date, also when the Mac slept through it).
        case done(endedAt: Date)
    }

    /// The longest timer the wheels can set: 23:59:59.
    public static let longest: TimeInterval = 23 * 3600 + 59 * 60 + 59

    public private(set) var phase: Phase = .idle
    /// The length it was started with; Repeat starts it again.
    public private(set) var duration: TimeInterval = 0
    /// What the ring drains from: the length, or one minute after +1 min.
    public private(set) var total: TimeInterval = 0
    /// Tells timers apart while several run (issue #70); kept across Repeat and +1 min.
    public private(set) var id = UUID()
    /// What the user called it ("Pasta"); empty when unnamed.
    public var name = ""

    public init() {}

    public init(name: String) { self.name = name }

    private enum CodingKeys: String, CodingKey { case phase, duration, total, id, name }

    /// Older saves have no id or name.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        phase = try values.decode(Phase.self, forKey: .phase)
        duration = try values.decode(TimeInterval.self, forKey: .duration)
        total = try values.decode(TimeInterval.self, forKey: .total)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
    }

    public var isRunning: Bool { if case .running = phase { true } else { false } }
    public var isPaused: Bool { if case .paused = phase { true } else { false } }
    public var isDone: Bool { if case .done = phase { true } else { false } }
    public var isIdle: Bool { phase == .idle }

    /// When it ends, while it runs.
    public var end: Date? { if case .running(let end) = phase { end } else { nil } }
    /// When it ran out, while it shows Done.
    public var endedAt: Date? { if case .done(let endedAt) = phase { endedAt } else { nil } }

    /// Starts a new timer; ignored while one is running or paused (cancel it first), or for less than a second.
    public mutating func start(_ seconds: TimeInterval, now: Date) {
        guard isIdle || isDone else { return }
        let length = min(Self.longest, seconds.rounded())
        guard length >= 1 else { return }
        duration = length
        total = length
        phase = .running(end: now + length)
    }

    /// Pauses with the time left. Ignored once the end has come: it's finishing.
    public mutating func pause(now: Date) {
        guard case .running(let end) = phase, end > now else { return }
        phase = .paused(remaining: end.timeIntervalSince(now))
    }

    public mutating func resume(now: Date) {
        guard case .paused(let remaining) = phase else { return }
        phase = .running(end: now + remaining)
    }

    /// Cancel while running or paused.
    public mutating func cancel() {
        guard isRunning || isPaused else { return }
        phase = .idle
    }

    /// Stop on the Done card.
    public mutating func stop() {
        guard isDone else { return }
        phase = .idle
    }

    /// +1 min on the Done card: a one-minute timer.
    public mutating func addMinute(now: Date) {
        guard isDone else { return }
        total = 60
        phase = .running(end: now + 60)
    }

    /// +1 min on a running or paused timer: a minute more, and the ring drains from the new length.
    public mutating func extend(by seconds: TimeInterval) {
        switch phase {
        case .running(let end):
            phase = .running(end: end + seconds)
        case .paused(let remaining):
            phase = .paused(remaining: remaining + seconds)
        default:
            return
        }
        total += seconds
    }

    /// Repeat on the Done card: the same length again.
    public mutating func restart(now: Date) {
        guard isDone, duration >= 1 else { return }
        total = duration
        phase = .running(end: now + duration)
    }

    /// Finishes a running timer whose end has come. Returns `true` only for the call that finished it, so
    /// the alarm, the wake and the clock check can all ask and the sound still plays once.
    public mutating func finishIfDue(now: Date) -> Bool {
        guard case .running(let end) = phase, now >= end else { return false }
        phase = .done(endedAt: end)
        return true
    }

    /// Seconds left: what the countdown shows.
    public func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle: duration
        case .running(let end): max(0, end.timeIntervalSince(now))
        case .paused(let remaining): remaining
        case .done: 0
        }
    }

    /// 1 at the start, 0 at the end: how full the ring is.
    public func fractionLeft(at now: Date) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, remaining(at: now) / total))
    }
}
