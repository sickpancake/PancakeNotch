import ConvertKit
import Foundation
import Testing

/// Which formats a file is offered, and when a format is dimmed (ADR-0038).
struct ConvertCatalogTests {
    func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    func photo(_ width: Int, _ height: Int, type: String = "public.jpeg", alpha: Bool = false) -> ConvertFileInfo {
        ConvertFileInfo(kind: .image, pixelWidth: width, pixelHeight: height, hasAlpha: alpha, imageType: type)
    }

    @Test func kindsComeFromTheExtension() {
        #expect(ConvertKind(url: url("a.HEIC")) == .image)
        #expect(ConvertKind(url: url("a.pdf")) == .pdf)
        #expect(ConvertKind(url: url("a.flac")) == .audio)
        #expect(ConvertKind(url: url("a.m4v")) == .video)
        #expect(ConvertKind(url: url("a.md")) == .plainText)
        #expect(ConvertKind(url: url("a.rtfd")) == .richText)
        #expect(ConvertKind(url: url("a.docx")) == .wordDocument)
        // Camera RAW is too heavy to decode; a ZIP isn't converted at all.
        #expect(ConvertKind(url: url("a.dng")) == nil)
        #expect(ConvertKind(url: url("a.zip")) == nil)
    }

    @Test func aFileIsNeverOfferedItsOwnFormat() {
        #expect(ConvertCatalog.formats(for: [url("a.heic")], wordToPDF: false) == [.jpeg, .png, .tiff, .pdf])
        #expect(ConvertCatalog.formats(for: [url("a.jpeg")], wordToPDF: false) == [.png, .heic, .tiff, .pdf])
        #expect(ConvertCatalog.formats(for: [url("a.wav")], wordToPDF: false) == [.m4a, .appleLossless, .aiff])
        #expect(ConvertCatalog.formats(for: [url("a.mov")], wordToPDF: false) == [.mp4, .audioOnly, .gif])
        #expect(ConvertCatalog.formats(for: [url("a.m4v")], wordToPDF: false) == [.mp4, .mov, .audioOnly, .gif])
        #expect(ConvertCatalog.formats(for: [url("a.rtf")], wordToPDF: false) == [.pdf, .text])
    }

    @Test func wordToPDFIsAnExperiment() {
        #expect(ConvertCatalog.formats(for: [url("a.docx")], wordToPDF: false) == [.text])
        #expect(ConvertCatalog.formats(for: [url("a.odt")], wordToPDF: true) == [.pdf, .text])
        let withPictures = ConvertFileInfo(kind: .wordDocument, hasPictures: true)
        let note = ConvertCatalog.note(for: .pdf, info: withPictures, quality: .balanced)
        #expect(note == .picturesNotKept)
        #expect(note?.allowsConverting == true)
    }

    @Test func severalFilesShareFormatsAndPicturesCombine() {
        let pictures = ConvertCatalog.formats(for: [url("a.jpg"), url("b.png"), url("c.pdf")], wordToPDF: false)
        #expect(pictures == [.combinedPDF])
        let photos = ConvertCatalog.formats(for: [url("a.heic"), url("b.heic")], wordToPDF: false)
        #expect(photos == [.combinedPDF, .jpeg, .png, .tiff, .pdf])
        #expect(ConvertCatalog.formats(for: [url("a.jpg"), url("b.mp3")], wordToPDF: false).isEmpty)
        #expect(ConvertCatalog.formats(for: [url("a.jpg"), url("b.zip")], wordToPDF: false).isEmpty)
        #expect(!ConvertCatalog.formats(for: [url("a.wav"), url("b.mp3")], wordToPDF: false).contains(.combinedPDF))
    }

    @Test func bigPicturesAreTooBigForFormatsThatDecodeThemWhole() {
        let photo12 = photo(4032, 3024)
        // Streamed: fine at any size the camera makes.
        #expect(ConvertCatalog.note(for: .pdf, info: photo12, quality: .best) == nil)
        // PNG decodes it all: too big, unless Smaller shrinks it first.
        #expect(ConvertCatalog.note(for: .png, info: photo12, quality: .balanced) == .tooBig)
        #expect(ConvertCatalog.note(for: .png, info: photo12, quality: .smaller) == nil)
        #expect(ConvertCatalog.note(for: .png, info: photo(2000, 1500), quality: .best) == nil)
        // A big transparent picture is drawn onto white for JPEG.
        #expect(ConvertCatalog.note(for: .jpeg, info: photo(4000, 3000, type: "public.png", alpha: true), quality: .balanced) == .tooBig)
        let options = ConvertCatalog.options(for: [url("a.jpg")], infos: [photo12], wordToPDF: false, quality: .balanced)
        #expect(options.first { $0.format == .png }?.isAvailable == false)
        #expect(options.first { $0.format == .pdf }?.isAvailable == true)
    }

    @Test func combineChecksAllTheFilesTogether() {
        let photos = [photo(5657, 4243), photo(4032, 3024), photo(4032, 3024)]
        // JPEG photos pass straight through into the PDF, whatever their size.
        #expect(ConvertCatalog.picturesPassThrough(photos))
        #expect(ConvertCatalog.combineNote(for: photos, quality: .best) == nil)
        // A PDF among them means macOS draws everything, and a big photo is then too much.
        let page = ConvertFileInfo(kind: .pdf, pageCount: 1, isLocked: false, largestPictureBytes: 0, largestPageArea: 612 * 792)
        #expect(!ConvertCatalog.picturesPassThrough(photos + [page]))
        #expect(ConvertCatalog.combineNote(for: photos + [page], quality: .best) == .tooBig)
        #expect(ConvertCatalog.combineNote(for: [photo(1600, 1200), page], quality: .best) == nil)
        // A scanned page in grey is light; the same in colour is heavy.
        let grey = ConvertFileInfo(kind: .pdf, pageCount: 1, isLocked: false, largestPictureBytes: 2480 * 3508, largestPageArea: 595 * 842)
        let colour = ConvertFileInfo(kind: .pdf, pageCount: 1, isLocked: false, largestPictureBytes: 2480 * 3508 * 4, largestPageArea: 595 * 842)
        #expect(ConvertCatalog.combineNote(for: [grey, page], quality: .balanced) == nil)
        #expect(ConvertCatalog.combineNote(for: [colour, page], quality: .balanced) == .tooBig)
        // Copying PDF pages preserves annotations and retains their objects until the result is saved.
        var long = page
        long.pageCount = 1000
        #expect(ConvertCatalog.combineNote(for: [long], quality: .balanced) == nil)
        #expect(ConvertCatalog.combineNote(for: [long, long], quality: .balanced) == .tooBig)
    }

    @Test func pdfNotes() {
        let locked = ConvertFileInfo(kind: .pdf, pageCount: 3, isLocked: true)
        #expect(ConvertCatalog.note(for: .pagePNG, info: locked, quality: .balanced) == .locked)
        let text = ConvertFileInfo(kind: .pdf, pageCount: 300, isLocked: false, largestPictureBytes: 0, largestPageArea: 612 * 792)
        #expect(ConvertCatalog.note(for: .pagePNG, info: text, quality: .best) == nil)
        #expect(ConvertCatalog.note(for: .text, info: text, quality: .best) == nil)
        #expect(ConvertCatalog.note(for: .text, info: ConvertFileInfo(kind: .pdf, isReadable: false), quality: .best) == .unreadable)
    }

    @Test func videoNotes() {
        let clip = ConvertFileInfo(kind: .video, duration: 12, videoWidth: 1920, videoHeight: 1080, hasAudio: false, repackages: [.mp4])
        #expect(ConvertCatalog.note(for: .gif, info: clip, quality: .balanced) == nil)
        #expect(ConvertCatalog.note(for: .mp4, info: clip, quality: .balanced) == nil)
        #expect(ConvertCatalog.note(for: .mov, info: clip, quality: .balanced) == .cantRepackage)
        #expect(ConvertCatalog.note(for: .audioOnly, info: clip, quality: .balanced) == .noSound)
        var long = clip
        long.duration = 16
        #expect(ConvertCatalog.note(for: .gif, info: long, quality: .balanced) == .tooLong)
        var portrait = clip
        (portrait.videoWidth, portrait.videoHeight) = (1080, 1920)
        #expect(ConvertCatalog.note(for: .gif, info: portrait, quality: .balanced) == nil)
        var fourK = clip
        (fourK.videoWidth, fourK.videoHeight) = (3840, 2160)
        #expect(ConvertCatalog.note(for: .gif, info: fourK, quality: .balanced) == .tooBig)
    }

    @Test func namesNeverOverwrite() {
        let folder = URL(fileURLWithPath: "/tmp/folder", isDirectory: true)
        let taken: Set<String> = ["Report.pdf", "Report 2.pdf", "Pages"]
        let exists = { (url: URL) in taken.contains(url.lastPathComponent) }
        #expect(ConvertNaming.uniqueURL(in: folder, base: "Report", ext: "pdf", exists: exists).lastPathComponent == "Report 3.pdf")
        #expect(ConvertNaming.uniqueURL(in: folder, base: "Report", ext: "txt", exists: exists).lastPathComponent == "Report.txt")
        #expect(ConvertNaming.uniqueURL(in: folder, base: "Pages", ext: nil, exists: exists).lastPathComponent == "Pages 2")
        #expect(ConvertNaming.uniqueURL(in: folder, base: "a/b:c", ext: "png", exists: exists).lastPathComponent == "a-b-c.png")
    }
}
