import AppKit
import ConvertKit
import Foundation

/// Text, RTF, Word and ODT files with AppKit's text system: plain text, RTF, or a PDF laid out page by
/// page on the document's own paper size (A4 or Letter by region when it has none). Word and ODT keep
/// their text, headings and simple tables; AppKit's reader leaves pictures out (ADR-0038).
@MainActor
enum DocumentConversion {
    static func convert(_ url: URL, kind: ConvertKind, to format: ConvertFormat, output: URL) throws {
        let (text, attributes) = try read(url, kind: kind)
        switch format {
        case .text:
            try write(Data(text.string.utf8), to: output)
        case .rtf:
            let range = NSRange(location: 0, length: text.length)
            guard let data = try? text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) else {
                throw ConvertFailure.failed
            }
            try write(data, to: output)
        case .pdf:
            try writePDF(text, attributes: attributes, to: output)
        default:
            throw ConvertFailure.unsupported
        }
    }

    private static func write(_ data: Data, to output: URL) throws {
        do { try data.write(to: output) } catch { throw ConvertFailure.cantWrite }
    }

    static func read(_ url: URL, kind: ConvertKind) throws -> (NSAttributedString, [NSAttributedString.DocumentAttributeKey: Any]) {
        if kind == .plainText {
            var encoding = String.Encoding.utf8
            guard let string = (try? String(contentsOf: url, usedEncoding: &encoding)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
                throw ConvertFailure.unreadable
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]
            return (NSAttributedString(string: string, attributes: attributes), [:])
        }
        let type: NSAttributedString.DocumentType
        switch url.pathExtension.lowercased() {
        case "rtf": type = .rtf
        case "rtfd": type = .rtfd
        case "doc": type = .docFormat
        case "docx": type = .officeOpenXML
        case "odt": type = .openDocument
        default: throw ConvertFailure.unsupported
        }
        var attributes: NSDictionary?
        guard let text = try? NSAttributedString(url: url, options: [.documentType: type], documentAttributes: &attributes) else {
            throw ConvertFailure.unreadable
        }
        var keyed: [NSAttributedString.DocumentAttributeKey: Any] = [:]
        attributes?.forEach { key, value in
            if let key = key as? String { keyed[NSAttributedString.DocumentAttributeKey(rawValue: key)] = value }
        }
        return (text, keyed)
    }

    /// Paper size and margins: the document's own, else A4 (metric regions) or Letter, with 1-inch margins.
    static func page(for attributes: [NSAttributedString.DocumentAttributeKey: Any]) -> (size: CGSize, margins: NSEdgeInsets) {
        let fallback = Locale.current.measurementSystem == .us ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842)
        var size = (attributes[.paperSize] as? NSValue)?.sizeValue ?? fallback
        if size.width < 144 || size.height < 144 { size = fallback }
        func margin(_ key: NSAttributedString.DocumentAttributeKey) -> CGFloat {
            let value = (attributes[key] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 72
            return min(max(value, 18), size.width / 4)
        }
        return (size, NSEdgeInsets(top: margin(.topMargin), left: margin(.leftMargin), bottom: margin(.bottomMargin), right: margin(.rightMargin)))
    }

    /// Lays the text out on pages and draws them into a PDF.
    static func writePDF(_ text: NSAttributedString, attributes: [NSAttributedString.DocumentAttributeKey: Any], to output: URL) throws {
        let (size, margins) = page(for: attributes)
        let content = CGSize(width: size.width - margins.left - margins.right, height: size.height - margins.top - margins.bottom)
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        // One container per page until all the text is placed (a piece too big for a page ends it).
        var containers: [NSTextContainer] = []
        repeat {
            let container = NSTextContainer(size: content)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
            let range = layout.glyphRange(for: container)
            if range.length == 0, containers.count > 1 { break }
        } while NSMaxRange(layout.glyphRange(for: containers[containers.count - 1])) < layout.numberOfGlyphs && containers.count < 5000

        var media = CGRect(origin: .zero, size: size)
        guard let context = CGContext(output as CFURL, mediaBox: &media, nil) else { throw ConvertFailure.cantWrite }
        // Light appearance: text without its own colour draws black, also when the Mac is in Dark Mode.
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            let graphics = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            for container in containers {
                let range = layout.glyphRange(for: container)
                guard range.length > 0 || containers.count == 1 else { continue }
                context.beginPDFPage(nil)
                context.saveGState()
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                let origin = CGPoint(x: margins.left, y: margins.top)
                layout.drawBackground(forGlyphRange: range, at: origin)
                layout.drawGlyphs(forGlyphRange: range, at: origin)
                context.restoreGState()
                context.endPDFPage()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        context.closePDF()
    }

    /// Whether a Word or ODT file holds pictures (their names sit unpacked in the file's zip index).
    /// Old .doc files are checked for picture data (PNG or JPEG).
    nonisolated static func hasPictures(_ url: URL) -> Bool? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        let markers: [[UInt8]]
        switch url.pathExtension.lowercased() {
        case "docx": markers = [Array("word/media/".utf8)]
        case "odt": markers = [Array("Pictures/".utf8)]
        case "doc": markers = [[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], [0xFF, 0xD8, 0xFF]]
        default: return nil
        }
        return markers.contains { data.range(of: Data($0)) != nil }
    }
}
