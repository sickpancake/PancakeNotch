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
        let description = (try? await track.load(.formatDescriptions))?.first
        let basic = description.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let sourceRate = basic.map(\.mSampleRate).flatMap { $0 > 0 ? $0 : nil } ?? 44_100
        let sourceChannels = basic.map { Int($0.mChannelsPerFrame) }.flatMap { $0 > 0 ? $0 : nil } ?? 2
        let sourceLayout = description.flatMap(Self.layout(of:))
        let bits = (basic.map(sourceBits) ?? 16) > 16 ? 24 : 16

        // Song details (title, artist, artwork…) go along into an M4A; the source's encoder delay doesn't.
        let metadata = format == .m4a || format == .audioOnly || format == .appleLossless
            ? ((try? await asset.load(.metadata)) ?? []).filter { !Self.isEncoderDetail($0) } : []
        let common = format == .m4a || format == .audioOnly || format == .appleLossless ? ((try? await asset.load(.commonMetadata)) ?? []) : []

        // AAC already: copied as it is (re-encoding only loses), unless Smaller file asks for fewer bits.
        let isAAC = format == .m4a || format == .audioOnly
        if isAAC, let description, let basic, [kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2].contains(basic.mFormatID) {
            let dataRate = Double((try? await track.load(.estimatedDataRate)) ?? 0)
            let target = Double(sourceChannels == 1 ? quality.stereoBitRate / 2 : quality.stereoBitRate)
            if quality != .smaller || (dataRate > 0 && dataRate <= target * 1.25) {
                try await copy(asset: asset, track: track, description: description, output: output, metadata: [metadata, common], duration: duration, progress: progress)
                return
            }
        }

        // AAC takes up to 48 kHz and, here, stereo; the lossless formats keep what the source has.
        let rate = isAAC ? min(sourceRate, 48_000) : sourceRate
        let channels = isAAC ? min(sourceChannels, 2) : sourceChannels
        var readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
        ]
        // Surround is read in the source's own speaker order (Apple Lossless's encoder puts it in its own).
        let readerLayout = channels == sourceChannels && channels > 2 ? sourceLayout : nil
        if let layout = readerLayout ?? layoutData(tag: plainLayout(channels: channels)) { readerSettings[AVChannelLayoutKey] = layout }

        var writerSettings: [String: Any] = [AVSampleRateKey: rate, AVNumberOfChannelsKey: channels]
        var writerLayout = layoutData(tag: plainLayout(channels: channels))
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
            // Apple Lossless takes up to 8 channels, each count in one speaker order of its own.
            guard let tag = losslessLayout(channels: channels) else { throw ConvertFailure.unsupported }
            fileType = .m4a
            writerSettings[AVFormatIDKey] = kAudioFormatAppleLossless
            writerSettings[AVEncoderBitDepthHintKey] = bits
            writerLayout = layoutData(tag: tag)
        case .wav, .aiff:
            fileType = format == .wav ? .wav : .aiff
            writerSettings[AVFormatIDKey] = kAudioFormatLinearPCM
            writerSettings[AVLinearPCMBitDepthKey] = bits
            writerSettings[AVLinearPCMIsFloatKey] = false
            writerSettings[AVLinearPCMIsBigEndianKey] = format == .aiff
            writerSettings[AVLinearPCMIsNonInterleaved] = false
            // In the speaker mask's order where the speakers have one. The writer only labels: the reader
            // puts the channels in that order.
            if channels > 2, let mask = sourceLayout.flatMap(Self.speakerMaskLayout) {
                writerLayout = mask
                readerSettings[AVChannelLayoutKey] = mask
            } else if channels > 2 {
                writerLayout = readerLayout ?? writerLayout
            }
        default:
            throw ConvertFailure.unsupported
        }
        if let writerLayout { writerSettings[AVChannelLayoutKey] = writerLayout }

        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw ConvertFailure.unreadable }
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw ConvertFailure.unreadable }
        reader.add(readerOutput)

        let writer = try makeWriter(output, fileType: fileType, settings: writerSettings, metadata: [metadata, common], bitRate: isAAC)
        try await pump(reader: reader, output: readerOutput, writer: writer, duration: duration, progress: progress)
    }

    /// AAC moved into an M4A without decoding.
    private static func copy(
        asset: AVURLAsset, track: AVAssetTrack, description: CMFormatDescription, output: URL, metadata: [[AVMetadataItem]],
        duration: Double, progress: @escaping ConvertEngine.Progress
    ) async throws {
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw ConvertFailure.unreadable }
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw ConvertFailure.unreadable }
        reader.add(readerOutput)
        let writer = try makeWriter(output, fileType: .m4a, settings: nil, hint: description, metadata: metadata, bitRate: false)
        try await pump(reader: reader, output: readerOutput, writer: writer, duration: duration, progress: progress)
    }

    private static func pump(
        reader: AVAssetReader, output: AVAssetReaderTrackOutput, writer: AVAssetWriter, duration: Double, progress: @escaping ConvertEngine.Progress
    ) async throws {
        guard reader.startReading() else { throw ConvertFailure.unreadable }
        writer.startSession(atSourceTime: .zero)
        let finished = await SamplePump(reader: output, writer: writer.inputs[0], duration: duration, progress: progress).run()
        if reader.status == .failed || !finished {
            writer.cancelWriting()
            throw reader.status == .failed ? ConvertFailure.unreadable : ConvertFailure.cantWrite
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw ConvertFailure.cantWrite }
        progress(1)
    }

    /// A writer that has started. Some sources' details don't fit an M4A and some rates don't suit a bit
    /// rate: each of those is retried with fewer details (`metadata`, fullest first), then without, rather
    /// than failing the file.
    private static func makeWriter(
        _ output: URL, fileType: AVFileType, settings: [String: Any]?, hint: CMFormatDescription? = nil,
        metadata: [[AVMetadataItem]], bitRate: Bool
    ) throws -> AVAssetWriter {
        var attempts: [([String: Any]?, [AVMetadataItem])] = metadata.filter { !$0.isEmpty }.map { (settings, $0) }
        attempts.append((settings, []))
        if bitRate, var plain = settings {
            plain[AVEncoderBitRateKey] = nil
            attempts.append((plain, []))
        }
        for (settings, metadata) in attempts {
            try? FileManager.default.removeItem(at: output)
            guard let writer = try? AVAssetWriter(outputURL: output, fileType: fileType) else { throw ConvertFailure.cantWrite }
            // Checked before the input exists: an input with settings the format refuses raises an exception.
            if let settings, !writer.canApply(outputSettings: settings, forMediaType: .audio) { continue }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings, sourceFormatHint: hint)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { continue }
            writer.add(input)
            writer.metadata = metadata
            if writer.startWriting() { return writer }
        }
        throw ConvertFailure.cantWrite
    }

    /// The bits per sample the source was made with: lossless formats say so in their flags.
    static func sourceBits(_ basic: AudioStreamBasicDescription) -> Int {
        if basic.mBitsPerChannel > 0 { return Int(basic.mBitsPerChannel) }
        guard basic.mFormatID == kAudioFormatAppleLossless || basic.mFormatID == kAudioFormatFLAC else { return 16 }
        switch basic.mFormatFlags {
        case kAppleLosslessFormatFlag_20BitSourceData: return 20
        case kAppleLosslessFormatFlag_24BitSourceData: return 24
        case kAppleLosslessFormatFlag_32BitSourceData: return 32
        default: return 16
        }
    }

    /// iTunes' gapless and loudness notes describe the source's own encoding, not the new file's.
    private static func isEncoderDetail(_ item: AVMetadataItem) -> Bool {
        let name = (item.key as? String) ?? item.identifier?.rawValue ?? ""
        return name.contains("iTunSMPB") || name.contains("iTunNORM") || name.contains("Encoding Params")
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

    /// Mono, stereo, or more channels in the order they come, unlabelled.
    private static func plainLayout(channels: Int) -> AudioChannelLayoutTag {
        switch channels {
        case 1: kAudioChannelLayoutTag_Mono
        case 2: kAudioChannelLayoutTag_Stereo
        default: kAudioChannelLayoutTag_DiscreteInOrder | AudioChannelLayoutTag(channels)
        }
    }

    /// The one speaker order Apple Lossless takes for each channel count.
    private static func losslessLayout(channels: Int) -> AudioChannelLayoutTag? {
        switch channels {
        case 1: kAudioChannelLayoutTag_Mono
        case 2: kAudioChannelLayoutTag_Stereo
        case 3: kAudioChannelLayoutTag_MPEG_3_0_B
        case 4: kAudioChannelLayoutTag_MPEG_4_0_B
        case 5: kAudioChannelLayoutTag_MPEG_5_0_D
        case 6: kAudioChannelLayoutTag_MPEG_5_1_D
        case 7: kAudioChannelLayoutTag_AAC_6_1
        case 8: kAudioChannelLayoutTag_MPEG_7_1_B
        default: nil
        }
    }

    private static func layoutData(tag: AudioChannelLayoutTag) -> Data? {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = tag
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }

    /// The source's speaker layout, as the reader and writer take it.
    private static func layout(of description: CMAudioFormatDescription) -> Data? {
        var size = 0
        guard let layout = CMAudioFormatDescriptionGetChannelLayout(description, sizeOut: &size), size > 0 else { return nil }
        return Data(bytes: layout, count: size)
    }

    /// The same speakers as a WAV speaker mask (its fixed order), when they all have a place in one.
    private static func speakerMaskLayout(_ data: Data) -> Data? {
        // A layout without speaker descriptions is only its 12-byte head.
        guard data.count >= 12 else { return nil }
        let tag = data.withUnsafeBytes { $0.loadUnaligned(as: AudioChannelLayoutTag.self) }
        if tag == kAudioChannelLayoutTag_UseChannelBitmap { return data }
        // The speakers in the source's order: listed in the layout, or looked up from its tag.
        var labels: [AudioChannelLabel] = []
        func read(_ layout: Data) {
            layout.withUnsafeBytes { bytes in
                let count = Int(bytes.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
                let first = MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions)!
                for index in 0..<count {
                    let offset = first + index * MemoryLayout<AudioChannelDescription>.stride
                    guard offset + MemoryLayout<AudioChannelDescription>.size <= bytes.count else { return }
                    labels.append(bytes.loadUnaligned(fromByteOffset: offset, as: AudioChannelDescription.self).mChannelLabel)
                }
            }
        }
        if tag == kAudioChannelLayoutTag_UseChannelDescriptions {
            read(data)
        } else {
            var tag = tag
            var size: UInt32 = 0
            let tagSize = UInt32(MemoryLayout<AudioChannelLayoutTag>.size)
            guard AudioFormatGetPropertyInfo(kAudioFormatProperty_ChannelLayoutForTag, tagSize, &tag, &size) == noErr, size > 0 else { return nil }
            var layout = Data(count: Int(size))
            let status = layout.withUnsafeMutableBytes { AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutForTag, tagSize, &tag, &size, $0.baseAddress!) }
            guard status == noErr else { return nil }
            read(layout)
        }
        // Speaker labels 1…18 are the mask's bits, in its order.
        guard !labels.isEmpty, labels.allSatisfy({ (1...18).contains($0) }), Set(labels).count == labels.count else { return nil }
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelBitmap
        layout.mChannelBitmap = AudioChannelBitmap(rawValue: labels.reduce(0) { $0 | 1 << ($1 - 1) })
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
