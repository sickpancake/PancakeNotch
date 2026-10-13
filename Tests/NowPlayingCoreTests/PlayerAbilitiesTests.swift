import AppKit
import Foundation
import Testing
@testable import NowPlayingCore

// MARK: Which controls work

struct PlayerAbilitiesTests {
    let spotify = ScriptablePlayers.spotify
    let music = ScriptablePlayers.music

    func song(app: String?, shuffle: ShuffleMode? = nil, repeatMode: RepeatMode? = nil, duration: TimeInterval? = 200,
              ad: Bool = false, commands: Set<Int>? = nil) -> NowPlayingTrack {
        NowPlayingTrack(title: "Song", duration: duration, bundleID: app, shuffle: shuffle, repeatMode: repeatMode,
                        isAdvertisement: ad, enabledCommands: commands)
    }

    @Test func nothingPlayingHasNoControls() {
        #expect(PlayerAbilities.resolve(track: nil, connection: .connected, scripted: nil) == .none)
    }

    @Test func practicePlayerHasEverything() {
        let track = song(app: "io.github.sickpancake.PancakeNotch.practice", shuffle: .off, repeatMode: .off)
        let abilities = PlayerAbilities.resolve(track: track, connection: .practice, scripted: nil)
        #expect(abilities.shuffleRoute == .player)
        #expect(abilities.repeatRoute == .player)
        #expect(abilities.repeatCycle == [.off, .playlist, .track])
        #expect(abilities.canSkipForward && abilities.canSkipBack && abilities.canSeek)
    }

    @Test func spotifyWithoutAScriptReadingHidesModes() {
        let abilities = PlayerAbilities.resolve(track: song(app: spotify), connection: .connected, scripted: nil)
        #expect(!abilities.canShuffle)
        #expect(!abilities.canRepeat)
        #expect(abilities.canSkipForward && abilities.canSeek)
    }

    @Test func spotifyModesGoThroughAppleScriptAndRepeatIsOnOff() {
        let scripted = ScriptedModes(shuffle: .tracks, repeatMode: .playlist)
        let abilities = PlayerAbilities.resolve(track: song(app: spotify), connection: .connected, scripted: scripted)
        #expect(abilities.shuffleRoute == .script)
        #expect(abilities.repeatRoute == .script)
        #expect(abilities.shuffle == .tracks)
        #expect(abilities.repeatCycle == [.off, .playlist])
        #expect(abilities.nextRepeatMode(after: .playlist) == .off)
        #expect(abilities.nextRepeatMode(after: .off) == .playlist)
    }

    @Test func spotifyNeverShowsRepeatOne() {
        let scripted = ScriptedModes(shuffle: .off, repeatMode: .track)
        let abilities = PlayerAbilities.resolve(track: song(app: spotify), connection: .connected, scripted: scripted)
        #expect(abilities.repeatMode == .playlist)
    }

    @Test func musicReportedByTheHelperUsesTheHelper() {
        let track = song(app: music, shuffle: .off, repeatMode: .track, commands: [0, 1, 2, 4, 5, 24, 25, 26])
        let abilities = PlayerAbilities.resolve(track: track, connection: .connected, scripted: nil)
        #expect(abilities.shuffleRoute == .player)
        #expect(abilities.repeatRoute == .player)
        #expect(abilities.repeatCycle == [.off, .playlist, .track])
        #expect(abilities.nextRepeatMode(after: .track) == .off)
    }

    @Test func musicThatRefusesModeCommandsFallsBackToAppleScript() {
        let track = song(app: music, shuffle: .off, repeatMode: .off, commands: [0, 1, 2, 4, 5, 24])
        let none = PlayerAbilities.resolve(track: track, connection: .connected, scripted: nil)
        #expect(!none.canShuffle && !none.canRepeat)
        let scripted = PlayerAbilities.resolve(track: track, connection: .connected,
                                               scripted: ScriptedModes(shuffle: .albums, repeatMode: .off))
        #expect(scripted.shuffleRoute == .script)
        #expect(scripted.shuffle == .albums)
    }

    @Test func browsersHaveNoModes() {
        let track = song(app: "com.google.Chrome")
        let abilities = PlayerAbilities.resolve(track: track, connection: .connected,
                                                scripted: ScriptedModes(shuffle: .off, repeatMode: .off))
        #expect(!abilities.canShuffle)
        #expect(!abilities.canRepeat)
    }

    @Test func theFallbackReportsSpotifyModesItself() {
        let track = song(app: spotify, shuffle: .off, repeatMode: .playlist)
        let abilities = PlayerAbilities.resolve(track: track, connection: .limited, scripted: nil)
        #expect(abilities.shuffleRoute == .player)
        #expect(abilities.repeatCycle == [.off, .playlist])
    }

    @Test func adsRefuseSkippingSeekingAndModes() {
        let track = song(app: spotify, shuffle: .off, repeatMode: .off, ad: true)
        let abilities = PlayerAbilities.resolve(track: track, connection: .connected,
                                                scripted: ScriptedModes(shuffle: .off, repeatMode: .off))
        #expect(!abilities.canSkipForward)
        #expect(!abilities.canSkipBack)
        #expect(!abilities.canSeek)
        #expect(!abilities.canShuffle)
        #expect(!abilities.canRepeat)
        #expect(abilities.isAdvertisement)
        #expect(abilities.skipBlockedReason == String(localized: "Can't skip during an ad"))
    }

    @Test func commandsThePlayerTurnedOffAreDimmedWithoutAnAd() {
        let track = song(app: spotify, commands: [0, 1, 2, 5])
        let abilities = PlayerAbilities.resolve(track: track, connection: .connected, scripted: nil)
        #expect(!abilities.canSkipForward)
        #expect(abilities.canSkipBack)
        #expect(!abilities.canSeek)
        #expect(!abilities.isAdvertisement)
    }

    @Test func liveStreamsCantSeek() {
        let abilities = PlayerAbilities.resolve(track: song(app: spotify, duration: nil), connection: .connected, scripted: nil)
        #expect(!abilities.canSeek)
        #expect(abilities.canSkipForward)
    }
}

// MARK: Resume

struct ResumeOptionTests {
    func resolve(_ last: String?, _ connection: NowPlayingConnection = .connected, denied: Set<String> = [],
                 installed: Set<String> = [ScriptablePlayers.music, ScriptablePlayers.spotify, "com.google.Chrome"]) -> ResumeOption? {
        ResumeOption.resolve(lastPlayer: last, connection: connection, deniedApps: denied, isInstalled: installed.contains)
    }

    @Test func musicAndSpotifyResumeThemselves() {
        #expect(resolve(ScriptablePlayers.music) == .app(ScriptablePlayers.music))
        #expect(resolve(ScriptablePlayers.spotify) == .app(ScriptablePlayers.spotify))
        #expect(resolve(ScriptablePlayers.spotify, .limited) == .app(ScriptablePlayers.spotify))
    }

    @Test func otherAppsHaveNoResume() {
        #expect(resolve("com.google.Chrome") == nil)
        #expect(resolve("com.apple.podcasts") == nil)
        #expect(resolve(nil) == nil)
    }

    @Test func refusedPermissionOffersTheWayToAllowIt() {
        #expect(resolve(ScriptablePlayers.spotify, denied: [ScriptablePlayers.spotify]) == .needsPermission(ScriptablePlayers.spotify))
    }

    @Test func uninstalledPlayersHaveNoResume() {
        #expect(resolve(ScriptablePlayers.spotify, installed: [ScriptablePlayers.music]) == nil)
    }

    @Test func practiceAlwaysResumesAndUnavailableNever() {
        #expect(resolve(nil, .practice) == .practice)
        #expect(resolve(ScriptablePlayers.music, .unavailable(reason: "x")) == nil)
    }
}

// MARK: The "Open ▾" apps

struct MediaAppsTests {
    @Test func mainAppIsTheLastPlayerIfInstalled() {
        let installed: Set<String> = ["com.google.Chrome", "com.apple.Music"]
        #expect(MediaApps.mainApp(lastPlayer: "com.google.Chrome", isInstalled: installed.contains) == "com.google.Chrome")
        #expect(MediaApps.mainApp(lastPlayer: "com.gone.App", isInstalled: installed.contains) == "com.apple.Music")
        #expect(MediaApps.mainApp(lastPlayer: nil, isInstalled: installed.contains) == "com.apple.Music")
    }

    @Test func mainAppFallsBackToTheFirstInstalledKnownApp() {
        let installed: Set<String> = ["org.videolan.vlc", "com.spotify.client"]
        #expect(MediaApps.mainApp(lastPlayer: nil, isInstalled: installed.contains) == "com.spotify.client")
        #expect(MediaApps.mainApp(lastPlayer: nil, isInstalled: { _ in false }) == nil)
        #expect(MediaApps.mainApp(lastPlayer: "io.github.sickpancake.PancakeNotch.practice", isInstalled: { $0 == "io.github.sickpancake.PancakeNotch.practice" }) == nil)
    }

    @Test func menuListsSeenAppsFirstWithoutDuplicatesOrTheMainApp() {
        let installed: Set<String> = ["com.apple.Music", "com.spotify.client", "com.google.Chrome", "com.apple.podcasts", "org.videolan.vlc"]
        let apps = MediaApps.menuApps(
            seen: ["com.google.Chrome", "com.spotify.client", "com.gone.App", "com.apple.Music"],
            main: "com.apple.Music",
            isInstalled: installed.contains
        )
        #expect(apps == ["com.google.Chrome", "com.spotify.client", "com.apple.podcasts", "org.videolan.vlc"])
    }

    @Test func menuIsEmptyWhenNothingElseIsInstalled() {
        #expect(MediaApps.menuApps(seen: [], main: "com.apple.Music", isInstalled: { $0 == "com.apple.Music" }).isEmpty)
    }
}

// MARK: Ads

struct SpotifyAdTests {
    @Test func adAddressesAreAds() {
        #expect(SpotifyAd.isAdAddress("spotify:ad:000000012c9e7a6b"))
        #expect(!SpotifyAd.isAdAddress("spotify:track:4uLU6hMCjMI75M1A2tKUQC"))
        #expect(!SpotifyAd.isAdAddress(nil))
    }

    @Test func withoutAnAddressPopularityAndTrackNumberDecide() {
        #expect(SpotifyAd.isAd(address: "", popularity: 0, trackNumber: 0))
        #expect(!SpotifyAd.isAd(address: "", popularity: 54, trackNumber: 3))
        #expect(!SpotifyAd.isAd(address: nil, popularity: nil, trackNumber: nil))
        // An address wins over the numbers (a song can have popularity 0).
        #expect(!SpotifyAd.isAd(address: "spotify:track:1", popularity: 0, trackNumber: 0))
    }

    @Test func readingsFromAppleScript() {
        let ad = PlayerReadingScripts.reading(title: "Advertisement", shuffle: "tracks", repeatMode: "playlist",
                                              address: "spotify:ad:1", popularity: 0, trackNumber: 0)
        #expect(ad.isAdvertisement)
        #expect(ad.modes == ScriptedModes(shuffle: .tracks, repeatMode: .playlist))
        let music = PlayerReadingScripts.reading(title: "Song", shuffle: "albums", repeatMode: "track",
                                                 address: "", popularity: nil, trackNumber: nil)
        #expect(!music.isAdvertisement)
        #expect(music.modes == ScriptedModes(shuffle: .albums, repeatMode: .track))
    }

    @Test func parsesTheScriptList() throws {
        let list = NSAppleEventDescriptor.list()
        let items: [NSAppleEventDescriptor] = [
            NSAppleEventDescriptor(string: "ok"), NSAppleEventDescriptor(string: "Advertisement"),
            NSAppleEventDescriptor(string: "off"), NSAppleEventDescriptor(string: "off"),
            NSAppleEventDescriptor(string: "spotify:ad:42"), NSAppleEventDescriptor(int32: 0), NSAppleEventDescriptor(int32: 0),
        ]
        for (index, item) in items.enumerated() { list.insert(item, at: index + 1) }
        let reading = try #require(PlayerReadingScripts.parse(list))
        #expect(reading.title == "Advertisement")
        #expect(reading.isAdvertisement)
        #expect(reading.modes == ScriptedModes(shuffle: .off, repeatMode: .off))
        let stopped = NSAppleEventDescriptor.list()
        stopped.insert(NSAppleEventDescriptor(string: "stopped"), at: 1)
        #expect(PlayerReadingScripts.parse(stopped) == nil)
    }

    @Test func spotifysAnnouncementFlagsAds() throws {
        let info = try #require(PlayerNotificationInfo.spotify([
            "Player State": "Playing", "Name": "Advertisement", "Track ID": "spotify:ad:9",
        ]))
        #expect(info.track(previous: nil, at: Date())?.isAdvertisement == true)
        let song = try #require(PlayerNotificationInfo.spotify([
            "Player State": "Playing", "Name": "Song", "Track ID": "spotify:track:9",
        ]))
        #expect(song.track(previous: nil, at: Date())?.isAdvertisement == false)
    }

    @Test @MainActor func helperReportsGetSpotifysAdMark() {
        let ad = NowPlayingTrack(title: "Advertisement", bundleID: ScriptablePlayers.spotify)
        let marked = CompositeBackend.marking(NowPlayingUpdate(track: ad), spotifyAdTitle: "Advertisement")
        #expect(marked.track?.isAdvertisement == true)
        let other = NowPlayingTrack(title: "Advertisement", bundleID: "com.google.Chrome")
        #expect(CompositeBackend.marking(NowPlayingUpdate(track: other), spotifyAdTitle: "Advertisement").track?.isAdvertisement == false)
        #expect(CompositeBackend.marking(NowPlayingUpdate(track: ad), spotifyAdTitle: nil).track?.isAdvertisement == false)
    }

    @Test func enabledCommandsComeFromTheHelper() throws {
        var parser = AdapterStreamParser()
        let line = Data((#"{"type":"data","diff":false,"payload":{"title":"S","bundleIdentifier":"com.spotify.client","playing":true,"enabledCommands":[0,1,2,4,5,8,9,10,11,24]}}"# + "\n").utf8)
        let track = try #require(parser.feed(line, receivedAt: Date())?.track)
        #expect(track.enabledCommands == [0, 1, 2, 4, 5, 8, 9, 10, 11, 24])
        let diff = Data((#"{"type":"data","diff":true,"payload":{"enabledCommands":null}}"# + "\n").utf8)
        #expect(try #require(parser.feed(diff, receivedAt: Date())?.track).enabledCommands == nil)
    }
}

// MARK: Center with AppleScript

@MainActor
final class FakeScripting: PlayerScripting {
    var permissionAnswer: Bool?
    var readResult: Result<ScriptedPlayerReading?, ScriptFailure> = .success(nil)
    var sendResult: Result<Void, ScriptFailure> = .success(())
    var playResult: Result<Void, ScriptFailure> = .success(())
    var reads: [String] = []
    var sent: [(NowPlayingCommand, String)] = []
    var played: [String] = []

    func permission(for bundleID: String, completion: @escaping @MainActor (Bool?) -> Void) {
        completion(permissionAnswer)
    }

    func read(_ bundleID: String, completion: @escaping @MainActor (Result<ScriptedPlayerReading?, ScriptFailure>) -> Void) {
        reads.append(bundleID)
        completion(readResult)
    }

    func send(_ command: NowPlayingCommand, to bundleID: String, completion: @escaping @MainActor (Result<Void, ScriptFailure>) -> Void) {
        sent.append((command, bundleID))
        completion(sendResult)
    }

    func play(_ bundleID: String, completion: @escaping @MainActor (Result<Void, ScriptFailure>) -> Void) {
        played.append(bundleID)
        completion(playResult)
    }
}

@MainActor
struct CenterScriptingTests {
    final class Viewer {}

    func makeCenter(scripting: FakeScripting) -> (NowPlayingCenter, FakeBackend) {
        let suite = "CenterScriptingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let backend = FakeBackend()
        let center = NowPlayingCenter(settings: NowPlayingSettings(defaults: defaults), backend: backend, scripting: scripting)
        center.isInstalled = { _ in true }
        center.start()
        backend.onConnectionChange?(.connected)
        return (center, backend)
    }

    func spotifySong(_ title: String = "Song") -> NowPlayingTrack {
        NowPlayingTrack(title: title, duration: 200, bundleID: ScriptablePlayers.spotify)
    }

    func reading(ad: Bool = false, shuffle: ShuffleMode = .off) -> ScriptedPlayerReading {
        ScriptedPlayerReading(title: "Song", modes: ScriptedModes(shuffle: shuffle, repeatMode: .off), isAdvertisement: ad)
    }

    @Test func openingTheNotchReadsSpotifysModes() {
        let scripting = FakeScripting()
        scripting.readResult = .success(reading(shuffle: .tracks))
        let (center, backend) = makeCenter(scripting: scripting)
        backend.onUpdate?(NowPlayingUpdate(track: spotifySong()))
        // Closed and never allowed: no question, no reading.
        #expect(scripting.reads.isEmpty)
        #expect(!center.abilities.canShuffle)
        let viewer = Viewer()
        center.viewerOpened(viewer)
        #expect(scripting.reads == [ScriptablePlayers.spotify])
        #expect(center.abilities.shuffleRoute == .script)
        #expect(center.abilities.shuffle == .tracks)
    }

    @Test func aClosedNotchChecksSpotifyForAdsOnlyOnceAllowed() {
        let scripting = FakeScripting()
        scripting.permissionAnswer = true
        scripting.readResult = .success(reading(ad: true))
        let (center, backend) = makeCenter(scripting: scripting)
        backend.onUpdate?(NowPlayingUpdate(track: spotifySong("Advertisement")))
        #expect(scripting.reads.count == 1)
        #expect(center.track?.isAdvertisement == true)
        #expect(!center.abilities.canSkipForward)
        #expect(!center.abilities.canSeek)
        // The next song isn't an ad any more.
        scripting.readResult = .success(reading(ad: false))
        backend.onUpdate?(NowPlayingUpdate(track: spotifySong("Next song")))
        #expect(center.track?.isAdvertisement == false)
        #expect(center.abilities.canSkipForward)
    }

    @Test func refusedPermissionHidesModesAndResume() {
        let scripting = FakeScripting()
        scripting.permissionAnswer = false
        let (center, backend) = makeCenter(scripting: scripting)
        backend.onUpdate?(NowPlayingUpdate(track: spotifySong()))
        center.viewerOpened(Viewer())
        #expect(scripting.reads.isEmpty)
        #expect(center.isAutomationDenied(ScriptablePlayers.spotify))
        #expect(!center.abilities.canShuffle)
        backend.onUpdate?(NowPlayingUpdate(track: nil))
        #expect(center.resumeOption == .needsPermission(ScriptablePlayers.spotify))
    }

    @Test func aScriptRefusedLaterHidesTheModes() {
        let scripting = FakeScripting()
        scripting.readResult = .success(reading())
        let (center, backend) = makeCenter(scripting: scripting)
        backend.onUpdate?(NowPlayingUpdate(track: spotifySong()))
        center.viewerOpened(Viewer())
        #expect(center.abilities.canShuffle)
        scripting.sendResult = .failure(.notPermitted)
        center.setShuffle(.tracks)
        #expect(!center.abilities.canShuffle)
        #expect(center.isAutomationDenied(ScriptablePlayers.spotify))
        #expect(backend.sent.isEmpty)
    }

    @Test func aFailedModeChangeGoesBack() {
        let scripting = FakeScripting()
        scripting.readResult = .success(reading())
        let (center, backend) = makeCenter(scripting: scripting)
        backend.onUpdate?(NowPlayingUpdate(track: spotifySong()))
        center.viewerOpened(Viewer())
        scripting.sendResult = .failure(.failed(code: -1708))
        center.setRepeat(.playlist)
        #expect(center.abilities.repeatMode == .off)
        #expect(scripting.sent.count == 1)
    }

    @Test func aModeChangeShowsAtOnceAndIsConfirmed() async throws {
        let scripting = FakeScripting()
        scripting.readResult = .success(reading())
        let (center, backend) = makeCenter(scripting: scripting)
        backend.onUpdate?(NowPlayingUpdate(track: spotifySong()))
        center.viewerOpened(Viewer())
        center.setShuffle(.tracks)
        #expect(center.abilities.shuffle == .tracks)
        #expect(scripting.sent.first?.0 == .setShuffle(.tracks))
        // Spotify answers that it really did change.
        scripting.readResult = .success(reading(shuffle: .tracks))
        try await Task.sleep(for: NowPlayingCenter.modeCheckDelay + .milliseconds(300))
        #expect(scripting.reads.count == 2)
        #expect(center.abilities.shuffle == .tracks)
    }

    @Test func resumeTellsTheLastPlayerNotMacOS() {
        let scripting = FakeScripting()
        let (center, backend) = makeCenter(scripting: scripting)
        backend.onUpdate?(NowPlayingUpdate(track: spotifySong()))
        backend.onUpdate?(NowPlayingUpdate(track: nil))
        #expect(center.resumeOption == .app(ScriptablePlayers.spotify))
        center.resume()
        #expect(scripting.played == [ScriptablePlayers.spotify])
        #expect(backend.sent.isEmpty)
    }

    @Test func resumeRefusedTurnsIntoAllow() {
        let scripting = FakeScripting()
        scripting.playResult = .failure(.notPermitted)
        let (center, backend) = makeCenter(scripting: scripting)
        backend.onUpdate?(NowPlayingUpdate(track: NowPlayingTrack(title: "Song", bundleID: ScriptablePlayers.music)))
        backend.onUpdate?(NowPlayingUpdate(track: nil))
        center.resume()
        #expect(center.resumeOption == .needsPermission(ScriptablePlayers.music))
    }

    @Test func browsersHaveNoResume() {
        let scripting = FakeScripting()
        let (center, backend) = makeCenter(scripting: scripting)
        backend.onUpdate?(NowPlayingUpdate(track: NowPlayingTrack(title: "Video", bundleID: "com.google.Chrome")))
        backend.onUpdate?(NowPlayingUpdate(track: nil))
        #expect(center.resumeOption == nil)
        center.resume()
        #expect(scripting.played.isEmpty)
        #expect(backend.sent.isEmpty)
    }

    @Test func musicWithModesFromTheHelperIsntAsked() {
        let scripting = FakeScripting()
        let (center, backend) = makeCenter(scripting: scripting)
        backend.onUpdate?(NowPlayingUpdate(track: NowPlayingTrack(title: "Song", bundleID: ScriptablePlayers.music,
                                                                  shuffle: .off, repeatMode: .off)))
        center.viewerOpened(Viewer())
        #expect(scripting.reads.isEmpty)
        #expect(center.abilities.shuffleRoute == .player)
        center.setShuffle(.tracks)
        #expect(backend.sent == [.setShuffle(.tracks)])
    }

    @Test func practiceSnapshotAdIsAnAd() {
        let center = NowPlayingCenter.practiceSnapshot(playing: true, elapsed: 5, ad: true)
        #expect(center.track?.isAdvertisement == true)
        #expect(!center.abilities.canSkipForward)
        #expect(center.resumeOption == .practice)
    }
}
