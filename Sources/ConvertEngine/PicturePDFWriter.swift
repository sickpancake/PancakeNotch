import ConvertKit
import CoreGraphics
import Foundation
import ImageIO

/// A PDF of photos written by hand, each page one JPEG passed through as it is. macOS's own PDF writer
/// decodes every picture it's given (about 8 MB per megapixel, measured), so a few phone photos would
/// be far over the memory budget; here nothing is decoded (ADR-0038).
final class PicturePDFWriter {
    private let handle: FileHandle
    private var offset = 0
    /// Each object's place in the file, by number (1 is the catalogue, 2 the page list, written last).
    private var objects: [Int] = [0, 0, 0]
    private var pages: [Int] = []

    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { throw ConvertFailure.cantWrite }
        self.handle = handle
        // The second line's high bytes tell tools the file is binary.
        try write(Data("%PDF-1.4\n%".utf8) + Data([0xE2, 0xE3, 0xCF, 0xD3, 0x0A]))
        objects[1] = offset
        try write("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
    }

    deinit { try? handle.close() }

    /// One page holding a JPEG (RGB or grey) stored turned by `orientation`, `size` points once upright.
    func addPage(jpeg: Data, orientation: CGImagePropertyOrientation, size: CGSize) throws {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ConvertFailure.unreadable
        }
        let model = properties[kCGImagePropertyColorModel] as? String
        guard model == kCGImagePropertyColorModelRGB as String || model == kCGImagePropertyColorModelGray as String else {
            throw ConvertFailure.unsupported
        }
        let components = model == kCGImagePropertyColorModelGray as String ? 1 : 3

        // The picture's colour profile goes along, so a Display P3 photo keeps its colours.
        var colourSpace = components == 1 ? "/DeviceGray" : "/DeviceRGB"
        if let profile = image.colorSpace?.copyICCData() as Data?, image.colorSpace?.numberOfComponents == components {
            let number = try begin()
            try write("\(number) 0 obj\n<< /N \(components) /Length \(profile.count) >>\nstream\n")
            try write(profile)
            try write("\nendstream\nendobj\n")
            colourSpace = "[/ICCBased \(number) 0 R]"
        }

        let picture = try begin()
        try write("""
            \(picture) 0 obj
            << /Type /XObject /Subtype /Image /Width \(width) /Height \(height) /ColorSpace \(colourSpace) \
            /BitsPerComponent 8 /Filter /DCTDecode /Length \(jpeg.count) >>
            stream

            """)
        try write(jpeg)
        try write("\nendstream\nendobj\n")

        // A picture fills a 1×1 square: stretch it to the page, turned upright.
        let turned = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
        let drawn = turned ? CGSize(width: size.height, height: size.width) : size
        let matrix = CGAffineTransform(scaleX: drawn.width, y: drawn.height)
            .concatenating(PDFConversion.orientationTransform(orientation, size: size))
        let drawing = "q \([matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty].map(Self.number).joined(separator: " ")) cm /P Do Q"
        let contents = try begin()
        try write("\(contents) 0 obj\n<< /Length \(drawing.utf8.count) >>\nstream\n\(drawing)\nendstream\nendobj\n")

        let page = try begin()
        try write("""
            \(page) 0 obj
            << /Type /Page /Parent 2 0 R /MediaBox [0 0 \(Self.number(size.width)) \(Self.number(size.height))] \
            /Resources << /XObject << /P \(picture) 0 R >> >> /Contents \(contents) 0 R >>
            endobj

            """)
        pages.append(page)
    }

    func finish() throws {
        objects[2] = offset
        try write("2 0 obj\n<< /Type /Pages /Kids [\(pages.map { "\($0) 0 R" }.joined(separator: " "))] /Count \(pages.count) >>\nendobj\n")
        let table = offset
        var xref = "xref\n0 \(objects.count)\n0000000000 65535 f \n"
        for place in objects.dropFirst() {
            xref += String(format: "%010d 00000 n \n", place)
        }
        xref += "trailer\n<< /Size \(objects.count) /Root 1 0 R >>\nstartxref\n\(table)\n%%EOF\n"
        try write(xref)
        try handle.close()
    }

    /// A new object starting here; its number.
    private func begin() throws -> Int {
        objects.append(offset)
        return objects.count - 1
    }

    private static func number(_ value: Double) -> String {
        // PDF has no exponents ("1e-05"), so a fixed number of places.
        let text = String(format: "%.4f", value)
        return text.contains(".") ? String(text.reversed().drop { $0 == "0" }.drop { $0 == "." }.reversed()) : text
    }

    private func write(_ text: String) throws { try write(Data(text.utf8)) }

    private func write(_ data: Data) throws {
        do { try handle.write(contentsOf: data) } catch { throw ConvertFailure.cantWrite }
        offset += data.count
    }
}
