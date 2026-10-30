// Makes the files scripts/check-convert-memory.sh converts: photos of several sizes and types, PDFs,
// audio, a 1080p clip and documents, all drawn here (no downloads). Pictures get fine noise so they
// compress like real photos.
// Usage: xcrun swiftc -O scripts/convert-fixtures.swift -o fixtures && ./fixtures <folder>
import AppKit
import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: fixtures <folder>\n".utf8))
    exit(1)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

/// 512×512 of random grey, drawn tiled over pictures at low opacity.
let noise: CGImage = {
    var bytes = [UInt8](repeating: 0, count: 512 * 512)
    arc4random_buf(&bytes, bytes.count)
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
        width: 512, height: 512, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 512, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil,
        shouldInterpolate: false, intent: .defaultIntent
    )!
}()

func picture(width: Int, height: Int, alpha: Bool = false, space: CGColorSpace = sRGB) -> CGImage {
    let info = space.model == .rgb ? (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast) : .none
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info.rawValue
    )!
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    if alpha {
        context.clear(rect)
        context.addEllipse(in: rect.insetBy(dx: Double(width) / 8, dy: Double(height) / 8))
        context.clip()
    }
    let colours = [CGColor(srgbRed: 0.9, green: 0.3, blue: 0.2, alpha: 1), CGColor(srgbRed: 0.1, green: 0.4, blue: 0.9, alpha: 1)]
    let gradient = CGGradient(colorsSpace: sRGB, colors: colours as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
    context.setAlpha(0.25)
    context.draw(noise, in: CGRect(x: 0, y: 0, width: 512, height: 512), byTiling: true)
    return context.makeImage()!
}

func save(_ image: CGImage, _ name: String, _ type: UTType, properties: [CFString: Any] = [:]) {
    let destination = CGImageDestinationCreateWithURL(folder.appending(path: name) as CFURL, type.identifier as CFString, 1, nil)!
    var options = properties
    options[kCGImageDestinationLossyCompressionQuality] = 0.85
    CGImageDestinationAddImage(destination, image, options as CFDictionary)
    precondition(CGImageDestinationFinalize(destination), "couldn't write \(name)")
}

// Photos: 4:3 at 3, 6, 12, 24 and 48 megapixels, as JPEG and HEIC; PNG and TIFF; transparent PNGs; CMYK.
let sizes = [(3, 2000, 1500), (6, 2828, 2121), (12, 4032, 3024), (24, 5657, 4243), (48, 8000, 6000)]
for (megapixels, width, height) in sizes {
    autoreleasepool {
        let image = picture(width: width, height: height)
        save(image, "photo\(megapixels).jpg", .jpeg)
        save(image, "photo\(megapixels).heic", .heic)
        if megapixels <= 6 { save(image, "photo\(megapixels).png", .png) }
        if megapixels == 6 { save(image, "photo\(megapixels).tiff", .tiff) }
    }
}
// A portrait photo stored on its side, as phones do.
save(picture(width: 4032, height: 3024), "turned12.jpg", .jpeg, properties: [kCGImagePropertyOrientation: 6])
for (megapixels, width, height) in [(2, 1633, 1225), (4, 2309, 1732)] {
    save(picture(width: width, height: height, alpha: true), "clear\(megapixels).png", .png)
}
save(picture(width: 2309, height: 1732, space: CGColorSpace(name: CGColorSpace.genericCMYK)!), "print4.jpg", .jpeg)

// PDFs: 200 pages of text; a page with a 6 MP photo; an A4 page scanned in grey at 300 dpi.
func pdf(_ name: String, pages: Int, size: CGSize, draw: (CGContext, Int) -> Void) {
    var box = CGRect(origin: .zero, size: size)
    let context = CGContext(folder.appending(path: name) as CFURL, mediaBox: &box, nil)!
    for page in 0..<pages {
        autoreleasepool {
            context.beginPDFPage(nil)
            draw(context, page)
            context.endPDFPage()
        }
    }
    context.closePDF()
}
let paragraph = String(repeating: "The quick brown fox jumps over the lazy dog, then naps in the sun. ", count: 40)
pdf("text200.pdf", pages: 200, size: CGSize(width: 612, height: 792)) { context, page in
    let text = NSAttributedString(string: "Page \(page + 1)\n\n" + paragraph + "\n\n" + paragraph, attributes: [.font: NSFont.systemFont(ofSize: 11)])
    let frame = CTFramesetterCreateFrame(
        CTFramesetterCreateWithAttributedString(text), CFRange(location: 0, length: 0),
        CGPath(rect: CGRect(x: 72, y: 72, width: 468, height: 648), transform: nil), nil
    )
    CTFrameDraw(frame, context)
}
let photo6 = CGImageSourceCreateWithURL(folder.appending(path: "photo6.jpg") as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }!
// Exercise PDFKit's annotation rendering and page-copy path on a long document too.
autoreleasepool {
    let document = PDFDocument(url: folder.appending(path: "text200.pdf"))!
    for index in 0..<document.pageCount {
        let page = document.page(at: index)!
        let mark = PDFAnnotation(bounds: CGRect(x: 72, y: 650, width: 200, height: 20), forType: .highlight, withProperties: nil)
        mark.color = .yellow
        page.addAnnotation(mark)
        if index % 2 == 1 { page.rotation = 90 }
    }
    precondition(document.write(to: folder.appending(path: "annotated200.pdf")))
}
pdf("photo6.pdf", pages: 1, size: CGSize(width: 612, height: 792)) { context, _ in
    context.draw(photo6, in: CGRect(x: 36, y: 126, width: 540, height: 405))
}
let scan = picture(width: 2480, height: 3508, space: CGColorSpaceCreateDeviceGray())
pdf("scan.pdf", pages: 3, size: CGSize(width: 595, height: 842)) { context, _ in
    context.draw(scan, in: CGRect(x: 0, y: 0, width: 595, height: 842))
}

// Audio: ten minutes of CD-quality stereo, and a minute of low-rate mono speech-like sound.
func tone(_ name: String, seconds: Double, rate: Double, channels: AVAudioChannelCount, settings: [String: Any]) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
    let file = try AVAudioFile(forWriting: folder.appending(path: name), settings: settings)
    let chunk = AVAudioFrameCount(rate)
    var written = 0.0
    while written < seconds {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!
        buffer.frameLength = chunk
        for channel in 0..<Int(channels) {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<Int(chunk) {
                let time = written + Double(frame) / rate
                samples[frame] = Float(0.3 * sin(2 * .pi * (220 + 110 * Double(channel)) * time) * (0.6 + 0.4 * sin(time)))
            }
        }
        try file.write(from: buffer)
        written += 1
    }
}
try tone("stereo10min.wav", seconds: 600, rate: 44_100, channels: 2, settings: [
    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
])
try tone("speech.aiff", seconds: 60, rate: 22_050, channels: 1, settings: [
    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true,
])

// Video: 15 seconds of 1080p at 30 fps with a moving picture, then the same with sound.
func clip(_ url: URL, seconds: Int) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1920, AVVideoHeightKey: 1080,
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 1920,
        kCVPixelBufferHeightKey as String: 1080,
    ])
    writer.add(input)
    precondition(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    let still = picture(width: 2400, height: 1350)
    for frame in 0..<(seconds * 30) {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        CVPixelBufferLockBaseAddress(buffer!, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer!), width: 1920, height: 1080, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer!), space: sRGB,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        context.draw(still, in: CGRect(x: -Double(frame), y: -Double(frame) / 2, width: 2400, height: 1350))
        CVPixelBufferUnlockBaseAddress(buffer!, [])
        precondition(adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    precondition(writer.status == .completed, "clip: \(String(describing: writer.error))")
}
let silent = folder.appending(path: "clip1080.mov")
try await clip(silent, seconds: 15)
try tone("clip-sound.aiff", seconds: 15, rate: 44_100, channels: 2, settings: [
    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true,
])
let composition = AVMutableComposition()
let video = AVURLAsset(url: silent), sound = AVURLAsset(url: folder.appending(path: "clip-sound.aiff"))
let range = CMTimeRange(start: .zero, duration: try await video.load(.duration))
try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    .insertTimeRange(range, of: try await video.loadTracks(withMediaType: .video)[0], at: .zero)
try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    .insertTimeRange(range, of: try await sound.loadTracks(withMediaType: .audio)[0], at: .zero)
let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
try await export.export(to: folder.appending(path: "clip1080sound.mov"), as: .mov)

// Documents: a long plain text, and the same as RTF and Word.
let long = (1...2000).map { "Line \($0). " + paragraph.prefix(200) }.joined(separator: "\n")
try long.write(to: folder.appending(path: "long.txt"), atomically: true, encoding: .utf8)
let document = NSAttributedString(string: long, attributes: [.font: NSFont.systemFont(ofSize: 12)])
for (name, type) in [("long.rtf", NSAttributedString.DocumentType.rtf), ("long.docx", .officeOpenXML)] {
    try document.data(from: NSRange(location: 0, length: document.length), documentAttributes: [.documentType: type])
        .write(to: folder.appending(path: name))
}
// Small rich documents remain convertible under the unpacked-text cap.
let short = NSAttributedString(string: (1...100).map { "Line \($0). " + paragraph.prefix(200) }.joined(separator: "\n"),
                               attributes: [.font: NSFont.systemFont(ofSize: 12)])
for (name, type) in [("short.rtf", NSAttributedString.DocumentType.rtf), ("short.docx", .officeOpenXML)] {
    try short.data(from: NSRange(location: 0, length: short.length), documentAttributes: [.documentType: type])
        .write(to: folder.appending(path: name))
}
print("Fixtures in \(folder.path)")
