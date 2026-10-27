import AVFoundation
import ConvertKit
import Foundation

/// Audio (or a video's sound) to M4A, Apple Lossless, WAV or AIFF: read as plain samples a little at a
/// time and written out as they come, so a long recording costs no more memory than a short one.
enum AudioConversion {
    static func convert(_ url: URL, to format: ConvertFormat, quality: ConvertQuality, output: URL, progress: @escaping ConvertEngine.Progress) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            throw format == .audioOnly ? ConvertFailure.unsupported : ConvertFailure.unreadable
        }
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        let basic = (try? await track.load(.formatDescriptions))?.first
            .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let sourceRate = basic.map(\.mSampleRate).flatMap { $0 > 0 ? $0 : nil } ?? 44_100
        let sourceChannels = basic.map { Int($0.mChannelsPerFrame) }.flatMap { $0 > 0 ? $0 : nil } ?? 2
        let bits = (basic.map { Int($0.mBitsPerChannel) } ?? 0) > 16 ? 24 : 16

        // AAC takes up to 48 kHz and, here, stereo; the lossless formats keep what the source has.
        let isAAC = format == .m4a || format == .audioOnly
        let rate = isAAC ? min(sourceRate, 48_000) : sourceRate
        let channels = isAAC ? min(sourceChannels, 2) : min(sourceChannels, 8)
        var readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
        ]
        if let layout = layoutData(channels: channels) { readerSettings[AVChannelLayoutKey] = layout }

        var writerSettings: [String: Any] = [AVSampleRateKey: rate, AVNumberOfChannelsKey: channels]
        let fileType: AVFileType
        switch format {
        case .m4a, .audioOnly:
            fileType = .m4a
            writerSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            let preferred = channels == 1 ? quality.stereoBitRate / 2 : quality.stereoBitRate
            if let bitRate = aacBitRate(preferred: preferred, sampleRate: rate, channels: channels) {
                writerSettings[AVEncoderBitRateKey] = bitRate
            }
        case .appleLossless:
            fileType = .m4a
            writerSettings[AVFormatIDKey] = kAudioFormatAppleLossless
            writerSettings[AVEncoderBitDepthHintKey] = bits
        case .wav, .aiff:
            fileType = format == .wav ? .wav : .aiff
            writerSettings[AVFormatIDKey] = kAudioFormatLinearPCM
            writerSettings[AVLinearPCMBitDepthKey] = bits
            writerSettings[AVLinearPCMIsFloatKey] = false
            writerSettings[AVLinearPCMIsBigEndianKey] = format == .aiff
            writerSettings[AVLinearPCMIsNonInterleaved] = false
        default:
            throw ConvertFailure.unsupported
        }
        if let layout = layoutData(channels: channels) { writerSettings[AVChannelLayoutKey] = layout }

        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw ConvertFailure.unreadable }
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw ConvertFailure.unreadable }
        reader.add(readerOutput)

        // Song details (title, artist, artwork) go along into an M4A.
        let metadata = fileType == .m4a ? ((try? await asset.load(.commonMetadata)) ?? []) : []
        let writer = try makeWriter(output, fileType: fileType, settings: writerSettings, metadata: metadata, rate: rate, bitRate: isAAC)
        let input = writer.inputs[0]

        guard reader.startReading() else { throw ConvertFailure.unreadable }
        writer.startSession(atSourceTime: .zero)
        let finished = await SamplePump(reader: readerOutput, writer: input, duration: duration, progress: progress).run()
        if reader.status == .failed || !finished {
            writer.cancelWriting()
            throw reader.status == .failed ? ConvertFailure.unreadable : ConvertFailure.cantWrite
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw ConvertFailure.cantWrite }
        progress(1)
    }

    /// A writer that has started. Some sources' details don't fit an M4A and some rates don't suit a bit
    /// rate: each of those is retried without, rather than failing the file.
    private static func makeWriter(
        _ output: URL, fileType: AVFileType, settings: [String: Any], metadata: [AVMetadataItem], rate: Double, bitRate: Bool
    ) throws -> AVAssetWriter {
        var attempts: [([String: Any], [AVMetadataItem])] = [(settings, metadata)]
        if !metadata.isEmpty { attempts.append((settings, [])) }
        if bitRate {
            var plain = settings
            plain[AVEncoderBitRateKey] = nil
            attempts.append((plain, []))
        }
        for (settings, metadata) in attempts {
            try? FileManager.default.removeItem(at: output)
            guard let writer = try? AVAssetWriter(outputURL: output, fileType: fileType) else { throw ConvertFailure.cantWrite }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            guard writer.canApply(outputSettings: settings, forMediaType: .audio), writer.canAdd(input) else { continue }
            writer.add(input)
            writer.metadata = metadata
            if writer.startWriting() { return writer }
        }
        throw ConvertFailure.cantWrite
    }

    /// The highest bit rate the AAC encoder takes for this rate and channel count, up to `preferred`
    /// (a low-rate recording such as speech takes much less than music).
    static func aacBitRate(preferred: Int, sampleRate: Double, channels: Int) -> Int? {
        let count = UInt32(channels)
        var input = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * count, mFramesPerPacket: 1, mBytesPerFrame: 4 * count, mChannelsPerFrame: count,
            mBitsPerChannel: 32, mReserved: 0
        )
        var output = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: 1024, mBytesPerFrame: 0, mChannelsPerFrame: count, mBitsPerChannel: 0, mReserved: 0
        )
        var converter: AudioConverterRef?
        guard AudioConverterNew(&input, &output, &converter) == noErr, let converter else { return nil }
        defer { AudioConverterDispose(converter) }
        var size: UInt32 = 0
        guard AudioConverterGetPropertyInfo(converter, kAudioConverterApplicableEncodeBitRates, &size, nil) == noErr, size > 0 else { return nil }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioConverterGetProperty(converter, kAudioConverterApplicableEncodeBitRates, &size, &ranges) == noErr else { return nil }
        let rates = ranges.map { Int($0.mMaximum) }.filter { $0 > 0 }.sorted()
        return rates.last { $0 <= preferred } ?? rates.first
    }

    /// Mono or stereo layouts (more channels keep the source's order, unlabelled).
    private static func layoutData(channels: Int) -> Data? {
        let tag: AudioChannelLayoutTag
        switch channels {
        case 1: tag = kAudioChannelLayoutTag_Mono
        case 2: tag = kAudioChannelLayoutTag_Stereo
        default: tag = kAudioChannelLayoutTag_DiscreteInOrder | AudioChannelLayoutTag(channels)
        }
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = tag
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }
}

/// Moves samples from a reader to a writer whenever the writer is ready (no polling).
/// AVFoundation calls back on one serial queue, so the state here is only touched there.
private final class SamplePump: @unchecked Sendable {
    private let reader: AVAssetReaderOutput
    private let writer: AVAssetWriterInput
    private let duration: Double
    private let progress: ConvertEngine.Progress
    private let queue = DispatchQueue(label: "io.github.sickpancake.PancakeNotch.convert.samples")
    private var isDone = false

    init(reader: AVAssetReaderOutput, writer: AVAssetWriterInput, duration: Double, progress: @escaping ConvertEngine.Progress) {
        self.reader = reader
        self.writer = writer
        self.duration = duration
        self.progress = progress
    }

    /// True once every sample was written; false if the writer refused one.
    func run() async -> Bool {
        await withCheckedContinuation { continuation in
            writer.requestMediaDataWhenReady(on: queue) { [self] in
                while !isDone, writer.isReadyForMoreMediaData {
                    guard let buffer = reader.copyNextSampleBuffer() else {
                        finish(continuation, ok: true)
                        return
                    }
                    guard writer.append(buffer) else {
                        finish(continuation, ok: false)
                        return
                    }
                    if duration > 0 {
                        progress(min(0.99, CMSampleBufferGetPresentationTimeStamp(buffer).seconds / duration))
                    }
                }
            }
        }
    }

    private func finish(_ continuation: CheckedContinuation<Bool, Never>, ok: Bool) {
        guard !isDone else { return }
        isDone = true
        writer.markAsFinished()
        continuation.resume(returning: ok)
    }
}
