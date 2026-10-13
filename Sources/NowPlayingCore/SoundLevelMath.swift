import Accelerate
import Foundation

/// Heights for the four sound bars, each 0…1, worked out both ways so a setting change needs no restart.
public struct SoundLevels: Equatable, Sendable {
    /// Bass on the left to treble on the right.
    public var bands: SIMD4<Float>
    /// How loud it is, a little different per bar.
    public var loudness: SIMD4<Float>

    public static let zero = SoundLevels(bands: .zero, loudness: .zero)

    public init(bands: SIMD4<Float>, loudness: SIMD4<Float>) {
        self.bands = bands
        self.loudness = loudness
    }

    public func bars(_ show: SoundBarsShow) -> SIMD4<Float> {
        show == .bands ? bands : loudness
    }
}

/// What the meter has measured so far, handed from the audio thread to the main thread.
struct MeterReading: Sendable {
    var levels = SoundLevels.zero
    /// Anything but exact silence has come through since the meter started.
    var heardSound = false
    /// How much audio has come through, in seconds of sound.
    var audioSeconds: TimeInterval = 0
    /// Setting up the tap failed; nothing will come.
    var failed = false
}

/// Moves a level towards its target quickly when it rises and slowly when it falls, so the bars jump
/// with a beat and sink back gently. Time-based, so it looks the same however often audio arrives.
public struct LevelSmoother: Sendable {
    /// Seconds to cover most of a rise.
    public var attack: TimeInterval
    /// Seconds to cover most of a fall.
    public var decay: TimeInterval
    public private(set) var value: Float = 0

    public init(attack: TimeInterval, decay: TimeInterval) {
        self.attack = attack
        self.decay = decay
    }

    @discardableResult
    public mutating func step(toward target: Float, seconds: TimeInterval) -> Float {
        guard seconds > 0 else { return value }
        let time = target > value ? attack : decay
        let share = Float(1 - exp(-seconds / max(time, 0.001)))
        value += (target - value) * share
        return value
    }

    public mutating func reset() { value = 0 }
}

/// Turns blocks of sound into bar heights: a 1024-point FFT split into four bands from bass to treble
/// (log-spaced, 60 Hz to 8 kHz), and the overall loudness. All memory is set aside up front: `process`
/// runs on the audio thread and must not allocate or wait.
final class LevelAnalyzer: @unchecked Sendable {
    static let fftSize = 1024
    private static let log2Size = vDSP_Length(10)
    /// Band edges in Hz: equal steps on a log scale.
    static let bandEdges: [Double] = (0...4).map { 60 * pow(8000.0 / 60, Double($0) / 4) }
    /// Treble carries less energy than bass in most music: lift the higher bands a little (dB).
    static let bandTilt: SIMD4<Float> = [0, 2, 5, 8]
    /// The quietest and loudest band levels the bars show (dBFS).
    static let bandRange: (floor: Float, ceiling: Float) = (-55, -15)
    /// The quietest and loudest overall levels the bars show (dBFS).
    static let loudnessRange: (floor: Float, ceiling: Float) = (-50, -8)
    /// In loudness mode the bars differ in height and in speed, so they don't move as one block.
    static let loudnessGain: SIMD4<Float> = [0.8, 1, 0.9, 0.72]

    private(set) var sampleRate: Double = 48_000
    private(set) var reading = MeterReading()
    /// The four band levels of the last block, before smoothing (tests).
    private(set) var rawBands: SIMD4<Float> = .zero
    /// The loudness of the last block, before smoothing (tests).
    private(set) var rawLoudness: Float = 0

    private let ring: UnsafeMutablePointer<Float>
    private var ringIndex = 0
    private let ordered: UnsafeMutablePointer<Float>
    private let window: UnsafeMutablePointer<Float>
    private let real: UnsafeMutablePointer<Float>
    private let imaginary: UnsafeMutablePointer<Float>
    private let magnitudes: UnsafeMutablePointer<Float>
    private let setup: FFTSetup
    // The constants, copied once so the audio thread never runs a first-use initializer.
    private let tilt = LevelAnalyzer.bandTilt
    private let bandRange = LevelAnalyzer.bandRange
    private let loudnessRange = LevelAnalyzer.loudnessRange
    private let loudnessGain = LevelAnalyzer.loudnessGain
    /// First and one-past-last FFT bin of each band.
    private var bandBins: [(Int, Int)] = []

    private var bandSmoothers = (0..<4).map { _ in LevelSmoother(attack: 0.03, decay: 0.2) }
    private var loudnessSmoothers = [
        LevelSmoother(attack: 0.03, decay: 0.16),
        LevelSmoother(attack: 0.04, decay: 0.22),
        LevelSmoother(attack: 0.035, decay: 0.19),
        LevelSmoother(attack: 0.05, decay: 0.27),
    ]

    init() {
        let size = Self.fftSize
        func buffer(_ count: Int) -> UnsafeMutablePointer<Float> {
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: count)
            pointer.initialize(repeating: 0, count: count)
            return pointer
        }
        ring = buffer(size)
        ordered = buffer(size)
        window = buffer(size)
        real = buffer(size / 2)
        imaginary = buffer(size / 2)
        magnitudes = buffer(size / 2)
        // Hann window.
        for index in 0..<size {
            window[index] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(size)))
        }
        // vDSP_create_fftsetup only fails when out of memory.
        setup = vDSP_create_fftsetup(Self.log2Size, FFTRadix(kFFTRadix2))!
        configure(sampleRate: 48_000)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        for pointer in [ring, ordered, window, real, imaginary, magnitudes] { pointer.deallocate() }
    }

    /// Sets the sample rate and clears everything. Only while no audio is being processed.
    func configure(sampleRate: Double) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 48_000
        let binWidth = self.sampleRate / Double(Self.fftSize)
        let lastBin = Self.fftSize / 2 - 1
        var bins: [(Int, Int)] = []
        var start = max(1, Int((Self.bandEdges[0] / binWidth).rounded()))
        for band in 0..<4 {
            let end = min(lastBin + 1, max(start + 1, Int((Self.bandEdges[band + 1] / binWidth).rounded())))
            bins.append((min(start, lastBin), end))
            start = end
        }
        bandBins = bins
        reset()
    }

    func reset() {
        ring.update(repeating: 0, count: Self.fftSize)
        ringIndex = 0
        reading = MeterReading()
        rawBands = .zero
        rawLoudness = 0
        for index in 0..<4 {
            bandSmoothers[index].reset()
            loudnessSmoothers[index].reset()
        }
    }

    /// One block of sound (`frames` samples, every `stride`-th float). Audio thread.
    func process(_ samples: UnsafePointer<Float>, frames: Int, stride: Int = 1) {
        guard frames > 0, stride > 0 else { return }
        let size = Self.fftSize
        var peak: Float = 0
        var meanSquare: Float = 0
        vDSP_maxmgv(samples, vDSP_Stride(stride), &peak, vDSP_Length(frames))
        vDSP_measqv(samples, vDSP_Stride(stride), &meanSquare, vDSP_Length(frames))
        // Keep the newest 1024 samples.
        let first = max(0, frames - size)
        for frame in first..<frames {
            ring[ringIndex] = samples[frame * stride]
            ringIndex = (ringIndex + 1) & (size - 1)
        }
        let seconds = Double(frames) / sampleRate
        reading.audioSeconds += seconds
        if peak > 0 { reading.heardSound = true }

        // Loudness: RMS in dB, between the floor and the ceiling.
        rawLoudness = Self.level(decibels: Self.decibels(meanSquare.squareRoot()), range: loudnessRange)
        // Bands: the newest 1024 samples in order, windowed, through the FFT.
        let tail = size - ringIndex
        ordered.update(from: ring + ringIndex, count: tail)
        (ordered + tail).update(from: ring, count: ringIndex)
        vDSP_vmul(ordered, 1, window, 1, ordered, 1, vDSP_Length(size))
        var split = DSPSplitComplex(realp: real, imagp: imaginary)
        ordered.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) { complex in
            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(size / 2))
        }
        vDSP_fft_zrip(setup, &split, 1, Self.log2Size, FFTDirection(FFT_FORWARD))
        vDSP_zvmags(&split, 1, magnitudes, 1, vDSP_Length(size / 2))
        // A full-scale sine through a Hann window and vDSP's real FFT: about (N/2)² × 1.5 of power
        // over its bins. Scale so that sine reads 0 dB.
        let scale = 2 / Float(size) / Float(1.5).squareRoot()
        var bands = SIMD4<Float>.zero
        for band in 0..<4 {
            let (start, end) = bandBins[band]
            var power: Float = 0
            vDSP_sve(magnitudes + start, 1, &power, vDSP_Length(end - start))
            let amplitude = power.squareRoot() * scale
            bands[band] = Self.level(decibels: Self.decibels(amplitude) + tilt[band], range: bandRange)
        }
        rawBands = bands

        var levels = SoundLevels.zero
        for index in 0..<4 {
            levels.bands[index] = bandSmoothers[index].step(toward: bands[index], seconds: seconds)
            levels.loudness[index] = loudnessSmoothers[index].step(
                toward: rawLoudness * loudnessGain[index], seconds: seconds
            )
        }
        reading.levels = levels
    }

    static func decibels(_ amplitude: Float) -> Float {
        amplitude > 0 ? 20 * log10(amplitude) : -200
    }

    /// 0 at the floor (or below), 1 at the ceiling (or above).
    static func level(decibels: Float, range: (floor: Float, ceiling: Float)) -> Float {
        min(1, max(0, (decibels - range.floor) / (range.ceiling - range.floor)))
    }
}

/// Tells, from what the meter hears, whether macOS lets PancakeNotch listen. There's no way to ask:
/// when the "System Audio Recording" permission is off (or its question is still on screen), the tap
/// delivers exact silence. So: any sound at all means allowed; silence while the app is known to be
/// making sound means not allowed, but only after a while, because the question may still be waiting
/// for an answer. Meanwhile the bars fall back to gentle motion and the tap is set up again now and
/// then (in case "Allow" only works for a fresh tap).
public struct AccessProbe: Sendable {
    public enum Verdict: Equatable, Sendable {
        /// Just started: keep showing the levels (they're zero for now).
        case waiting
        /// Sound came through: allowed.
        case hearing
        /// Nothing heard yet: show gentle motion meanwhile.
        case notHearing
        /// Nothing heard for a while: set the tap up again.
        case retry
        /// Silence for long while the app made sound: not allowed.
        case denied
    }

    /// Nothing heard this long (seconds on the clock): gentle motion meanwhile.
    public static let fallbackAfter: TimeInterval = 1.5
    /// Seconds of silence (while the app makes sound) between fresh tries.
    public static let retryEvery: TimeInterval = 5
    /// Seconds of silence (while the app makes sound) that mean "not allowed".
    public static let deniedAfter: TimeInterval = 15

    public private(set) var heard = false
    /// Seconds of exact silence that came through while the app said it was making sound.
    public private(set) var silentSeconds: TimeInterval = 0
    private var lastAudioSeconds: TimeInterval = 0
    private var retries = 0

    public init() {}

    /// The tap was set up again: its sound clock starts at 0.
    public mutating func meterRestarted() {
        lastAudioSeconds = 0
    }

    /// - Parameters:
    ///   - heardSound: anything but exact silence has come through.
    ///   - audioSeconds: seconds of sound that have come through since the tap was (re)started.
    ///   - elapsed: seconds since listening began.
    ///   - isOutputRunning: whether the app is making sound (nil = can't tell).
    public mutating func update(
        heardSound: Bool, audioSeconds: TimeInterval, elapsed: TimeInterval, isOutputRunning: Bool?
    ) -> Verdict {
        if heardSound { heard = true }
        if heard { return .hearing }
        let delta = max(0, audioSeconds - lastAudioSeconds)
        lastAudioSeconds = audioSeconds
        if isOutputRunning == true { silentSeconds += delta }
        if silentSeconds >= Self.deniedAfter { return .denied }
        if silentSeconds >= Self.retryEvery * Double(retries + 1) {
            retries += 1
            return .retry
        }
        return elapsed >= Self.fallbackAfter ? .notHearing : .waiting
    }
}
