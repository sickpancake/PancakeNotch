import ConvertKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pictures to JPEG, PNG, HEIC or TIFF with ImageIO. Re-encoding straight from the source keeps the
/// metadata (date, place, orientation) and lets ImageIO stream; only a transparent picture going to JPEG
/// is drawn onto white first.
enum ImageConversion {
    static func type(for format: ConvertFormat) -> UTType {
        switch format {
        case .png, .pagePNG: .png
        case .heic: .heic
        case .tiff: .tiff
        default: .jpeg
        }
    }

    static func convert(_ url: URL, to format: ConvertFormat, quality: ConvertQuality, output: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw ConvertFailure.unreadable
        }
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type(for: format).identifier as CFString, 1, nil) else {
            throw ConvertFailure.cantWrite
        }
        var options: [CFString: Any] = [:]
        if format == .jpeg || format == .heic { options[kCGImageDestinationLossyCompressionQuality] = quality.lossyQuality }
        let longSide = max(properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
        let shrinksTo = quality.maxPixelSize.flatMap { longSide > $0 ? $0 : nil }

        if format == .jpeg, properties[kCGImagePropertyHasAlpha] as? Bool == true {
            // JPEG has no transparency: what was see-through becomes white, not black.
            guard let image = decode(source, maxPixelSize: shrinksTo) else { throw ConvertFailure.unreadable }
            CGImageDestinationAddImage(destination, try flattened(image), options as CFDictionary)
        } else {
            if let shrinksTo { options[kCGImageDestinationImageMaxPixelSize] = shrinksTo }
            CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw ConvertFailure.cantWrite }
    }

    /// The picture upright (orientation applied), at most `maxPixelSize` on its long side.
    static func decode(_ source: CGImageSource, maxPixelSize: Int?) -> CGImage? {
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxPixelSize {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        } else if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            options[kCGImageSourceThumbnailMaxPixelSize] = max(
                properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            )
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The picture drawn on white, without an alpha channel.
    static func flattened(_ image: CGImage) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) ?? CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ConvertFailure.tooBig }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        guard let flat = context.makeImage() else { throw ConvertFailure.tooBig }
        return flat
    }

    /// The picture as a JPEG file, shrunk to `maxPixelSize` if given, keeping its orientation tag.
    static func writeJPEG(from source: CGImageSource, quality: ConvertQuality, maxPixelSize: Int?, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ConvertFailure.cantWrite
        }
        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality.lossyQuality]
        if let maxPixelSize { options[kCGImageDestinationImageMaxPixelSize] = maxPixelSize }
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConvertFailure.cantWrite }
    }

    /// The picture as JPEG data, shrunk to `maxPixelSize` if given, keeping its orientation tag.
    static func jpegData(from source: CGImageSource, quality: ConvertQuality, maxPixelSize: Int?) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality.lossyQuality]
        if let maxPixelSize { options[kCGImageDestinationImageMaxPixelSize] = maxPixelSize }
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
