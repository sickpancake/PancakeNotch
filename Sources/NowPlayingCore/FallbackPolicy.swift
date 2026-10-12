import Foundation

/// Decides when to stop using the mediaremote-adapter helper and ask Music and Spotify directly
/// instead (ADR-0012). A small state machine without side effects, so it's easy to test:
/// `CompositeBackend` feeds it events and carries out the actions it returns.
struct FallbackPolicy: Equatable, Sendable {
    /// This many helper crashes within `failureWindow` and we give up on it.
    static let maxFailures = 3
    static let failureWindow: TimeInterval = 60
    /// How long the helper may stay quiet after Music or Spotify says it started playing.
    static let silenceTimeout: TimeInterval = 2

    enum Source: Equatable, Sendable {
        /// The helper: every app.
        case adapter
        /// Music and Spotify only.
        case fallback
    }

    enum Reason: Equatable, Sendable {
        /// The helper files are missing or Perl couldn't start.
        case unavailable
        /// The helper kept crashing.
        case crashing
        /// The helper runs but didn't notice music that Music or Spotify reported (macOS closed the door).
        case silent
    }

    enum Event: Equatable, Sendable {
        /// Start (or start over) with the helper.
        case start
        case adapterUnavailable
        /// The helper ended without being asked to.
        case adapterExited(at: Date)
        /// The helper reported a state (nil = nothing playing).
        case adapterReported(NowPlayingTrack?, at: Date)
        /// Music or Spotify posted "Playing".
        case playerStartedPlaying(bundleID: String, at: Date)
        /// The wait scheduled by `.scheduleSilenceCheck` is over.
        case silenceCheck(bundleID: String, notifiedAt: Date)
    }

    enum Action: Equatable, Sendable {
        case none
        case startAdapter
        case restartAdapter(after: TimeInterval)
        case useFallback(Reason)
        case scheduleSilenceCheck(bundleID: String, notifiedAt: Date, after: TimeInterval)
    }

    private(set) var source: Source = .adapter
    private var failures: [Date] = []
    /// When the helper last reported something playing (or paused).
    private var lastContent: Date?
    private var adapterTrack: NowPlayingTrack?

    mutating func handle(_ event: Event) -> Action {
        switch event {
        case .start:
            self = FallbackPolicy()
            return .startAdapter

        case .adapterUnavailable:
            guard source == .adapter else { return .none }
            source = .fallback
            return .useFallback(.unavailable)

        case .adapterExited(let date):
            guard source == .adapter else { return .none }
            failures = failures.filter { date.timeIntervalSince($0) < Self.failureWindow } + [date]
            if failures.count >= Self.maxFailures {
                source = .fallback
                return .useFallback(.crashing)
            }
            return .restartAdapter(after: Self.backoff(afterFailures: failures.count))

        case .adapterReported(let track, let date):
            guard source == .adapter else { return .none }
            adapterTrack = track
            if track != nil { lastContent = date }
            return .none

        case .playerStartedPlaying(let bundleID, let date):
            guard source == .adapter else { return .none }
            return .scheduleSilenceCheck(bundleID: bundleID, notifiedAt: date, after: Self.silenceTimeout)

        case .silenceCheck(let bundleID, let notifiedAt):
            guard source == .adapter,
                  Self.isSilentFailure(bundleID: bundleID, notifiedAt: notifiedAt, lastContent: lastContent, adapterTrack: adapterTrack)
            else { return .none }
            source = .fallback
            return .useFallback(.silent)
        }
    }

    /// Wait 1 s after the first crash, 2 s after the second, …
    static func backoff(afterFailures count: Int) -> TimeInterval {
        min(8, pow(2, Double(max(0, count - 1))))
    }

    /// The helper missed music: nothing arrived since the notification, and what it showed before
    /// isn't that app playing.
    static func isSilentFailure(bundleID: String, notifiedAt: Date, lastContent: Date?, adapterTrack: NowPlayingTrack?) -> Bool {
        if let lastContent, lastContent >= notifiedAt { return false }
        if let track = adapterTrack, track.isPlaying,
           track.bundleID == bundleID || track.sourceBundleID == bundleID {
            return false
        }
        return true
    }
}
