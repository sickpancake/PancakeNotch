import AppKit
import Foundation
import NotchCore
import Testing
@testable import ModuleNowPlaying
@testable import NowPlayingCore

/// Reports whatever the test hands it; nothing real plays.
@MainActor
final class EarTestBackend: NowPlayingBackend {
    var onUpdate: ((NowPlayingUpdate) -> Void)?
    var onConnectionChange: ((NowPlayingConnection) -> Void)?
    func start() {}
    func stop() {}
    func send(_ command: NowPlayingCommand) {}
    var processID: pid_t? { nil }
}

/// When Now Playing wants a spot beside the notch (ADR-0011's ear rules, ADR-0032).
@MainActor
struct NowPlayingEarTests {
    func makeModule() -> (NowPlayingModule, EarTestBackend) {
        let suite = "NowPlayingEarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let backend = EarTestBackend()
        let center = NowPlayingCenter(settings: NowPlayingSettings(defaults: defaults), backend: backend)
        center.start()
        return (NowPlayingModule(center: center), backend)
    }

    func play(_ backend: EarTestBackend, playing: Bool = true) {
        let track = NowPlayingTrack(title: "Song", artist: "Band", duration: 200, elapsed: 10, elapsedDate: .now,
                                    isPlaying: playing, bundleID: "com.apple.Music", shuffle: .off, repeatMode: .off)
        backend.onUpdate?(NowPlayingUpdate(track: track))
    }

    @Test func noSongNoSpot() {
        let (module, _) = makeModule()
        #expect(!module.isActive)
    }

    @Test func aPlayingSongTakesASpot() {
        let (module, backend) = makeModule()
        play(backend)
        #expect(module.isActive)
    }

    @Test func aPausedSongKeepsItsSpotUntilYouMoveOn() {
        let (module, backend) = makeModule()
        play(backend, playing: false)
        #expect(module.isActive)
        module.userSwitchedAway()
        #expect(!module.isActive)
        // Coming back to Now Playing in the open notch takes the spot back.
        module.notchDidOpen()
        #expect(module.isActive)
    }

    @Test func aPlayingSongKeepsItsSpotEvenAfterYouMoveOn() {
        let (module, backend) = makeModule()
        play(backend)
        module.userSwitchedAway()
        #expect(module.isActive)
    }

    @Test func theSettingTurnsTheSpotOff() {
        let (module, backend) = makeModule()
        play(backend)
        module.center.settings.showsInEars = false
        #expect(!module.isActive)
    }

    @Test func artAndSoundBarsBothComeWithIt() {
        let (module, backend) = makeModule()
        play(backend)
        let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        let ears = module.compactEars(layout: layout)
        #expect(ears != nil)
        #expect(ears?.extra != nil)
    }
}
