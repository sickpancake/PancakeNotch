import AVFoundation
import ConvertKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import ConvertEngine

/// Each conversion, run for real on small files made by the test.
@MainActor
struct ConversionTests {
    func output(_ message: ConvertMessage, _ index: Int = 0) throws -> URL {
        #expect(message.errors == [])
        let outputs = try #require(message.outputs)
        try #require(outputs.count > index)
        return URL(fileURLWithPath: outputs[index].path)
    }

    // MARK: Pictures

    @Test(arguments: [ConvertFormat.png, .heic, .tiff])
    func picturesKeepTheirSize(format: ConvertFormat) async throws {
        let fixture = try ConvertFixture()
        let source = fixture.savePicture(ConvertFixture.picture(width: 300, height: 200), "Photo.jpg", .jpeg)
        let result = try output(await fixture.convert([source], to: format))
        #expect(result.lastPathComponent == "Photo.\(format.fileExtension)")
        let check = try #require(PictureCheck(result))
        #expect(check.width == 300 && check.height == 200)
        #expect(check.brightness(x: 0.05, y: 0.05) < 40) // the black corner stays top-left
    }

    @Test func seeThroughBecomesWhiteInJPEG() async throws {
        let fixture = try ConvertFixture()
        let source = fixture.savePicture(ConvertFixture.picture(width: 200, height: 200, clearEdges: true), "Logo.png", .png)
        let check = try #require(PictureCheck(try output(await fixture.convert([source], to: .jpeg))))
        #expect(check.brightness(x: 0.05, y: 0.05) > 245)
    }

    @Test func smallerShrinksBigPictures() async throws {
        let fixture = try ConvertFixture()
        let source = fixture.savePicture(ConvertFixture.picture(width: 3000, height: 1000), "Wide.jpg", .jpeg)
        let check = try #require(PictureCheck(try output(await fixture.convert([source], to: .png, quality: .smaller))))
        #expect(check.width == 2000)
        #expect((666...667).contains(check.height))
    }

    // MARK: PDFs

    @Test func combinePutsPhotosUprightOnePerPage() async throws {
        let fixture = try ConvertFixture()
        // Stored on its side, shown upright (orientation 6): the black corner shows top-right.
        let turned = fixture.savePicture(ConvertFixture.picture(width: 400, height: 300), "Turned.jpg", .jpeg, orientation: 6)
        let plain = fixture.savePicture(ConvertFixture.picture(width: 400, height: 300), "Plain.heic", .heic)
        let result = try output(await fixture.convert([turned, plain], to: .combinedPDF))
        #expect(result.lastPathComponent == "Combined.pdf")
        let document = try #require(PDFDocument(url: result))
        #expect(document.pageCount == 2)
        let first = try #require(document.page(at: 0))
        let bounds = first.bounds(for: .mediaBox)
        #expect(bounds.width == 300 && bounds.height == 400)
        let picture = PictureCheck(first.thumbnail(of: CGSize(width: 300, height: 400), for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        #expect(picture.brightness(x: 0.95, y: 0.05) < 60)
        #expect(picture.brightness(x: 0.05, y: 0.05) > 100)
        let second = PictureCheck(try #require(document.page(at: 1)).thumbnail(of: CGSize(width: 400, height: 300), for: .mediaBox)
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        #expect(second.brightness(x: 0.05, y: 0.05) < 60)
    }

    @Test func combineMixesPDFsAndPictures() async throws {
        let fixture = try ConvertFixture()
        let pdf = fixture.savePDF("Report.pdf", pages: 3)
        let screenshot = fixture.savePicture(ConvertFixture.picture(width: 200, height: 100), "Shot.png", .png)
        let document = try #require(PDFDocument(url: try output(await fixture.convert([pdf, screenshot], to: .combinedPDF))))
        #expect(document.pageCount == 4)
        #expect(document.page(at: 2)?.string?.contains("Page 3") == true)
    }

    @Test func pdfPagesBecomeAFolderOfPictures() async throws {
        let fixture = try ConvertFixture()
        let pdf = fixture.savePDF("Report.pdf", pages: 3)
        let folder = try output(await fixture.convert([pdf], to: .pagePNG))
        #expect(folder.lastPathComponent == "Report")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == ["Page 01.png", "Page 02.png", "Page 03.png"])
        let page = try #require(PictureCheck(folder.appending(path: "Page 01.png")))
        #expect(page.width == 1224 && page.height == 1584) // Letter at 2× (Balanced)
    }

    @Test func aOnePagePDFBecomesOnePicture() async throws {
        let fixture = try ConvertFixture()
        let pdf = fixture.savePDF("Ticket.pdf", pages: 1)
        let result = try output(await fixture.convert([pdf], to: .pageJPEG, quality: .smaller))
        #expect(result.lastPathComponent == "Ticket.jpg")
        #expect(PictureCheck(result)?.width == 612)
    }

    @Test func pdfTextAndAPDFWithoutText() async throws {
        let fixture = try ConvertFixture()
        let text = try String(contentsOf: try output(await fixture.convert([fixture.savePDF("Report.pdf", pages: 2)], to: .text)), encoding: .utf8)
        #expect(text.contains("Page 1 of the report") && text.contains("Page 2 of the report"))
        let scan = await fixture.convert([fixture.savePDF("Scan.pdf", pages: 1, withText: false)], to: .text)
        #expect(scan.errors == [ConvertError(source: 0, failure: .noText)])
    }

    @Test func probeWeighsPicturesInPDFs() async throws {
        let fixture = try ConvertFixture()
        let grey = await ConvertProbe.info(for: fixture.savePicturePDF("Grey.pdf", width: 1000, height: 800, grey: true))
        let colour = await ConvertProbe.info(for: fixture.savePicturePDF("Colour.pdf", width: 1000, height: 800, grey: false))
        #expect(grey.largestPictureBytes == 800_000)
        #expect(colour.largestPictureBytes == 3_200_000)
        #expect(grey.largestPageArea == 484_704.0) // Letter, 612 × 792 points
        let text = await ConvertProbe.info(for: fixture.savePDF("Text.pdf", pages: 2))
        #expect(text.largestPictureBytes == 0 && text.pageCount == 2)
    }

    // MARK: Sound and video

    @Test(arguments: [ConvertFormat.m4a, .appleLossless, .wav])
    func audioConverts(format: ConvertFormat) async throws {
        let fixture = try ConvertFixture()
        // Low-rate mono (speech) is where AAC's bit rate has to come down.
        let source = try fixture.saveTone("Memo.aiff", seconds: 2, rate: 22_050, channels: 1, bigEndian: true)
        let result = try output(await fixture.convert([source], to: format))
        let asset = AVURLAsset(url: result)
        #expect(try await asset.load(.isReadable))
        #expect(abs(try await asset.load(.duration).seconds - 2) < 0.1)
    }

    @Test func videosRepackageAndGiveTheirSound() async throws {
        let fixture = try ConvertFixture()
        let clip = try await fixture.saveClip("Clip.mov")
        let mp4 = try output(await fixture.convert([clip], to: .mp4))
        #expect(mp4.pathExtension == "mp4")
        #expect(try await AVURLAsset(url: mp4).load(.isReadable))
        // No sound in this clip: "Audio only" says so instead of making an empty file.
        let info = await ConvertProbe.info(for: clip)
        #expect(ConvertCatalog.note(for: .audioOnly, info: info, quality: .balanced) == .noSound)
    }

    @Test func aClipBecomesAnUprightGIF() async throws {
        let fixture = try ConvertFixture()
        let clip = try await fixture.saveClip("Portrait.mov", turned: true)
        let gif = try output(await fixture.convert([clip], to: .gif))
        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect((11...13).contains(CGImageSourceGetCount(source)))
        let frame = try #require(PictureCheck(gif))
        #expect(frame.width == 90 && frame.height == 160)
        #expect(frame.brightness(x: 0.9, y: 0.05) < 60)
        #expect(frame.brightness(x: 0.1, y: 0.95) > 200)
    }

    // MARK: Documents

    @Test func textBecomesAPDFAndRichText() async throws {
        let fixture = try ConvertFixture()
        let source = fixture.url("Notes.txt")
        try (1...200).map { "Line \($0) of the notes." }.joined(separator: "\n").write(to: source, atomically: true, encoding: .utf8)
        let pdf = try #require(PDFDocument(url: try output(await fixture.convert([source], to: .pdf))))
        #expect(pdf.pageCount >= 3)
        #expect(pdf.page(at: 0)?.string?.contains("Line 1 of the notes.") == true)
        let rtf = try output(await fixture.convert([source], to: .rtf))
        let back = try NSAttributedString(url: rtf, options: [:], documentAttributes: nil)
        #expect(back.string.hasPrefix("Line 1 of the notes."))
    }

    @Test func wordBecomesText() async throws {
        let fixture = try ConvertFixture()
        let document = NSAttributedString(string: "Hello from Word")
        let source = fixture.url("Letter.docx")
        try document.data(from: NSRange(location: 0, length: document.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
            .write(to: source)
        let text = try String(contentsOf: try output(await fixture.convert([source], to: .text)), encoding: .utf8)
        #expect(text.contains("Hello from Word"))
    }

    // MARK: Failures

    @Test func aMissingFileIsReportedNotThrown() async throws {
        let fixture = try ConvertFixture()
        let message = await fixture.convert([fixture.url("Gone.jpg")], to: .png)
        #expect(message.outputs == [])
        #expect(message.errors?.first?.source == 0)
    }

    @Test func oneBadFileDoesNotStopTheRest() async throws {
        let fixture = try ConvertFixture()
        let good = fixture.savePicture(ConvertFixture.picture(width: 50, height: 50), "Good.heic", .heic)
        let message = await fixture.convert([fixture.url("Gone.heic"), good], to: .jpeg)
        #expect(message.outputs?.map(\.source) == [1])
        #expect(message.errors?.map(\.source) == [0])
    }
}
