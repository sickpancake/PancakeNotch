import AppKit
import AVFoundation
import ConvertKit
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import ConvertEngine

@MainActor
struct ConversionQualityTests {
    private func output(_ message: ConvertMessage) throws -> URL {
        #expect(message.errors == [])
        return URL(fileURLWithPath: try #require(message.outputs?.first).path)
    }

    @Test func transparentPictureKeepsMetadataWhenFlattened() async throws {
        let fixture = try ConvertFixture()
        let source = fixture.url("Camera.png")
        let destination = try #require(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, ConvertFixture.picture(width: 120, height: 80, clearEdges: true), [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Test camera"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:01:02 03:04:05"],
        ] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        let result = try output(await fixture.convert([source], to: .jpeg))
        let image = try #require(CGImageSourceCreateWithURL(result as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [String: Any])
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake as String] as? String == "Test camera")
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String == "2024:01:02 03:04:05")
    }

    @Test(arguments: [ConvertFormat.wav, .aiff, .appleLossless])
    func losslessAudioKeeps24BitSamples(format: ConvertFormat) async throws {
        let fixture = try ConvertFixture()
        let source = try fixture.saveTone("Precise.wav", seconds: 0.1, rate: 48_000, channels: 2, bigEndian: false, bits: 24)
        // Exercise the ALAC flags too: its stream description reports zero bits per channel.
        let lossless = try output(await fixture.convert([source], to: .appleLossless))
        let result = try output(await fixture.convert([lossless], to: format))
        let original = try samples(source), converted = try samples(result)
        #expect(original == converted)
        let track = try #require(try await AVURLAsset(url: result).loadTracks(withMediaType: .audio).first)
        let description = try #require(try await track.load(.formatDescriptions).first)
        let basic = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee)
        #expect(AudioConversion.sourceBits(basic) == 24)
    }

    @Test func surroundLosslessKeepsEveryChannel() async throws {
        let fixture = try ConvertFixture()
        let source = fixture.url("Surround.wav")
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A))
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channelLayout: layout)
        var settings = format.settings
        settings[AVLinearPCMBitDepthKey] = 24
        settings[AVLinearPCMIsFloatKey] = false
        do {
            let file = try AVAudioFile(forWriting: source, settings: settings)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
            buffer.frameLength = 1024
            for channel in 0..<6 {
                for frame in 0..<1024 { buffer.floatChannelData![channel][frame] = Float(channel + 1) / 16 }
            }
            try file.write(from: buffer)
        }
        let lossless = try output(await fixture.convert([source], to: .appleLossless))
        let restored = try output(await fixture.convert([lossless], to: .wav))
        let original = try samples(source), converted = try samples(restored)
        #expect(original.count == 6 && converted.count == 6)
        #expect(original == converted)
    }

    @Test func extractingAACDoesNotReencodePackets() async throws {
        let fixture = try ConvertFixture()
        let source = try fixture.saveTone("Tone.wav", seconds: 0.2, rate: 44_100, channels: 2, bigEndian: false)
        let aac = try output(await fixture.convert([source], to: .m4a))
        let clip = try await fixture.saveClip("Silent.mov")
        let movie = AVMutableComposition()
        for (url, media) in [(clip, AVMediaType.video), (aac, AVMediaType.audio)] {
            let asset = AVURLAsset(url: url)
            let track = try #require(try await asset.loadTracks(withMediaType: media).first)
            let target = try #require(movie.addMutableTrack(withMediaType: media, preferredTrackID: kCMPersistentTrackID_Invalid))
            try target.insertTimeRange(CMTimeRange(start: .zero, duration: try await asset.load(.duration)), of: track, at: .zero)
        }
        let exporter = try #require(AVAssetExportSession(asset: movie, presetName: AVAssetExportPresetPassthrough))
        let video = fixture.url("Sound.mov")
        try await exporter.export(to: video, as: .mov)
        let extracted = try output(await fixture.convert([video], to: .audioOnly))
        #expect(try await packets(aac) == packets(extracted))
    }

    @Test func pdfPicturesIncludeAnnotationsOnRotatedPages() async throws {
        let fixture = try ConvertFixture()
        for rotation in [0, 90, 180, 270] {
            let source = fixture.savePDF("Annotated-\(rotation).pdf", pages: 1, withText: false)
            let document = try #require(PDFDocument(url: source))
            let page = try #require(document.page(at: 0))
            page.rotation = rotation
            let annotation = PDFAnnotation(bounds: CGRect(x: 350, y: 500, width: 150, height: 150), forType: .square, withProperties: nil)
            annotation.color = .black
            annotation.interiorColor = .black
            page.addAnnotation(annotation)
            try #require(document.write(to: source))
            let result = try output(await fixture.convert([source], to: .pagePNG, quality: .smaller))
            let image = try #require(PictureCheck(result))
            let reference = PictureCheck(try #require(page.thumbnail(of: CGSize(width: image.width, height: image.height), for: .cropBox)
                .cgImage(forProposedRect: nil, context: nil, hints: nil)))
            #expect(image.width == (rotation % 180 == 0 ? 612 : 792))
            for y in stride(from: 0.1, to: 1.0, by: 0.1) {
                for x in stride(from: 0.1, to: 1.0, by: 0.1) {
                    #expect(abs(image.brightness(x: x, y: y) - reference.brightness(x: x, y: y)) < 15)
                }
            }
        }
    }

    @Test func combiningKeepsAnnotationsMetadataAndBookmarkTargets() async throws {
        let fixture = try ConvertFixture()
        let first = fixture.savePDF("First.pdf", pages: 2)
        let second = fixture.url("Bookmarked.pdf")
        let original = try #require(PDFDocument(url: fixture.savePDF("Second.pdf", pages: 2)))
        // PDFKit omits newly added outlines when saving some loaded Quartz PDFs. Build a fresh
        // document so this fixture really contains the bookmarks the converter must preserve.
        let source = PDFDocument()
        while let page = original.page(at: 0) {
            original.removePage(at: 0)
            source.insert(page, at: source.pageCount)
        }
        let page = try #require(source.page(at: 1))
        page.rotation = 90
        let link = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 100, height: 30), forType: .link, withProperties: nil)
        link.url = URL(string: "https://example.com/test")
        page.addAnnotation(link)
        let root = PDFOutline(), bookmark = PDFOutline()
        bookmark.label = "Last page"
        bookmark.destination = PDFDestination(page: page, at: CGPoint(x: 12, y: 34))
        root.insertChild(bookmark, at: 0)
        source.outlineRoot = root
        source.documentAttributes = [PDFDocumentAttribute.titleAttribute: "Bookmarked report"]
        try #require(source.write(to: second))
        #expect(PDFDocument(url: second)?.outlineRoot?.numberOfChildren == 1)
        let firstDocument = try #require(PDFDocument(url: first))
        firstDocument.documentAttributes = [PDFDocumentAttribute.titleAttribute: "Report title"]
        try #require(firstDocument.write(to: first))
        let image = fixture.savePicture(ConvertFixture.picture(width: 80, height: 40), "Photo.jpg", .jpeg)
        let result = try output(await fixture.convert([first, image, second], to: .combinedPDF))
        #expect(try Data(contentsOf: result).range(of: Data(contentsOf: image)) != nil)
        let combined = try #require(PDFDocument(url: result))
        #expect(combined.pageCount == 5)
        #expect(combined.page(at: 4)?.rotation == 90)
        #expect(combined.page(at: 4)?.annotations.first?.url == link.url)
        #expect(combined.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Report title")
        let destination = try #require(combined.outlineRoot?.child(at: 0)?.destination)
        #expect(combined.index(for: try #require(destination.page)) == 4)
    }

    @Test func oldTextEncodingsKeepPunctuation() async throws {
        let fixture = try ConvertFixture()
        let words = "Café costs €5 — “hello”"
        let source = fixture.url("Windows.txt")
        try #require(words.data(using: .windowsCP1252)).write(to: source)
        let result = try output(await fixture.convert([source], to: .rtf))
        #expect(try NSAttributedString(url: result, options: [:], documentAttributes: nil).string == words)
    }

    @Test func plainTextKeepsTableRowsLinksAndBlankLines() throws {
        let text = NSMutableAttributedString(string: "\nIntro\nName\nQty\nApple\n3\nRead more\nexample.com\nline\u{2028}two\u{FFFC}\n")
        let table = NSTextTable()
        table.numberOfColumns = 2
        for (index, words) in ["Name\n", "Qty\n", "Apple\n", "3\n"].enumerated() {
            let style = NSMutableParagraphStyle()
            style.textBlocks = [NSTextTableBlock(table: table, startingRow: index / 2, rowSpan: 1, startingColumn: index % 2, columnSpan: 1)]
            text.addAttribute(.paragraphStyle, value: style, range: (text.string as NSString).range(of: words))
        }
        text.addAttribute(.link, value: URL(string: "https://example.com/page")!, range: (text.string as NSString).range(of: "Read more"))
        text.addAttribute(.link, value: URL(string: "https://example.com/")!, range: (text.string as NSString).range(of: "example.com"))
        #expect(DocumentConversion.plainText(text) == "\nIntro\nName\tQty\nApple\t3\nRead more (https://example.com/page)\nexample.com\nline\ntwo\n")
        // The real RTF writer/reader must retain the table and link attributes too.
        let rtf = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let restored = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        let plain = DocumentConversion.plainText(restored)
        #expect(plain.contains("Name\tQty\nApple\t3"))
        #expect(plain.contains("Read more (https://example.com/page)"))
        #expect(PDFConversion.plainLetters("ﬁnd ﬂowers ﬃ ﬄ ﬀ ﬅ ﬆ café") == "find flowers ffi ffl ff st st café")
    }

    private func samples(_ url: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channels = try #require(buffer.floatChannelData)
        return (0..<Int(buffer.format.channelCount)).map { Array(UnsafeBufferPointer(start: channels[$0], count: Int(buffer.frameLength))) }
    }

    private func packets(_ url: URL) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        try #require(reader.startReading())
        var result = Data()
        while let sample = output.copyNextSampleBuffer() {
            // AAC trim markers can be sample buffers without encoded bytes.
            guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
            var bytes = [UInt8](repeating: 0, count: CMBlockBufferGetDataLength(buffer))
            try #require(CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: bytes.count, destination: &bytes) == noErr)
            result.append(contentsOf: bytes)
        }
        #expect(reader.status == .completed)
        return result
    }
}
