import ConvertKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// PDFs to page pictures or text, and pictures and PDFs into one PDF. Pages are drawn one at a time and
/// let go before the next, so a long PDF costs no more memory than a short one.
enum PDFConversion {
    /// Opens a PDF protected by an owner password only (it reads without one); false if it needs a password.
    static func unlock(_ document: CGPDFDocument) -> Bool {
        !document.isEncrypted || document.isUnlocked || document.unlockWithPassword("")
    }

    static func openDocument(_ url: URL) throws -> CGPDFDocument {
        guard let document = CGPDFDocument(url as CFURL) else { throw ConvertFailure.unreadable }
        guard unlock(document) else { throw ConvertFailure.unsupported }
        return document
    }

    // MARK: Pages as pictures

    /// One picture for a one-page PDF, otherwise a folder named `base` with "Page 01.png"…
    static func pages(
        of url: URL, as format: ConvertFormat, quality: ConvertQuality, in folder: URL, base: String,
        pageName: String, progress: ConvertEngine.Progress
    ) throws -> URL {
        let document = try openDocument(url)
        let count = document.numberOfPages
        guard count > 0 else { throw ConvertFailure.unreadable }
        let type = ImageConversion.type(for: format)
        if count == 1 {
            let output = folder.appending(path: base + "." + format.fileExtension)
            try autoreleasepool { try writePage(1, of: document, at: url, scale: quality.pageScale, quality: quality, type: type, to: output) }
            progress(1)
            return output
        }
        let pagesFolder = folder.appending(path: base, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pagesFolder, withIntermediateDirectories: true)
        let digits = max(2, String(count).count)
        for number in 1...count {
            let padded = String(repeating: "0", count: digits - String(number).count) + String(number)
            let output = pagesFolder.appending(path: "\(pageName) \(padded).\(format.fileExtension)")
            try autoreleasepool { try writePage(number, of: document, at: url, scale: quality.pageScale, quality: quality, type: type, to: output) }
            progress(Double(number) / Double(count))
        }
        return pagesFolder
    }

    private static func writePage(_ number: Int, of document: CGPDFDocument, at url: URL, scale: Double, quality: ConvertQuality, type: UTType, to output: URL) throws {
        guard let page = document.page(at: number) else { throw ConvertFailure.unreadable }
        let size = uprightSize(of: page)
        var scale = scale
        if size.width * size.height * scale * scale > ConvertLimits.maxPagePixels {
            scale = (ConvertLimits.maxPagePixels / (size.width * size.height)).squareRoot()
        }
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ConvertFailure.tooBig }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.interpolationQuality = .high
        // Highlights, notes and filled-in forms are annotations, which Quartz leaves out: PDFKit draws a page
        // that has them (opened for that page alone, so a long PDF doesn't pile up in memory). PDFKit turns
        // and places the page itself.
        if hasAnnotations(page), let annotated = PDFDocument(url: url), annotated.isLocked ? annotated.unlock(withPassword: "") : true,
           let pdfPage = annotated.page(at: number - 1) {
            context.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
            pdfPage.draw(with: .cropBox, to: context)
            return try save(context, type: type, quality: quality, to: output)
        }
        context.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        // getDrawingTransform only shrinks: scale up around the page for anything over 1×.
        if scale > 1 {
            let box = page.getBoxRect(.cropBox)
            context.translateBy(x: box.midX, y: box.midY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.midX, y: -box.midY)
        }
        context.drawPDFPage(page)
        try save(context, type: type, quality: quality, to: output)
    }

    private static func save(_ context: CGContext, type: UTType, quality: ConvertQuality, to output: URL) throws {
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvertFailure.cantWrite
        }
        let options: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: quality.lossyQuality] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConvertFailure.cantWrite }
    }

    /// Whether the page has annotations: highlights, notes, shapes, links or form fields.
    static func hasAnnotations(_ page: CGPDFPage) -> Bool {
        var annotations: CGPDFArrayRef?
        guard let dictionary = page.dictionary, CGPDFDictionaryGetArray(dictionary, "Annots", &annotations), let annotations else { return false }
        return CGPDFArrayGetCount(annotations) > 0
    }

    /// The page's crop box as it's shown, turned by its rotation.
    static func uprightSize(of page: CGPDFPage) -> CGSize {
        let box = page.getBoxRect(.cropBox).size
        return page.rotationAngle % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
    }

    // MARK: Text

    /// Pages read per opening of the PDF: PDFKit keeps what it read of every page until the document goes.
    static let textPagesPerOpening = 20

    /// The PDF's text, page after page. A scanned PDF has none: that's an empty file, so it's refused.
    static func text(of url: URL, output: URL, progress: ConvertEngine.Progress) throws {
        guard let first = PDFDocument(url: url) else { throw ConvertFailure.unreadable }
        if first.isLocked, !first.unlock(withPassword: "") { throw ConvertFailure.unsupported }
        let count = first.pageCount
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: output) else { throw ConvertFailure.cantWrite }
        defer { try? handle.close() }
        var wroteText = false
        var document: PDFDocument? = first
        for index in 0..<count {
            try autoreleasepool {
                if document == nil {
                    document = PDFDocument(url: url)
                    if document?.isLocked == true { _ = document?.unlock(withPassword: "") }
                }
                defer { if (index + 1) % textPagesPerOpening == 0 { document = nil } }
                guard let text = document?.page(at: index)?.string.map(plainLetters), !text.isEmpty else { return }
                do {
                    try handle.write(contentsOf: Data(((wroteText ? "\n\n" : "") + text).utf8))
                } catch {
                    throw ConvertFailure.cantWrite
                }
                wroteText = true
            }
            progress(Double(index + 1) / Double(count))
        }
        guard wroteText else { throw ConvertFailure.noText }
    }

    /// Typesetting ligatures ("ﬁ", "ﬀ"…) as their letters, so a search for "find" finds the text.
    static func plainLetters(_ text: String) -> String {
        let ligatures: [Character: String] = ["\u{FB00}": "ff", "\u{FB01}": "fi", "\u{FB02}": "fl", "\u{FB03}": "ffi", "\u{FB04}": "ffl", "\u{FB05}": "st", "\u{FB06}": "st"]
        guard text.unicodeScalars.contains(where: { (0xFB00...0xFB06).contains($0.value) }) else { return text }
        return text.reduce(into: "") { result, character in
            if let letters = ligatures[character] { result += letters } else { result.append(character) }
        }
    }

    // MARK: One PDF

    /// Every page of every PDF, and each picture as a page, into one PDF. When every file is a photo that
    /// passes through (`ConvertCatalog.picturesPassThrough`), nothing is decoded. Otherwise the pictures are
    /// drawn as pages by macOS first, then PDFKit puts every page in as it is: text, links, highlights,
    /// notes and bookmarks stay.
    static func combine(_ urls: [URL], passesThrough: Bool, quality: ConvertQuality, into output: URL, progress: ConvertEngine.Progress) throws {
        if passesThrough {
            let writer = try PicturePDFWriter(url: output)
            let scratch = output.deletingLastPathComponent().appending(path: ".picture-\(UUID().uuidString).jpg")
            defer { try? FileManager.default.removeItem(at: scratch) }
            for (index, url) in urls.enumerated() {
                try autoreleasepool { try addPicturePage(url, quality: quality, scratch: scratch, to: writer) }
                progress(Double(index + 1) / Double(urls.count))
            }
            try writer.finish()
            return
        }
        // The pictures' pages, in order, in a scratch PDF.
        let pictures = urls.filter { ConvertKind(url: $0) != .pdf }
        let scratch = output.deletingLastPathComponent().appending(path: ".pictures-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: scratch) }
        var picturePages: PDFDocument?
        if !pictures.isEmpty {
            guard let context = CGContext(scratch as CFURL, mediaBox: nil, nil) else { throw ConvertFailure.cantWrite }
            for url in pictures {
                try autoreleasepool { try drawPicturePage(url, quality: quality, in: context) }
            }
            context.closePDF()
            picturePages = PDFDocument(url: scratch)
            guard picturePages?.pageCount == pictures.count else { throw ConvertFailure.failed }
        }

        let combined = PDFDocument()
        let bookmarks = PDFOutline()
        var sources: [PDFDocument] = []
        var nextPicture = 0
        for (index, url) in urls.enumerated() {
            if ConvertKind(url: url) == .pdf {
                guard let document = PDFDocument(url: url) else { throw ConvertFailure.unreadable }
                if document.isLocked, !document.unlock(withPassword: "") { throw ConvertFailure.unsupported }
                if sources.isEmpty { combined.documentAttributes = document.documentAttributes }
                sources.append(document)
                // Bookmarks are noted (as page numbers) before their pages move to the combined PDF.
                let marks = document.outlineRoot.map { Bookmark.children(of: $0, in: document) } ?? []
                let offset = combined.pageCount
                while document.pageCount > 0, let page = document.page(at: 0) {
                    document.removePage(at: 0)
                    combined.insert(page, at: combined.pageCount)
                }
                for mark in marks {
                    bookmarks.insertChild(mark.outline(in: combined, offset: offset), at: bookmarks.numberOfChildren)
                }
            } else if let page = picturePages?.page(at: nextPicture) {
                nextPicture += 1
                combined.insert(page, at: combined.pageCount)
            }
            progress(0.8 * Double(index + 1) / Double(urls.count))
        }
        guard combined.pageCount > 0 else { throw ConvertFailure.unreadable }
        if bookmarks.numberOfChildren > 0 { combined.outlineRoot = bookmarks }
        guard combined.write(to: output) else { throw ConvertFailure.cantWrite }
        withExtendedLifetime(sources) {}
        progress(1)
    }

    /// A bookmark with the page it opens as a number, so it can point at that page in another PDF.
    private struct Bookmark {
        var label: String?
        var page: Int?
        var point: CGPoint
        var isOpen: Bool
        var children: [Bookmark]

        static func children(of outline: PDFOutline, in document: PDFDocument) -> [Bookmark] {
            (0..<outline.numberOfChildren).compactMap { outline.child(at: $0) }.map { child in
                let page = child.destination?.page.map { document.index(for: $0) }.flatMap { $0 == NSNotFound ? nil : $0 }
                return Bookmark(
                    label: child.label, page: page, point: child.destination?.point ?? .zero, isOpen: child.isOpen,
                    children: children(of: child, in: document)
                )
            }
        }

        func outline(in document: PDFDocument, offset: Int) -> PDFOutline {
            let outline = PDFOutline()
            outline.label = label
            if let page, let target = document.page(at: offset + page) { outline.destination = PDFDestination(page: target, at: point) }
            for (index, child) in children.enumerated() { outline.insertChild(child.outline(in: document, offset: offset), at: index) }
            outline.isOpen = isOpen
            return outline
        }
    }

    /// A JPEG or HEIF photo as a page the size it would print at: a JPEG goes in as it is, anything else
    /// (or a shrunk one) is re-encoded as JPEG straight from the file into `scratch`, then read from there
    /// as it's written (mapped, so a big JPEG isn't held in memory).
    private static func addPicturePage(_ url: URL, quality: ConvertQuality, scratch: URL, to writer: PicturePDFWriter) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ConvertFailure.unreadable
        }
        let shrinksTo = quality.maxPixelSize.flatMap { max(pixelWidth, pixelHeight) > $0 ? $0 : nil }
        var file = url
        if CGImageSourceGetType(source) as String? != UTType.jpeg.identifier || shrinksTo != nil {
            try ImageConversion.writeJPEG(from: source, quality: quality, maxPixelSize: shrinksTo, to: scratch)
            file = scratch
        }
        guard let jpeg = try? Data(contentsOf: file, options: .alwaysMapped) else { throw ConvertFailure.unreadable }
        // The orientation as the JPEG has it (re-encoding keeps the tag and the pixels as stored).
        let stored = CGImageSourceCreateWithData(jpeg as CFData, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        let orientation = (stored?[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        try writer.addPage(jpeg: jpeg, orientation: orientation, size: pageSize(properties, width: pixelWidth, height: pixelHeight))
    }

    /// A picture's page in points, upright: its pixels at its resolution (72 dpi when it doesn't say).
    private static func pageSize(_ properties: [CFString: Any], width: Int, height: Int) -> CGSize {
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        let turned = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
        let dpi = (properties[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 72
        let points = 72 / dpi
        return CGSize(width: Double(turned ? height : width) * points, height: Double(turned ? width : height) * points)
    }

    /// A picture as a page the size it would print at, drawn by macOS. A JPEG photo goes in as it is, a HEIF
    /// one as JPEG (made straight from the file); anything else (PNG, TIFF, transparent or print-colour
    /// pictures) is drawn as it is, so screenshots stay sharp.
    private static func drawPicturePage(_ url: URL, quality: ConvertQuality, in context: CGContext) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ConvertFailure.unreadable
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        let turned = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
        var media = CGRect(origin: .zero, size: pageSize(properties, width: pixelWidth, height: pixelHeight))
        let longSide = max(pixelWidth, pixelHeight)
        let shrinksTo = quality.maxPixelSize.flatMap { longSide > $0 ? $0 : nil }
        let info = ConvertProbe.image(url)

        context.beginPage(mediaBox: &media)
        defer { context.endPage() }
        // A JPEG that keeps its size goes in as it is (mapped, not read): re-encoding it would only lose.
        let isJPEG = CGImageSourceGetType(source) as String? == UTType.jpeg.identifier
        if info.passesThroughToPDF,
           let data = isJPEG && shrinksTo == nil
               ? try? Data(contentsOf: url, options: .alwaysMapped)
               : ImageConversion.jpegData(from: source, quality: quality, maxPixelSize: shrinksTo),
           let provider = CGDataProvider(data: data as CFData),
           let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
            context.concatenate(orientationTransform(orientation, size: media.size))
            context.draw(jpeg, in: CGRect(origin: .zero, size: turned ? CGSize(width: media.height, height: media.width) : media.size))
        } else {
            guard let image = ImageConversion.decode(source, maxPixelSize: shrinksTo) else { throw ConvertFailure.unreadable }
            context.draw(image, in: media)
        }
    }

    /// Draws a picture stored turned or mirrored (EXIF orientation) upright in a box of `size`.
    static func orientationTransform(_ orientation: CGImagePropertyOrientation, size: CGSize) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        switch orientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: size.height).rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: size.width, y: 0).rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: size.height).rotated(by: -.pi / 2)
        default:
            break
        }
        switch orientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: 0).scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: size.height, y: 0).scaledBy(x: -1, y: 1)
        default:
            break
        }
        return transform
    }
}
