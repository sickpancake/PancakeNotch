import Accelerate
import AVFoundation
import ConvertKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Video: repackaged into MP4 or MOV without decoding (fast, same quality, little memory), or a short
/// clip turned into a GIF. Re-encoding video is left out: it's far over the memory budget (ADR-0038).
enum VideoConversion {
    static func repackage(_ url: URL, to format: ConvertFormat, output: URL, progress: @escaping ConvertEngine.Progress) async throws {
        let asset = AVURLAsset(url: url)
        let type: AVFileType = format == .mov ? .mov : .mp4
        guard await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough, with: asset, outputFileType: type),
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ConvertFailure.unsupported
        }
        let states = session.states(updateInterval: 0.25)
        let watcher = Task {
            for await state in states {
                if case .exporting(let exported) = state { progress(min(0.99, exported.fractionCompleted)) }
            }
        }
        defer { watcher.cancel() }
        do {
            try await session.export(to: output, as: type)
        } catch {
            throw ConvertFailure.failed
        }
        progress(1)
    }

    /// Frames per second in a GIF.
    static let gifFrameRate = 12.0

    static func gif(_ url: URL, quality: ConvertQuality, output: URL, progress: @escaping ConvertEngine.Progress) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform),
              let duration = try? await asset.load(.duration).seconds, duration > 0,
              natural.width > 0, natural.height > 0 else { throw ConvertFailure.unreadable }

        // Frames are read in order (no seeking) and the decoder shrinks them to the GIF's size as it goes.
        let scale = min(1, Double(quality.gifSize) / max(natural.width, natural.height))
        let width = max(1, Int((natural.width * scale).rounded()))
        let height = max(1, Int((natural.height * scale).rounded()))
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw ConvertFailure.unreadable }
        let frames = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        frames.alwaysCopiesSampleData = false
        guard reader.canAdd(frames) else { throw ConvertFailure.unreadable }
        reader.add(frames)
        guard reader.startReading() else { throw ConvertFailure.unreadable }
        defer { reader.cancelReading() }

        // A phone video filmed upright is stored on its side with a note to turn it.
        let turns = quarterTurns(transform)
        let upright = turns % 2 == 0 ? (width: width, height: height) : (width: height, height: width)
        let writer = try GIFWriter(url: output, width: upright.width, height: upright.height)
        var turned = [UInt8](repeating: 0, count: turns == 0 ? 0 : upright.width * upright.height * 4)
        let rotation = UInt8(turns == 1 ? kRotate90DegreesClockwise : turns == 2 ? kRotate180DegreesClockwise : kRotate90DegreesCounterClockwise)

        let step = 1 / gifFrameRate
        var start: Double?
        var next = 0.0
        var added = 0
        while let sample = frames.copyNextSampleBuffer() {
            try autoreleasepool {
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                guard time.isFinite, let buffer = CMSampleBufferGetImageBuffer(sample),
                      CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height else { return }
                let first = start ?? time
                start = first
                // 12 frames a second: a frame is kept once its time comes (a slower video keeps every frame).
                guard time - first + 0.001 >= next else { return }
                next += step
                if next < time - first { next = time - first + step }

                CVPixelBufferLockBaseAddress(buffer, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
                guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                if turns == 0 {
                    try writer.add(bgra: base, bytesPerRow: bytesPerRow, time: time - first)
                } else {
                    try turned.withUnsafeMutableBytes { turned in
                        var source = vImage_Buffer(data: base, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
                        var destination = vImage_Buffer(
                            data: turned.baseAddress, height: vImagePixelCount(upright.height),
                            width: vImagePixelCount(upright.width), rowBytes: upright.width * 4
                        )
                        var black: [UInt8] = [0, 0, 0, 255]
                        guard vImageRotate90_ARGB8888(&source, &destination, rotation, &black, vImage_Flags(kvImageNoFlags)) == kvImageNoError,
                              let pixels = turned.baseAddress else { throw ConvertFailure.failed }
                        try writer.add(bgra: pixels, bytesPerRow: upright.width * 4, time: time - first)
                    }
                }
                added += 1
                progress(min(0.99, (time - first) / duration))
            }
        }
        guard reader.status != .failed else { throw ConvertFailure.unreadable }
        guard added > 0 else { throw ConvertFailure.unreadable }
        try writer.finish(end: duration - (start ?? 0))
        progress(1)
    }

    /// How many quarter turns clockwise a video's transform asks for (mirroring is left as it is).
    static func quarterTurns(_ transform: CGAffineTransform) -> Int {
        let turns = Int((atan2(transform.b, transform.a) / (.pi / 2)).rounded())
        return (turns % 4 + 4) % 4
    }
}
