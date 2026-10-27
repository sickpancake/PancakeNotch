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
            try write(Data(plainText(text).utf8), to: output)
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
            guard let string = readText(url) else { throw ConvertFailure.unreadable }
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

    /// A plain text file in UTF-8 or UTF-16, else in the older encoding its bytes fit (Windows, Mac, Japanese,
    /// Chinese…), else Latin-1, which reads anything.
    static func readText(_ url: URL) -> String? {
        var encoding = String.Encoding.utf8
        if let string = try? String(contentsOf: url, usedEncoding: &encoding) { return string }
        guard let data = try? Data(contentsOf: url) else { return nil }
        func cf(_ encoding: CFStringEncodings) -> String.Encoding {
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
        }
        let suggested: [String.Encoding] = [.windowsCP1252, .shiftJIS, cf(.GB_18030_2000), cf(.big5), .japaneseEUC, cf(.EUC_KR), .macOSRoman]
        var converted: NSString?
        var lossy = ObjCBool(false)
        let found = NSString.stringEncoding(
            for: data,
            encodingOptions: [.suggestedEncodingsKey: suggested.map(\.rawValue), .useOnlySuggestedEncodingsKey: true, .allowLossyKey: false],
            convertedString: &converted, usedLossyConversion: &lossy
        )
        if found != 0, !lossy.boolValue, let converted { return converted as String }
        return String(data: data, encoding: .macOSRoman) ?? String(data: data, encoding: .isoLatin1)
    }

    /// The text as a .txt file shows it: table rows on one line with tabs between the cells, a link's
    /// address after its words, and no stand-ins for pictures or Word's line breaks.
    static func plainText(_ text: NSAttributedString) -> String {
        let withAddresses = NSMutableAttributedString(attributedString: text)
        var links: [(NSRange, String)] = []
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let address = (value as? URL)?.absoluteString ?? value as? String
            guard let address, !address.isEmpty else { return }
            let words = (text.string as NSString).substring(with: range)
            // A link that already reads as its address, or one within the document, adds nothing.
            var shown = address.replacingOccurrences(of: "mailto:", with: "")
            for prefix in ["https://", "http://"] where shown.hasPrefix(prefix) { shown.removeFirst(prefix.count) }
            if shown.hasSuffix("/") { shown.removeLast() }
            guard !address.hasPrefix("#"), !shown.isEmpty, !words.contains(shown) else { return }
            links.append((range, address.hasPrefix("mailto:") ? shown : address))
        }
        for (range, address) in links.reversed() {
            withAddresses.insert(NSAttributedString(string: " (\(address))"), at: NSMaxRange(range))
        }

        let string = withAddresses.string as NSString
        var result = ""
        var lastCell: NSTextTableBlock?
        var hasParagraph = false
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { paragraph, range, _, _ in
            let paragraph = paragraph ?? ""
            let style = withAddresses.length > 0
                ? withAddresses.attribute(.paragraphStyle, at: min(range.location, withAddresses.length - 1), effectiveRange: nil) as? NSParagraphStyle
                : nil
            let cell = style?.textBlocks.last as? NSTextTableBlock
            if let cell, let last = lastCell, cell.table === last.table {
                // Another paragraph of the same cell, the next cell of the row, or the next row.
                result += cell === last ? " " : cell.startingRow == last.startingRow ? "\t" : "\n"
            } else if hasParagraph {
                result += "\n"
            }
            result += paragraph
            lastCell = cell
            hasParagraph = true
        }
        if withAddresses.string.last?.isNewline == true { result += "\n" }
        return result.replacingOccurrences(of: "\u{FFFC}", with: "").replacingOccurrences(of: "\u{2028}", with: "\n")
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

        // Longer than that: refused, rather than leaving out the end.
        if containers.count >= 5000, NSMaxRange(layout.glyphRange(for: containers[containers.count - 1])) < layout.numberOfGlyphs {
            throw ConvertFailure.tooBig
        }

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
