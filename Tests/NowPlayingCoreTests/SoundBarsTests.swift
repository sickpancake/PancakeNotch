import CoreAudio
import Foundation
import Testing
@testable import NowPlayingCore

// MARK: Measuring

struct LevelAnalyzerTests {
    /// `seconds` of a sine tone at `frequency`, fed in blocks of 512 like Core Audio does.
    private func feed(_ analyzer: LevelAnalyzer, frequency: Double, amplitude: Float = 0.5, seconds: Double = 0.1) {
        let rate = analyzer.sampleRate
        let total = Int(rate * seconds)
        var samples = [Float](repeating: 0, count: total)
        for index in 0..<total {
            samples[index] = amplitude * Float(sin(2 * Double.pi * frequency * Double(index) / rate))
        }
        var start = 0
        while start < total {
            let count = min(512, total - start)
            samples.withUnsafeBufferPointer { analyzer.process($0.baseAddress! + start, frames: count) }
            start += count
        }
    }

    @Test func aLowToneLightsTheFirstBar() {
        let analyzer = LevelAnalyzer()
        feed(analyzer, frequency: 100)
        let bands = analyzer.rawBands
        #expect(bands[0] > 0.5)
        #expect(bands[0] > bands[1] && bands[0] > bands[2] && bands[0] > bands[3])
        #expect(bands[3] < 0.2)
    }

    @Test func aHighToneLightsTheLastBar() {
        let analyzer = LevelAnalyzer()
        feed(analyzer, frequency: 5000)
        let bands = analyzer.rawBands
        #expect(bands[3] > 0.5)
        #expect(bands[3] > bands[0] && bands[3] > bands[1] && bands[3] > bands[2])
        #expect(bands[0] < 0.2)
    }

    @Test func aMiddleToneLightsAMiddleBar() {
        let analyzer = LevelAnalyzer()
        feed(analyzer, frequency: 1200)
        let bands = analyzer.rawBands
        #expect(bands[2] > bands[0] && bands[2] > bands[3])
    }

    @Test func silenceIsZeroAndNotHeard() {
        let analyzer = LevelAnalyzer()
        feed(analyzer, frequency: 440, amplitude: 0)
        #expect(analyzer.rawBands == .zero)
        #expect(analyzer.rawLoudness == 0)
        #expect(analyzer.reading.levels == .zero)
        #expect(!analyzer.reading.heardSound)
        #expect(abs(analyzer.reading.audioSeconds - 0.1) < 0.01)
    }

    @Test func soundIsHeard() {
        let analyzer = LevelAnalyzer()
        feed(analyzer, frequency: 440, amplitude: 0.001)
        #expect(analyzer.reading.heardSound)
    }

    @Test func louderIsHigher() {
        let quiet = LevelAnalyzer()
        feed(quiet, frequency: 440, amplitude: 0.02)
        let loud = LevelAnalyzer()
        feed(loud, frequency: 440, amplitude: 0.5)
        #expect(loud.rawLoudness > quiet.rawLoudness)
        #expect(loud.rawLoudness > 0.8)
        // Loudness bars differ a little from each other, so they don't move as one block.
        let bars = loud.reading.levels.loudness
        #expect(bars[0] != bars[1])
        #expect(bars.max() <= 1 && bars.min() > 0)
    }

    @Test func levelsAreSmoothedAndReset() {
        let analyzer = LevelAnalyzer()
        feed(analyzer, frequency: 100, seconds: 0.5)
        #expect(analyzer.reading.levels.bands[0] > 0.5)
        analyzer.reset()
        #expect(analyzer.reading.levels == .zero)
        #expect(!analyzer.reading.heardSound)
        #expect(analyzer.reading.audioSeconds == 0)
    }

    @Test func readsOneChannelOfInterleavedSound() {
        let analyzer = LevelAnalyzer()
        let frames = 2048
        var stereo = [Float](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            // Left: a low tone. Right: silence.
            stereo[frame * 2] = 0.5 * Float(sin(2 * Double.pi * 100 * Double(frame) / analyzer.sampleRate))
        }
        stereo.withUnsafeBufferPointer { analyzer.process($0.baseAddress!, frames: frames, stride: 2) }
        #expect(analyzer.rawBands[0] > 0.5)
    }

    @Test func otherSampleRatesKeepTheBands() {
        let analyzer = LevelAnalyzer()
        analyzer.configure(sampleRate: 44_100)
        feed(analyzer, frequency: 5000)
        #expect(analyzer.rawBands[3] > analyzer.rawBands[0])
    }

    @Test func levelMapping() {
        let range: (floor: Float, ceiling: Float) = (-50, -10)
        #expect(LevelAnalyzer.level(decibels: -60, range: range) == 0)
        #expect(LevelAnalyzer.level(decibels: -30, range: range) == 0.5)
        #expect(LevelAnalyzer.level(decibels: 0, range: range) == 1)
        #expect(LevelAnalyzer.decibels(0) < -100)
        #expect(abs(LevelAnalyzer.decibels(1)) < 0.001)
    }
}

struct LevelSmootherTests {
    @Test func risesFast() {
        var smoother = LevelSmoother(attack: 0.03, decay: 0.2)
        smoother.step(toward: 1, seconds: 0.06)
        #expect(smoother.value > 0.8)
    }

    @Test func fallsSlowly() {
        var smoother = LevelSmoother(attack: 0.03, decay: 0.2)
        smoother.step(toward: 1, seconds: 1)
        smoother.step(toward: 0, seconds: 0.06)
        #expect(smoother.value > 0.6)
        smoother.step(toward: 0, seconds: 1)
        #expect(smoother.value < 0.01)
    }

    @Test func sameResultHoweverOftenSoundArrives() {
        var once = LevelSmoother(attack: 0.03, decay: 0.2)
        once.step(toward: 1, seconds: 0.04)
        var often = LevelSmoother(attack: 0.03, decay: 0.2)
        for _ in 0..<4 { often.step(toward: 1, seconds: 0.01) }
        #expect(abs(once.value - often.value) < 0.001)
    }

    @Test func noTimeNoChange() {
        var smoother = LevelSmoother(attack: 0.03, decay: 0.2)
        #expect(smoother.step(toward: 1, seconds: 0) == 0)
    }
}

// MARK: Permission

struct AccessProbeTests {
    /// Feeds silence in 1/30 s steps for `seconds`, returning every verdict.
    private func silence(_ probe: inout AccessProbe, seconds: Double, running: Bool?, from start: Double = 0) -> [AccessProbe.Verdict] {
        var verdicts: [AccessProbe.Verdict] = []
        let step = 1.0 / 30
        var time = start
        while time < start + seconds - 0.0001 {
            time += step
            verdicts.append(probe.update(heardSound: false, audioSeconds: time, elapsed: time, isOutputRunning: running))
        }
        return verdicts
    }

    @Test func soundMeansAllowed() {
        var probe = AccessProbe()
        _ = silence(&probe, seconds: 1, running: true)
        #expect(probe.update(heardSound: true, audioSeconds: 1.1, elapsed: 1.1, isOutputRunning: true) == .hearing)
        // Once heard, later silence (a quiet passage) isn't a refusal.
        let later = silence(&probe, seconds: 30, running: true, from: 1.1)
        #expect(later.allSatisfy { $0 == .hearing })
    }

    @Test func silenceWhileTheAppPlaysMeansNotAllowed() {
        var probe = AccessProbe()
        let verdicts = silence(&probe, seconds: 16, running: true)
        // Waiting first, then gentle motion meanwhile, a few fresh tries, then "not allowed".
        #expect(verdicts.first == .waiting)
        let firstFallback = verdicts.firstIndex(of: .notHearing) ?? 0
        #expect(abs(Double(firstFallback + 1) / 30 - AccessProbe.fallbackAfter) < 0.1)
        #expect(verdicts.filter { $0 == .retry }.count == 2)
        let denied = verdicts.firstIndex(of: .denied) ?? 0
        #expect(abs(Double(denied + 1) / 30 - AccessProbe.deniedAfter) < 0.1)
    }

    @Test func silenceWhileTheAppIsQuietIsNotARefusal() {
        var probe = AccessProbe()
        let verdicts = silence(&probe, seconds: 40, running: false)
        #expect(!verdicts.contains(.denied))
        #expect(!verdicts.contains(.retry))
        #expect(verdicts.last == .notHearing)
    }

    @Test func unknownOutputIsNotARefusal() {
        var probe = AccessProbe()
        let verdicts = silence(&probe, seconds: 40, running: nil)
        #expect(!verdicts.contains(.denied))
    }

    @Test func aRestartedTapKeepsCounting() {
        var probe = AccessProbe()
        _ = silence(&probe, seconds: 10, running: true)
        probe.meterRestarted()
        var verdicts: [AccessProbe.Verdict] = []
        for step in 1...200 {
            let audio = Double(step) / 30
            verdicts.append(probe.update(heardSound: false, audioSeconds: audio, elapsed: 10 + audio, isOutputRunning: true))
        }
        let denied = verdicts.firstIndex(of: .denied) ?? 0
        #expect(abs(Double(denied + 1) / 30 - 5) < 0.1)
    }
}

// MARK: Deciding

struct SoundBarsModeTests {
    private func mode(
        _ style: SoundBarsStyle, access: SoundBarsAccess = .unknown, practice: Bool = false, source: Bool = true,
        playing: Bool = true, visible: Bool = true, reduceMotion: Bool = false
    ) -> SoundBarsMode {
        SoundBarsMode.resolve(style: style, access: access, isPractice: practice, hasSource: source,
                              isPlaying: playing, isVisible: visible, reduceMotion: reduceMotion)
    }

    @Test func followTheMusicListensOnlyWhenEverythingFits() {
        #expect(mode(.followMusic) == .real)
        #expect(mode(.followMusic, access: .allowed) == .real)
        #expect(mode(.followMusic, access: .denied) == .gentle)
        #expect(mode(.followMusic, practice: true) == .gentle)
        #expect(mode(.followMusic, source: false) == .gentle)
        #expect(mode(.followMusic, playing: false) == .gentle)
        #expect(mode(.followMusic, visible: false) == .off)
        #expect(mode(.followMusic, reduceMotion: true) == .still)
    }

    @Test func gentleMotion() {
        #expect(mode(.gentle) == .gentle)
        #expect(mode(.gentle, practice: true) == .gentle)
        #expect(mode(.gentle, playing: false) == .gentle)
        #expect(mode(.gentle, visible: false) == .off)
        #expect(mode(.gentle, reduceMotion: true) == .still)
    }

    @Test func still() {
        #expect(mode(.still) == .still)
        #expect(mode(.still, playing: false) == .still)
        #expect(mode(.still, visible: false) == .off)
    }
}

struct SoundSourceTests {
    @Test func needsSomethingToFind() {
        #expect(SoundSourceID(processID: nil, bundleIDs: [nil, ""]) == nil)
        #expect(SoundSourceID(processID: 42, bundleIDs: [])?.processID == 42)
    }

    @Test func dropsRepeatsAndBlanks() {
        let source = SoundSourceID(processID: nil, bundleIDs: ["com.google.Chrome", nil, "", "com.google.Chrome"])
        #expect(source?.bundleIDs == ["com.google.Chrome"])
    }

    @Test func fromATrack() {
        let track = NowPlayingTrack(title: "Song", bundleID: "com.google.Chrome", sourceBundleID: "com.google.Chrome.helper", processID: 7)
        let source = SoundSourceID(track: track)
        #expect(source?.processID == 7)
        #expect(source?.bundleIDs == ["com.google.Chrome", "com.google.Chrome.helper"])
    }
}

struct AudioProcessSelectionTests {
    private let own: Int32 = 1
    private func process(_ id: AudioObjectID, pid: Int32, _ bundleID: String, running: Bool = false) -> AudioProcess {
        AudioProcess(objectID: id, processID: pid, bundleID: bundleID, isRunningOutput: running)
    }

    @Test func spotifyPlaysFromItsOwnProcess() {
        let source = SoundSourceID(processID: 500, bundleIDs: ["com.spotify.client"])!
        let selection = AudioProcessSelection(source: source, processes: [
            process(10, pid: 500, "com.spotify.client", running: true),
            process(11, pid: 600, "com.apple.Music", running: true),
        ], ownProcessID: own)
        #expect(selection.watched == [10])
        #expect(selection.tapped == [10])
        #expect(selection.isRunningOutput)
    }

    @Test func aBrowserPlaysFromAHelper() {
        let source = SoundSourceID(processID: 700, bundleIDs: ["com.google.Chrome"])!
        let selection = AudioProcessSelection(source: source, processes: [
            process(20, pid: 700, "com.google.Chrome"),
            process(21, pid: 701, "com.google.Chrome.helper", running: true),
            process(22, pid: 702, "com.google.Chrome.helper.Renderer"),
            process(23, pid: 800, "com.google.ChromeRemoteDesktop", running: true),
        ], ownProcessID: own)
        #expect(selection.watched == [20, 21, 22])
        // Only the one making sound is listened to.
        #expect(selection.tapped == [21])
        #expect(selection.isRunningOutput)
    }

    @Test func bundleIDsMatchWhateverTheCase() {
        let source = SoundSourceID(processID: nil, bundleIDs: ["company.thebrowser.Browser"])!
        let selection = AudioProcessSelection(source: source, processes: [
            process(30, pid: 900, "company.thebrowser.browser.helper", running: true),
        ], ownProcessID: own)
        #expect(selection.tapped == [30])
    }

    @Test func quietAppListensToTheNamedProcess() {
        let source = SoundSourceID(processID: 700, bundleIDs: ["com.google.Chrome"])!
        let selection = AudioProcessSelection(source: source, processes: [
            process(20, pid: 700, "com.google.Chrome"),
            process(21, pid: 701, "com.google.Chrome.helper"),
        ], ownProcessID: own)
        #expect(selection.tapped == [20])
        #expect(!selection.isRunningOutput)
    }

    @Test func withoutANamedProcessListensToAll() {
        let source = SoundSourceID(processID: nil, bundleIDs: ["com.google.Chrome"])!
        let selection = AudioProcessSelection(source: source, processes: [
            process(20, pid: 700, "com.google.Chrome"),
            process(21, pid: 701, "com.google.Chrome.helper"),
        ], ownProcessID: own)
        #expect(selection.tapped == [20, 21])
    }

    @Test func neverItselfAndNothingWhenNotFound() {
        let source = SoundSourceID(processID: own, bundleIDs: ["io.github.sickpancake.PancakeNotch"])!
        let selection = AudioProcessSelection(source: source, processes: [
            process(40, pid: own, "io.github.sickpancake.PancakeNotch", running: true),
        ], ownProcessID: own)
        #expect(selection.watched.isEmpty)
        #expect(selection.tapped.isEmpty)
    }
}

// MARK: Settings

@MainActor
struct SoundBarsSettingsTests {
    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "io.github.sickpancake.PancakeNotch.tests.soundBars.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func defaults() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = NowPlayingSettings(defaults: defaults)
        #expect(settings.soundBars == .gentle)
        #expect(settings.soundBarsShow == .bands)
        #expect(settings.soundBarsAccess == .unknown)
    }

    @Test func remembersChoices() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = NowPlayingSettings(defaults: defaults)
        settings.soundBars = .followMusic
        settings.soundBarsShow = .loudness
        settings.soundBarsAccess = .denied
        #expect(defaults.string(forKey: "nowPlaying.soundBars") == "followMusic")
        #expect(defaults.string(forKey: "nowPlaying.soundBarsShow") == "loudness")
        let again = NowPlayingSettings(defaults: defaults)
        #expect(again.soundBars == .followMusic)
        #expect(again.soundBarsShow == .loudness)
        #expect(again.soundBarsAccess == .denied)
    }

    @Test func unknownValuesFallBackToDefaults() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("dancing", forKey: "nowPlaying.soundBars")
        defaults.set(3, forKey: "nowPlaying.soundBarsShow")
        let settings = NowPlayingSettings(defaults: defaults)
        #expect(settings.soundBars == .gentle)
        #expect(settings.soundBarsShow == .bands)
    }
}
