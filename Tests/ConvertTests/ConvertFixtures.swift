import AppKit
import AVFoundation
import ConvertKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import ConvertEngine

/// Small files made on the spot for the conversion tests, in a folder of their own.
final class ConvertFixture {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ConvertTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    func url(_ name: String) -> URL { folder.appending(path: name) }

    /// A picture filled with `colour`, with a black square in its top-left corner as stored (to check
    /// orientation), optionally see-through outside a centre square.
    static func picture(width: Int, height: Int, colour: CGColor = CGColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1), clearEdges: Bool = false) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: (clearEdges ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue
        )!
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if clearEdges {
            context.clear(rect)
            context.setFillColor(colour)
            context.fill(rect.insetBy(dx: Double(width) / 4, dy: Double(height) / 4))
        } else {
            context.setFillColor(colour)
            context.fill(rect)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            let side = Double(min(width, height)) / 4
            context.fill(CGRect(x: 0, y: Double(height) - side, width: side, height: side))
        }
        return context.makeImage()!
    }

    @discardableResult
    func savePicture(_ image: CGImage, _ name: String, _ type: UTType, orientation: Int? = nil) -> URL {
        let url = url(name)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        return url
    }

    /// A PDF of `pages` Letter pages, each saying "Page n" (or blank).
    @discardableResult
    func savePDF(_ name: String, pages: Int, withText: Bool = true) -> URL {
        let url = url(name)
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        for page in 1...pages {
            context.beginPDFPage(nil)
            if withText {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Page \(page) of the report", attributes: [
                    .font: NSFont.systemFont(ofSize: 24),
                ]))
                context.textPosition = CGPoint(x: 72, y: 700)
                CTLineDraw(line, context)
            } else {
                context.setFillColor(CGColor(gray: 0.5, alpha: 1))
                context.fill(CGRect(x: 72, y: 72, width: 200, height: 200))
            }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    /// A PDF page holding one picture of `width`×`height`, grey or in colour.
    @discardableResult
    func savePicturePDF(_ name: String, width: Int, height: Int, grey: Bool) -> URL {
        let url = url(name)
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        let space = grey ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmap = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: (grey ? CGImageAlphaInfo.none : .noneSkipLast).rawValue
        )!
        bitmap.setFillColor(CGColor(gray: 0.4, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.beginPDFPage(nil)
        context.draw(bitmap.makeImage()!, in: CGRect(x: 72, y: 72, width: 300, height: 300))
        context.endPDFPage()
        context.closePDF()
        return url
    }

    /// `seconds` of a tone as uncompressed audio.
    @discardableResult
    func saveTone(_ name: String, seconds: Double, rate: Double, channels: AVAudioChannelCount, bigEndian: Bool, bits: Int = 16) throws -> URL {
        let url = url(name)
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: bits, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: bigEndian,
        ])
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frames) {
                buffer.floatChannelData![channel][frame] = Float(0.3 * sin(2 * .pi * 440 * Double(frame) / rate))
            }
        }
        try file.write(from: buffer)
        return url
    }

    /// A one-second H.264 clip, 160×90 at 24 fps, with the black square top-left; `turned` stores it
    /// on its side with a note to show it upright (as a phone filming upright does).
    @discardableResult
    @MainActor
    func saveClip(_ name: String, seconds: Double = 1, turned: Bool = false) async throws -> URL {
        let url = url(name)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 90,
        ])
        input.expectsMediaDataInRealTime = false
        if turned { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 90, ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 90,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ConvertFailure.failed }
        writer.startSession(atSourceTime: .zero)
        let frame = Self.picture(width: 160, height: 90, colour: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        for index in 0..<Int(seconds * 24) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer!), width: 160, height: 90, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer!), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )!
            context.draw(frame, in: CGRect(x: 0, y: 0, width: 160, height: 90))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            guard adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 24)) else {
                throw writer.error ?? ConvertFailure.failed
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ConvertFailure.failed }
        return url
    }

    /// Runs a request through the engine, into a fresh output folder.
    @MainActor
    func convert(_ sources: [URL], to format: ConvertFormat, quality: ConvertQuality = .balanced) async -> ConvertMessage {
        let output = folder.appending(path: "out-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let request = ConvertRequest(
            sources: sources.map(\.path), format: format, quality: quality, outputFolder: output.path, pageName: "Page"
        )
        return await ConvertEngine.run(request) { _ in }
    }
}

/// A picture file's pixel size and the colour at a point (x, y from the top-left, upright as shown).
struct PictureCheck {
    let width: Int
    let height: Int
    private let pixels: [UInt8]

    init?(_ url: URL, frame: Int = 0) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, frame, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 10_000,
              ] as CFDictionary) else { return nil }
        self.init(image)
    }

    init(_ image: CGImage) {
        let (width, height) = (image.width, image.height)
        self.width = width
        self.height = height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )!
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        self.pixels = pixels
    }

    /// Brightness 0…255 at a fraction of the way across and down.
    func brightness(x: Double, y: Double) -> Int {
        let column = min(width - 1, Int(Double(width) * x)), row = min(height - 1, Int(Double(height) * y))
        let index = (row * width + column) * 4
        return (Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])) / 3
    }
}
