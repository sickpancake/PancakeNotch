import AppKit
import Foundation
import NotchCore
import Testing
@testable import ModuleNowPlaying
@testable import NowPlayingCore

/// Reports whatever the test hands it; nothing real plays.
@MainActor
final class SongTestBackend: NowPlayingBackend {
    var onUpdate: ((NowPlayingUpdate) -> Void)?
    var onConnectionChange: ((NowPlayingConnection) -> Void)?
    func start() {}
    func stop() {}
    func send(_ command: NowPlayingCommand) {}
    var processID: pid_t? { nil }
}

/// After you pick another module while music plays, the notch opens on your pick until the music stops
/// (NotchSong.tla, UX review 2026-11-03).
@MainActor
struct SongFocusTests {
    final class Clock {
        var date = Date(timeIntervalSince1970: 1_000_000)
    }

    func makeModule(_ clock: Clock) -> (NowPlayingModule, SongTestBackend, NotchViewModel) {
        let suite = "SongFocusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let backend = SongTestBackend()
        let center = NowPlayingCenter(settings: NowPlayingSettings(defaults: defaults), backend: backend, now: { clock.date })
        center.start()
        let module = NowPlayingModule(center: center)
        module.now = { clock.date }
        let notch = NotchViewModel(layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))))
        notch.modules = [module]
        return (module, backend, notch)
    }

    func play(_ backend: SongTestBackend, _ title: String = "Song", playing: Bool = true) {
        let track = NowPlayingTrack(title: title, artist: "Band", duration: 200, elapsed: 10, elapsedDate: .now,
                                    isPlaying: playing, bundleID: "com.apple.Music", shuffle: .off, repeatMode: .off)
        backend.onUpdate?(NowPlayingUpdate(track: track))
    }

    func nothing(_ backend: SongTestBackend) {
        backend.onUpdate?(NowPlayingUpdate(track: nil))
    }

    /// Lets the module's observation of the player run.
    func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    // NotchSong.tla: hover → pick the Shelf → move away → the next song starts → hover again.
    @Test func yourPickSticksAcrossSongs() async {
        let clock = Clock()
        let (module, backend, notch) = makeModule(clock); defer { withExtendedLifetime(notch) {} }
        play(backend, "One")
        await settle()
        #expect(module.wantsFocus)
        module.userSwitchedAway()
        #expect(!module.wantsFocus)
        clock.date += 200
        play(backend, "Two")
        await settle()
        #expect(!module.wantsFocus)
        // It keeps its spot beside the notch meanwhile.
        #expect(module.isActive)
    }

    // Some players report "nothing playing" for a moment between two songs: still the same listening.
    @Test func theGapBetweenSongsKeepsYourPick() async {
        let clock = Clock()
        let (module, backend, notch) = makeModule(clock); defer { withExtendedLifetime(notch) {} }
        play(backend, "One")
        await settle()
        module.userSwitchedAway()
        nothing(backend)
        await settle()
        clock.date += 2
        play(backend, "Two")
        await settle()
        #expect(!module.wantsFocus)
    }

    // The music stops for real, then plays again: the song comes first again.
    @Test func playingAgainAfterAStopTakesTheFirstPageBack() async {
        let clock = Clock()
        let (module, backend, notch) = makeModule(clock); defer { withExtendedLifetime(notch) {} }
        play(backend, "One")
        await settle()
        module.userSwitchedAway()
        play(backend, "One", playing: false)
        await settle()
        clock.date += 60
        play(backend, "One")
        await settle()
        #expect(module.wantsFocus)
    }

    // Coming back to Now Playing yourself undoes the pick at once.
    @Test func comingBackUndoesYourPick() async {
        let clock = Clock()
        let (module, backend, notch) = makeModule(clock); defer { withExtendedLifetime(notch) {} }
        play(backend)
        await settle()
        module.userSwitchedAway()
        module.notchDidOpen()
        #expect(module.wantsFocus)
    }

    // A paused song you moved on from stays out of the way (unchanged).
    @Test func aPausedSongYouMovedOnFromStepsAside() async {
        let clock = Clock()
        let (module, backend, notch) = makeModule(clock); defer { withExtendedLifetime(notch) {} }
        play(backend, playing: false)
        await settle()
        module.userSwitchedAway()
        #expect(!module.wantsFocus)
        #expect(!module.isActive)
    }
}


extension SongFocusTests {
    @Test(arguments: [true, false]) func pausedLastModuleOpensHome(tabs: Bool) async {
        let (module, backend, notch) = makeModule(Clock())
        notch.home.opening = .lastModule
        notch.arrangement.navigation = tabs ? .tabs : .tabsAndMenu
        play(backend)
        await settle()
        notch.open()
        #expect(!notch.showsHome)
        #expect(module.wantsFocus)
        notch.close()
        play(backend, playing: false)
        await settle()
        #expect(!module.wantsFocus)
        #expect(module.isIdleForOpening)
        #expect(module.isActive) // Paused artwork still keeps its spot beside the notch.
        notch.open()
        #expect(notch.showsHome == !tabs)
        #expect(notch.selectedModule?.moduleID == "nowPlaying")
        notch.close()
        nothing(backend)
        await settle()
        notch.open()
        #expect(notch.showsHome == !tabs)
    }
}
