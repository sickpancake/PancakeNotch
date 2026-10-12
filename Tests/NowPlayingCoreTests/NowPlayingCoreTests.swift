import AppKit
import Foundation
import Testing
@testable import NowPlayingCore

// MARK: Track

struct NowPlayingTrackTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func elapsedMovesOnWhilePlaying() {
        let track = NowPlayingTrack(title: "Song", duration: 200, elapsed: 10, elapsedDate: start, isPlaying: true)
        #expect(track.elapsed(at: start.addingTimeInterval(5)) == 15)
    }

    @Test func elapsedStaysPutWhilePaused() {
        let track = NowPlayingTrack(title: "Song", duration: 200, elapsed: 10, elapsedDate: start, isPlaying: false)
        #expect(track.elapsed(at: start.addingTimeInterval(60)) == 10)
        #expect(track.playbackRate == 0)
    }

    @Test func elapsedStopsAtTheEnd() {
        let track = NowPlayingTrack(title: "Song", duration: 100, elapsed: 95, elapsedDate: start, isPlaying: true)
        #expect(track.elapsed(at: start.addingTimeInterval(30)) == 100)
    }

    @Test func playingWithZeroRateCountsAsNormalSpeed() {
        let track = NowPlayingTrack(title: "Song", elapsedDate: start, playbackRate: 0, isPlaying: true)
        #expect(track.playbackRate == 1)
    }

    @Test func identityChangesWithTheSong() {
        let one = NowPlayingTrack(title: "A", artist: "X", bundleID: "app")
        var two = one
        two.elapsed = 50
        #expect(one.identity == two.identity)
        two.title = "B"
        #expect(one.identity != two.identity)
    }
}

// MARK: Adapter stream

struct AdapterStreamTests {
    let now = Date(timeIntervalSince1970: 1_791_773_212)

    private func line(_ json: String) -> Data { Data((json + "\n").utf8) }

    @Test func fullSnapshotBecomesATrack() throws {
        var parser = AdapterStreamParser()
        let update = parser.feed(line(#"{"type":"data","diff":false,"payload":{"title":"I need a good one.","artist":"Matthew Beaver","album":"","bundleIdentifier":"com.google.Chrome","playing":true,"playbackRate":1,"durationMicros":28601000,"elapsedTimeMicros":1506654,"timestampEpochMicros":1791773211691171,"processIdentifier":88829}}"#), receivedAt: now)
        let track = try #require(update?.track)
        #expect(track.title == "I need a good one.")
        #expect(track.artist == "Matthew Beaver")
        #expect(track.bundleID == "com.google.Chrome")
        #expect(track.isPlaying)
        #expect(abs((track.duration ?? 0) - 28.601) < 0.001)
        #expect(abs(track.elapsed - 1.506654) < 0.001)
        #expect(abs(track.elapsedDate.timeIntervalSince1970 - 1_791_773_211.691171) < 0.001)
    }

    @Test func emptyPayloadMeansNothingPlaying() {
        var parser = AdapterStreamParser()
        let update = parser.feed(line(#"{"type":"data","diff":false,"payload":{}}"#), receivedAt: now)
        #expect(update != nil)
        #expect(update?.track == nil)
    }

    @Test func diffChangesOnlyItsKeysAndNullRemoves() throws {
        var parser = AdapterStreamParser()
        _ = parser.feed(line(#"{"type":"data","diff":false,"payload":{"title":"Song","artist":"Band","album":"LP","bundleIdentifier":"com.apple.Music","playing":true,"durationMicros":200000000,"elapsedTimeMicros":0,"timestampEpochMicros":1791773211000000,"shuffleMode":3}}"#), receivedAt: now)
        let update = parser.feed(line(#"{"type":"data","diff":true,"payload":{"playing":false,"shuffleMode":null}}"#), receivedAt: now)
        let track = try #require(update?.track)
        #expect(track.title == "Song")
        #expect(track.album == "LP")
        #expect(!track.isPlaying)
        #expect(track.shuffle == nil)
    }

    @Test func parentAppIsTheOneShown() throws {
        var parser = AdapterStreamParser()
        let update = parser.feed(line(#"{"type":"data","diff":false,"payload":{"title":"Video","bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","playing":true}}"#), receivedAt: now)
        let track = try #require(update?.track)
        #expect(track.bundleID == "com.apple.Safari")
        #expect(track.sourceBundleID == "com.apple.WebKit.GPU")
    }

    @Test func linesCanArriveInPieces() throws {
        var parser = AdapterStreamParser()
        let whole = #"{"type":"data","diff":false,"payload":{"title":"Split","bundleIdentifier":"a","playing":true}}"#
        let middle = whole.index(whole.startIndex, offsetBy: 30)
        let first = parser.feed(Data(whole[..<middle].utf8), receivedAt: now)
        #expect(first == nil)
        let update = parser.feed(Data((whole[middle...] + "\n").utf8), receivedAt: now)
        let track = try #require(update?.track)
        #expect(track.title == "Split")
    }

    @Test func modesMapToTheirNumbers() throws {
        var parser = AdapterStreamParser()
        let update = parser.feed(line(#"{"type":"data","diff":false,"payload":{"title":"S","bundleIdentifier":"a","playing":true,"shuffleMode":1,"repeatMode":2}}"#), receivedAt: now)
        let track = try #require(update?.track)
        #expect(track.shuffle == .off)
        #expect(track.repeatMode == .track)
    }

    @Test func commandsBecomeAdapterFunctions() {
        #expect(AdapterLocation.function(for: .play) == ["send", "0"])
        #expect(AdapterLocation.function(for: .pause) == ["send", "1"])
        #expect(AdapterLocation.function(for: .next) == ["send", "4"])
        #expect(AdapterLocation.function(for: .previous) == ["send", "5"])
        #expect(AdapterLocation.function(for: .seek(to: 1.5)) == ["seek", "1500000"])
        #expect(AdapterLocation.function(for: .setShuffle(.tracks)) == ["shuffle", "3"])
        #expect(AdapterLocation.function(for: .setRepeat(.playlist)) == ["repeat", "3"])
    }
}

// MARK: Fallback

struct FallbackPolicyTests {
    let start = Date(timeIntervalSince1970: 0)

    @Test func threeCrashesInAMinuteGiveUp() {
        var policy = FallbackPolicy()
        let result1 = policy.handle(.start)
        #expect(result1 == .startAdapter)
        let result2 = policy.handle(.adapterExited(at: start))
        #expect(result2 == .restartAdapter(after: 1))
        let result3 = policy.handle(.adapterExited(at: start.addingTimeInterval(5)))
        #expect(result3 == .restartAdapter(after: 2))
        let result4 = policy.handle(.adapterExited(at: start.addingTimeInterval(10)))
        #expect(result4 == .useFallback(.crashing))
        #expect(policy.source == .fallback)
    }

    @Test func crashesFarApartKeepRetrying() {
        var policy = FallbackPolicy()
        _ = policy.handle(.start)
        _ = policy.handle(.adapterExited(at: start))
        _ = policy.handle(.adapterExited(at: start.addingTimeInterval(100)))
        let result5 = policy.handle(.adapterExited(at: start.addingTimeInterval(200)))
        #expect(result5 != .useFallback(.crashing))
        #expect(policy.source == .adapter)
    }

    @Test func missingFilesUseTheFallback() {
        var policy = FallbackPolicy()
        _ = policy.handle(.start)
        let result6 = policy.handle(.adapterUnavailable)
        #expect(result6 == .useFallback(.unavailable))
    }

    @Test func silentHelperIsNoticed() {
        var policy = FallbackPolicy()
        _ = policy.handle(.start)
        _ = policy.handle(.adapterReported(nil, at: start))
        let action = policy.handle(.playerStartedPlaying(bundleID: "com.apple.Music", at: start.addingTimeInterval(1)))
        #expect(action == .scheduleSilenceCheck(bundleID: "com.apple.Music", notifiedAt: start.addingTimeInterval(1), after: 2))
        let result7 = policy.handle(.silenceCheck(bundleID: "com.apple.Music", notifiedAt: start.addingTimeInterval(1)))
        #expect(result7 == .useFallback(.silent))
    }

    @Test func workingHelperStays() {
        var policy = FallbackPolicy()
        _ = policy.handle(.start)
        _ = policy.handle(.playerStartedPlaying(bundleID: "com.apple.Music", at: start))
        let track = NowPlayingTrack(title: "Song", isPlaying: true, bundleID: "com.apple.Music")
        _ = policy.handle(.adapterReported(track, at: start.addingTimeInterval(0.5)))
        let result8 = policy.handle(.silenceCheck(bundleID: "com.apple.Music", notifiedAt: start))
        #expect(result8 == .none)
        #expect(policy.source == .adapter)
    }
}

// MARK: Music and Spotify announcements

struct PlayerNotificationTests {
    @Test func musicAnnouncement() throws {
        let info = try #require(PlayerNotificationInfo.music([
            "Player State": "Playing", "Name": "Song", "Artist": "Band", "Album": "LP", "Total Time": 180_000,
        ]))
        #expect(info.bundleID == "com.apple.Music")
        #expect(info.state == .playing)
        #expect(info.duration == 180)
        #expect(info.position == nil)
    }

    @Test func spotifyAnnouncement() throws {
        let info = try #require(PlayerNotificationInfo.spotify([
            "Player State": "Paused", "Name": "Song", "Artist": "Band", "Album": "LP",
            "Duration": 213_000, "Playback Position": 42.5, "Track ID": "spotify:track:1",
        ]))
        #expect(info.state == .paused)
        #expect(info.duration == 213)
        #expect(info.position == 42.5)
        #expect(info.trackID == "spotify:track:1")
    }

    @Test func spotifyOldSecondsDuration() throws {
        let info = try #require(PlayerNotificationInfo.spotify(["Player State": "Playing", "Duration": 284]))
        #expect(info.duration == 284)
    }

    @Test func unknownStateIsIgnored() {
        #expect(PlayerNotificationInfo.music(["Name": "Song"]) == nil)
    }
}

// MARK: Listening

struct ListeningTrackerTests {
    let start = Date(timeIntervalSince1970: 0)
    let song = NowPlayingTrack(title: "Song", artist: "Band", isPlaying: true, bundleID: "com.apple.Music")

    @Test func pauseEndsAStretch() throws {
        var tracker = ListeningTracker()
        let result9 = tracker.update(song, at: start)
        #expect(result9 == nil)
        var paused = song
        paused.isPlaying = false
        let ended = tracker.update(paused, at: start.addingTimeInterval(30))
        let record = try #require(ended)
        #expect(record.seconds == 30)
        #expect(record.title == "Song")
        #expect(record.started == start)
    }

    @Test func aLatePauseCountsOnlyUntilThePause() throws {
        var tracker = ListeningTracker()
        _ = tracker.update(song, at: start)
        // Paused after 40 s, but we only hear about it an hour later (the Mac slept).
        let paused = NowPlayingTrack(title: "Song", artist: "Band", elapsed: 40, elapsedDate: start.addingTimeInterval(40),
                                     isPlaying: false, bundleID: "com.apple.Music")
        let ended = tracker.update(paused, at: start.addingTimeInterval(3600))
        #expect(try #require(ended).seconds == 40)
    }

    @Test func shortStretchesDontCount() {
        var tracker = ListeningTracker()
        _ = tracker.update(song, at: start)
        let result10 = tracker.update(nil, at: start.addingTimeInterval(3))
        #expect(result10 == nil)
    }

    @Test func aNewSongEndsTheOldOne() throws {
        var tracker = ListeningTracker()
        _ = tracker.update(song, at: start)
        var next = song
        next.title = "Next"
        let ended = tracker.update(next, at: start.addingTimeInterval(60))
        let record = try #require(ended)
        #expect(record.title == "Song")
        #expect(tracker.isListening)
    }
}

// MARK: Center

@MainActor
final class FakeBackend: NowPlayingBackend {
    var onUpdate: ((NowPlayingUpdate) -> Void)?
    var onConnectionChange: ((NowPlayingConnection) -> Void)?
    var sent: [NowPlayingCommand] = []
    var started = 0
    var stopped = 0
    func start() { started += 1 }
    func stop() { stopped += 1 }
    func send(_ command: NowPlayingCommand) { sent.append(command) }
    var processID: pid_t? { nil }
}

@MainActor
struct NowPlayingCenterTests {
    final class Clock { var now = Date(timeIntervalSince1970: 1_000) }

    func makeCenter() -> (NowPlayingCenter, FakeBackend, Clock, UserDefaults) {
        let suite = "NowPlayingCenterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let backend = FakeBackend()
        let clock = Clock()
        let center = NowPlayingCenter(settings: NowPlayingSettings(defaults: defaults), backend: backend, now: { clock.now })
        center.start()
        return (center, backend, clock, defaults)
    }

    func song(_ title: String = "Song", playing: Bool = true, app: String = "com.spotify.client", at date: Date) -> NowPlayingTrack {
        NowPlayingTrack(title: title, artist: "Band", duration: 200, elapsed: 10, elapsedDate: date, isPlaying: playing, bundleID: app,
                        shuffle: .off, repeatMode: .off)
    }

    @Test func showsWhatTheBackendReports() {
        let (center, backend, clock, _) = makeCenter()
        backend.onUpdate?(NowPlayingUpdate(track: song(at: clock.now)))
        #expect(center.track?.title == "Song")
        #expect(center.lastPlayerBundleID == "com.spotify.client")
        #expect(center.seenApps == ["com.spotify.client"])
        #expect(backend.started == 1)
    }

    @Test func ignoredAppsAreHidden() async {
        let (center, backend, clock, _) = makeCenter()
        center.settings.ignore("com.google.Chrome")
        backend.onUpdate?(NowPlayingUpdate(track: song(app: "com.google.Chrome", at: clock.now)))
        #expect(center.track == nil)
        #expect(center.lastPlayerBundleID == nil)
        center.settings.unignore("com.google.Chrome")
        // The ignore list is observed: the change lands on the next main-actor turn.
        for _ in 0..<20 where center.track == nil { await Task.yield() }
        #expect(center.track?.title == "Song")
    }

    @Test func pauseShowsAtOnceAndIsSent() {
        let (center, backend, clock, _) = makeCenter()
        backend.onUpdate?(NowPlayingUpdate(track: song(at: clock.now)))
        clock.now = clock.now.addingTimeInterval(5)
        center.send(.pause)
        #expect(center.track?.isPlaying == false)
        #expect(center.track?.elapsed == 15)
        #expect(center.pausedSince == clock.now)
        #expect(backend.sent == [.pause])
    }

    @Test func aPressThePlayerNeverConfirmsGoesBack() async throws {
        let (center, backend, clock, _) = makeCenter()
        backend.onUpdate?(NowPlayingUpdate(track: song(at: clock.now)))
        center.send(.pause)
        #expect(center.track?.isPlaying == false)
        try await Task.sleep(for: NowPlayingCenter.confirmTimeout + .milliseconds(300))
        #expect(center.track?.isPlaying == true)
    }

    @Test func aConfirmedPressStays() async throws {
        let (center, backend, clock, _) = makeCenter()
        backend.onUpdate?(NowPlayingUpdate(track: song(at: clock.now)))
        center.send(.pause)
        backend.onUpdate?(NowPlayingUpdate(track: song(playing: false, at: clock.now)))
        try await Task.sleep(for: NowPlayingCenter.confirmTimeout + .milliseconds(300))
        #expect(center.track?.isPlaying == false)
    }

    @Test func seekAndModesShowAtOnce() {
        let (center, backend, clock, _) = makeCenter()
        backend.onUpdate?(NowPlayingUpdate(track: song(at: clock.now)))
        center.send(.seek(to: 120))
        center.send(.setShuffle(.tracks))
        center.send(.setRepeat(.track))
        #expect(center.track?.elapsed == 120)
        #expect(center.track?.shuffle == .tracks)
        #expect(center.track?.repeatMode == .track)
        #expect(backend.sent.count == 3)
    }

    @Test func listeningIsReportedWhenTheSongPauses() {
        let (center, backend, clock, _) = makeCenter()
        var records: [ListeningRecord] = []
        center.onListened = { records.append($0) }
        backend.onUpdate?(NowPlayingUpdate(track: song(at: clock.now)))
        clock.now = clock.now.addingTimeInterval(90)
        backend.onUpdate?(NowPlayingUpdate(track: song(playing: false, at: clock.now)))
        #expect(records.count == 1)
        #expect(records.first?.seconds == 90)
    }

    @Test func stopFlushesAndClears() {
        let (center, backend, clock, _) = makeCenter()
        var records: [ListeningRecord] = []
        center.onListened = { records.append($0) }
        backend.onUpdate?(NowPlayingUpdate(track: song(at: clock.now)))
        clock.now = clock.now.addingTimeInterval(20)
        center.stop()
        #expect(records.count == 1)
        #expect(center.track == nil)
        #expect(backend.stopped == 1)
    }

    @Test func songChangeIsAnnounced() {
        let (center, backend, clock, _) = makeCenter()
        var changes: [String] = []
        center.onSongChange = { changes.append($0.title) }
        backend.onUpdate?(NowPlayingUpdate(track: song("One", at: clock.now)))
        backend.onUpdate?(NowPlayingUpdate(track: song("One", playing: false, at: clock.now)))
        backend.onUpdate?(NowPlayingUpdate(track: song("Two", at: clock.now)))
        #expect(changes == ["One", "Two"])
    }

    @Test func artworkFollowsTheSong() {
        let (center, backend, clock, _) = makeCenter()
        let image = NSImage(size: NSSize(width: 4, height: 4))
        var track = song(at: clock.now)
        track.artworkID = "a"
        backend.onUpdate?(NowPlayingUpdate(track: track, artwork: image))
        #expect(center.artwork === image)
        // Same artwork ID, no image: unchanged.
        backend.onUpdate?(NowPlayingUpdate(track: track))
        #expect(center.artwork === image)
        // A song without artwork.
        track.artworkID = nil
        backend.onUpdate?(NowPlayingUpdate(track: track))
        #expect(center.artwork == nil)
    }
}

// MARK: Practice player

@MainActor
struct PracticePlayerTests {
    final class Clock { var now = Date(timeIntervalSince1970: 5_000) }

    func makePlayer() -> (PracticePlayer, Clock, () -> NowPlayingTrack?) {
        let clock = Clock()
        let player = PracticePlayer(now: { clock.now })
        var last: NowPlayingTrack?
        player.onUpdate = { last = $0.track }
        player.start()
        return (player, clock, { last })
    }

    @Test func startsPlayingTheFirstSong() {
        let (player, _, latest) = makePlayer()
        #expect(latest()?.title == PracticePlayer.songs[0].title)
        #expect(latest()?.isPlaying == true)
        #expect(latest()?.shuffle == .off)
        player.stop()
    }

    @Test func pauseKeepsThePosition() {
        let (player, clock, latest) = makePlayer()
        clock.now = clock.now.addingTimeInterval(12)
        player.send(.pause)
        #expect(latest()?.isPlaying == false)
        #expect(latest()?.elapsed == 12)
        player.stop()
    }

    @Test func nextAndPreviousMoveThroughTheSongs() {
        let (player, clock, latest) = makePlayer()
        player.send(.next)
        #expect(latest()?.title == PracticePlayer.songs[1].title)
        // Early in a song, back goes to the song before.
        player.send(.previous)
        #expect(latest()?.title == PracticePlayer.songs[0].title)
        // Later on, back restarts the song.
        clock.now = clock.now.addingTimeInterval(20)
        player.send(.previous)
        #expect(latest()?.title == PracticePlayer.songs[0].title)
        #expect(latest()?.elapsed == 0)
        // Back from the first song wraps around to the last.
        player.send(.previous)
        #expect(latest()?.title == PracticePlayer.songs[2].title)
        player.stop()
    }

    @Test func seekStaysInsideTheSong() {
        let (player, _, latest) = makePlayer()
        player.send(.seek(to: 10_000))
        #expect(latest()?.elapsed == PracticePlayer.songs[0].duration)
        player.send(.seek(to: 30))
        #expect(latest()?.elapsed == 30)
        player.stop()
    }

    @Test func modesAreReported() {
        let (player, _, latest) = makePlayer()
        player.send(.setRepeat(.track))
        player.send(.setShuffle(.tracks))
        #expect(latest()?.repeatMode == .track)
        #expect(latest()?.shuffle == .tracks)
        player.stop()
    }

    @Test func artworkIsDrawn() {
        #expect(PracticeArtwork.image(for: 0) != nil)
        #expect(PracticeArtwork.image(for: 1) != nil)
        #expect(PracticeArtwork.image(for: 2) != nil)
    }

    @Test func snapshotCenterIsReadyAtOnce() {
        let center = NowPlayingCenter.practiceSnapshot(playing: false, elapsed: 74)
        #expect(center.track?.elapsed(at: Date()) == 74)
        #expect(center.artwork != nil)
        #expect(center.connection == .practice)
        let empty = NowPlayingCenter.practiceSnapshot(playing: false, elapsed: 0, empty: true)
        #expect(empty.track == nil)
    }
}
