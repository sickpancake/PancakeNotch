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

    /// The user picked another module in the open notch. The notch stops opening on Now Playing until the
    /// music stops and plays again, or the user comes back to it; later songs in a row don't undo the pick.
    /// A paused song also gives up its ear meanwhile.
    private(set) var hasYielded = false
    /// When the music last stopped (paused, or nothing loaded), to tell a real stop from the short gap
    /// between two songs. `nil` while it plays.
    @ObservationIgnored private var stoppedAt: Date?
    /// The clock (replaceable in tests).
    @ObservationIgnored var now: () -> Date = Date.init
    /// Where the progress bar is being dragged to, in seconds (nil when not dragging).
    var scrubTime: TimeInterval?
    /// A short note over the artwork (the practice player can't open an app).
    var artworkNote: String?
    /// The "Open ▾" app menu is showing: it keeps the notch open.
    private(set) var isAppMenuOpen = false

    @ObservationIgnored private var lastIdentity: String?
    @ObservationIgnored private var wasPlaying = false
    @ObservationIgnored private var noteTask: Task<Void, Never>?

    /// Music that stops for less than this and plays again is the gap between two songs, not a stop:
    /// the user's pick of another module stays.
    static let songGap: TimeInterval = 10

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

    /// Playing music takes focus unless the user picked another module since it started.
    public var wantsFocus: Bool { center.track?.isPlaying == true && !hasYielded }

    public var isIdleForOpening: Bool { center.track?.isPlaying != true }

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
            center.viewerClosed(self)
            return
        }
        lastIdentity = center.track?.identity
        wasPlaying = center.track?.isPlaying ?? false
        stoppedAt = wasPlaying ? nil : now()
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
        center.viewerOpened(self)
        guard hasYielded else { return }
        hasYielded = false
        notch?.activityChanged()
    }

    public func notchDidClose() {
        scrubTime = nil
        center.viewerClosed(self)
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
        if isPlaying, !wasPlaying {
            // Music playing again after a real stop takes the ears and the first page back. The next song
            // (even after the player's short gap between songs) keeps the user's pick.
            if stoppedAt.map({ now().timeIntervalSince($0) >= Self.songGap }) ?? true { hasYielded = false }
            stoppedAt = nil
        } else if !isPlaying, wasPlaying || stoppedAt == nil {
            stoppedAt = now()
        }
        if let identity = track?.identity, identity != lastIdentity {
            if lastIdentity != nil {
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

    // Every action checks `center.abilities` again: a button that can't work does nothing and tells
    // the lessons nothing (the views dim or hide it as well).

    func playPause() {
        guard let track = center.track else { return }
        center.send(track.isPlaying ? .pause : .play)
        onEvent?(track.isPlaying ? .paused : .played)
    }

    /// "Resume" while nothing plays (see `NowPlayingCenter.resumeOption`).
    func resume() {
        switch center.resumeOption {
        case .practice?, .app?: break
        case .needsPermission?, nil: return
        }
        center.resume()
        onEvent?(.played)
    }

    func skip(forward: Bool) {
        let abilities = center.abilities
        guard forward ? abilities.canSkipForward : abilities.canSkipBack else { return }
        center.send(forward ? .next : .previous)
        onEvent?(forward ? .skippedForward : .skippedBack)
    }

    func seek(to time: TimeInterval) {
        guard center.abilities.canSeek else { return }
        center.send(.seek(to: max(0, time)))
        onEvent?(.seeked)
    }

    func cycleShuffle() {
        guard let shuffle = center.abilities.shuffle else { return }
        center.setShuffle(shuffle == .off ? .tracks : .off)
        onEvent?(.shuffleChanged)
    }

    /// Off → whole list → this song → off, like the Music app (Spotify: off ↔ on).
    func cycleRepeat() {
        let abilities = center.abilities
        guard let mode = abilities.repeatMode else { return }
        center.setRepeat(abilities.nextRepeatMode(after: mode))
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

    /// Opens another app from the "Open ▾" menu and gets the notch out of its way.
    func openApp(_ bundleID: String) {
        guard center.connection != .practice else { return }
        center.openApp(bundleID)
        notch?.close()
    }

    func toggleTimeDisplay() {
        settings.showsRemainingTime.toggle()
    }

    // MARK: Holding the notch open

    /// The app menu keeps the notch open while it's showing.
    public var holdsOpen: Bool { isAppMenuOpen }

    func setAppMenuOpen(_ open: Bool) {
        guard isAppMenuOpen != open else { return }
        isAppMenuOpen = open
        if !open { notch?.holdReleased() }
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
