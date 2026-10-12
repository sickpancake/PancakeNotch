import AppKit
import NotchCore
import NowPlayingCore
import Observation
import SwiftUI

/// What the user just did in Now Playing, for the app window's lessons.
public enum NowPlayingEvent: Equatable, Sendable {
    case played, paused, skippedForward, skippedBack, seeked, shuffleChanged, repeatChanged, artworkClicked
    /// The user switched to another module in the open notch.
    case switchedAway
}

/// Now Playing in the notch (ADR-0012): album art and sound bars in the compact ears, the player in the
/// open notch. Several copies can show one `NowPlayingCenter` (the real notch and Home's live notch);
/// each copy keeps its own "the user moved on" state.
@MainActor
@Observable
public final class NowPlayingModule: NotchModule {
    public let center: NowPlayingCenter
    public var settings: NowPlayingSettings { center.settings }

    @ObservationIgnored public private(set) weak var notch: NotchViewModel?
    /// Told what the user does (play, skip, drag the progress bar…), for the lessons.
    @ObservationIgnored public var onEvent: (@MainActor (NowPlayingEvent) -> Void)?
    /// Rendering off-screen: plain SwiftUI bars instead of the Core Animation ones.
    @ObservationIgnored public var isSnapshot = false

    /// The user picked another module while this song was paused (or before it started playing):
    /// the song gives up its ear until music plays again, and the notch stops opening on it.
    private(set) var hasYielded = false
    /// Where the progress bar is being dragged to, in seconds (nil when not dragging).
    var scrubTime: TimeInterval?
    /// A short note over the artwork (the practice player can't open an app).
    var artworkNote: String?

    @ObservationIgnored private var lastIdentity: String?
    @ObservationIgnored private var wasPlaying = false
    @ObservationIgnored private var noteTask: Task<Void, Never>?

    /// How long a paused song still counts as "what you're listening to" when the notch opens.
    static let recentPause: TimeInterval = 5 * 60

    public init(center: NowPlayingCenter) {
        self.center = center
    }

    // MARK: NotchModule

    public var moduleID: String { "nowPlaying" }
    public var title: String { String(localized: "Now Playing", comment: "Module name") }
    public var symbol: String { "music.note" }

    public var menuStatus: String? {
        guard let track = center.track else {
            if case .unavailable = center.connection { return String(localized: "Not connected") }
            return String(localized: "Nothing playing")
        }
        return track.isPlaying ? track.title : String(localized: "Paused: \(track.title)", comment: "Module Menu status")
    }

    /// Art and sound bars beside the notch while a song is loaded, until the user moves on from a
    /// paused one.
    public var isActive: Bool {
        guard settings.showsInEars, let track = center.track else { return false }
        return track.isPlaying || !hasYielded
    }

    /// The notch opens on Now Playing while music plays or was paused a moment ago.
    public var wantsFocus: Bool {
        guard let track = center.track, !hasYielded else { return false }
        if track.isPlaying { return true }
        guard let pausedSince = center.pausedSince else { return false }
        return Date().timeIntervalSince(pausedSince) < Self.recentPause
    }

    public var accessibilityStatus: String? {
        guard isActive, let track = center.track else { return nil }
        let line = track.artist.isEmpty ? track.title : String(localized: "\(track.title) by \(track.artist)")
        return track.isPlaying
            ? String(localized: "Playing \(line)", comment: "VoiceOver, compact notch")
            : String(localized: "Paused, \(line)", comment: "VoiceOver, compact notch")
    }

    public func attach(to notch: NotchViewModel?) {
        self.notch = notch
        guard notch != nil else {
            noteTask?.cancel()
            scrubTime = nil
            return
        }
        lastIdentity = center.track?.identity
        wasPlaying = center.track?.isPlaying ?? false
        observeCenter()
        notch?.activityChanged()
    }

    public func expandedView(layout: NotchLayout) -> AnyView {
        AnyView(NowPlayingView(module: self, layout: NowPlayingLayout(layout)))
    }

    public func compactEars(layout: NotchLayout) -> CompactEars? {
        CompactEars(
            main: AnyView(NowPlayingArtEar(module: self, height: layout.geometry.compactHeight)),
            extra: AnyView(NowPlayingBarsEar(module: self, height: layout.geometry.compactHeight))
        )
    }

    public func peekView(layout: NotchLayout) -> AnyView? {
        guard center.track != nil else { return nil }
        return AnyView(NowPlayingPeek(module: self))
    }

    /// Coming back to Now Playing takes its ear back (the user hasn't moved on any more).
    public func notchDidOpen() {
        guard hasYielded else { return }
        hasYielded = false
        notch?.activityChanged()
    }

    public func notchDidClose() {
        scrubTime = nil
    }

    public func userSwitchedAway() {
        hasYielded = true
        notch?.activityChanged()
        onEvent?(.switchedAway)
    }

    // MARK: Following the player

    /// Re-checks the ears whenever the song, its play state or the ear setting changes. Observation
    /// only: nothing is polled.
    private func observeCenter() {
        withObservationTracking {
            _ = center.track
            _ = settings.showsInEars
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.notch != nil else { return }
                self.centerChanged()
                self.observeCenter()
            }
        }
    }

    private func centerChanged() {
        let track = center.track
        let isPlaying = track?.isPlaying ?? false
        // Music playing again, or a new song, takes the ears back.
        if isPlaying, !wasPlaying { hasYielded = false }
        if let identity = track?.identity, identity != lastIdentity {
            if lastIdentity != nil {
                // Another paused song showing up isn't music playing again: the ear stays given up.
                if isPlaying { hasYielded = false }
                if settings.peeksOnSongChange, isPlaying, let notch, notch.state != .expanded {
                    notch.peek(self, for: .seconds(3))
                }
            }
            lastIdentity = identity
        } else if track == nil {
            lastIdentity = nil
        }
        wasPlaying = isPlaying
        notch?.activityChanged()
    }

    // MARK: Actions (from the views)

    func playPause() {
        guard let track = center.track else {
            center.resume()
            onEvent?(.played)
            return
        }
        center.send(track.isPlaying ? .pause : .play)
        onEvent?(track.isPlaying ? .paused : .played)
    }

    func skip(forward: Bool) {
        center.send(forward ? .next : .previous)
        onEvent?(forward ? .skippedForward : .skippedBack)
    }

    func seek(to time: TimeInterval) {
        center.send(.seek(to: max(0, time)))
        onEvent?(.seeked)
    }

    func cycleShuffle() {
        guard let shuffle = center.track?.shuffle else { return }
        center.send(.setShuffle(shuffle == .off ? .tracks : .off))
        onEvent?(.shuffleChanged)
    }

    /// Off → whole list → this song → off, like the Music app.
    func cycleRepeat() {
        guard let mode = center.track?.repeatMode else { return }
        let next: RepeatMode = switch mode {
        case .off: .playlist
        case .playlist: .track
        case .track: .off
        }
        center.send(.setRepeat(next))
        onEvent?(.repeatChanged)
    }

    /// Brings the playing app forward. The practice player has no app: it says so instead.
    func openApp() {
        onEvent?(.artworkClicked)
        if center.connection == .practice {
            showNote(String(localized: "In your notch, this opens the app that's playing"))
            return
        }
        center.openPlayerApp()
        // The app comes forward: get the notch out of its way.
        notch?.close()
    }

    func toggleTimeDisplay() {
        settings.showsRemainingTime.toggle()
    }

    private func showNote(_ text: String) {
        noteTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { artworkNote = text }
        noteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { self?.artworkNote = nil }
        }
    }
}
