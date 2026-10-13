import AppKit
import ImageIO

/// Turns album art bytes (often several megabytes) into a small picture, so only a 256 px bitmap
/// stays in memory. Safe to call off the main thread.
enum ArtworkImage {
    static let maxPixelSize = 256

    static func downsample(_ data: Data) -> NSImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// A short ID that changes when the bytes change (only compared within one run of the app).
    static func id<T: Hashable>(for value: T, count: Int) -> String {
        var hasher = Hasher()
        hasher.combine(value)
        return "\(count)-\(String(UInt(bitPattern: hasher.finalize()), radix: 16))"
    }
}
