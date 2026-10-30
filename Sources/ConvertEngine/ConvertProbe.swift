import AVFoundation
import ConvertKit
import CoreGraphics
import Foundation
import Darwin
import ImageIO

/// Looks at a file before converting: picture size, page count, a clip's length and size. Reads headers
/// only (never decodes a whole picture or video).
public enum ConvertProbe {
    public static func info(for source: URL) async -> ConvertFileInfo {
        let url = source.resolvingSymlinksInPath()
        let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return ConvertFileInfo(kind: nil, isReadable: false) }
        defer { close(fd) }
        var file = stat()
        guard fstat(fd, &file) == 0, file.st_mode & S_IFMT == S_IFREG else { return ConvertFileInfo(kind: nil, isReadable: false) }
        guard let kind = ConvertKind(url: url) else { return ConvertFileInfo(kind: nil, isReadable: false) }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return ConvertFileInfo(kind: kind, isReadable: false) }
        switch kind {
        case .image: return image(url)
        case .pdf: return pdf(url)
        case .audio: return await audio(url)
        case .video: return await video(url)
        case .plainText, .richText, .wordDocument:
            do {
                let bytes = try DocumentInput.bytes(url, kind: kind)
                return ConvertFileInfo(kind: kind, hasPictures: kind == .wordDocument ? DocumentConversion.hasPictures(url) : nil, documentBytes: bytes)
            } catch ConvertFailure.tooBig {
                return ConvertFileInfo(kind: kind, documentBytes: .max)
            } catch {
                return ConvertFileInfo(kind: kind, isReadable: false)
            }
        }
    }

    static func image(_ url: URL) -> ConvertFileInfo {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return ConvertFileInfo(kind: .image, isReadable: false)
        }
        return ConvertFileInfo(
            kind: .image, pixelWidth: width, pixelHeight: height, hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool ?? false,
            imageType: CGImageSourceGetType(source) as String?,
            isCMYK: properties[kCGImagePropertyColorModel] as? String == kCGImagePropertyColorModelCMYK as String
        )
    }

    /// Pages, and the biggest page and picture in them (what drawing a page costs); a locked PDF isn't looked into.
    static func pdf(_ url: URL) -> ConvertFileInfo {
        guard let document = CGPDFDocument(url as CFURL) else { return ConvertFileInfo(kind: .pdf, isReadable: false) }
        let count = document.numberOfPages
        guard PDFConversion.unlock(document) else { return ConvertFileInfo(kind: .pdf, pageCount: count, isLocked: true) }
        var largestPicture = 0
        var largestPage = 0.0
        for number in stride(from: 1, through: count, by: 1) {
            autoreleasepool {
                guard let page = document.page(at: number) else { return }
                let box = page.getBoxRect(.cropBox).size
                largestPage = max(largestPage, abs(box.width * box.height))
                if let resources = PDFPictures.resources(of: page) {
                    largestPicture = max(largestPicture, PDFPictures.largestPictureBytes(in: resources))
                }
            }
        }
        return ConvertFileInfo(
            kind: .pdf, pageCount: count, isLocked: false, largestPictureBytes: largestPicture, largestPageArea: largestPage
        )
    }

    static func audio(_ url: URL) async -> ConvertFileInfo {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
              (try? await asset.load(.isReadable)) == true else {
            return ConvertFileInfo(kind: .audio, isReadable: false)
        }
        let duration = try? await asset.load(.duration)
        return ConvertFileInfo(kind: .audio, duration: duration.map(\.seconds), hasAudio: true)
    }

    static func video(_ url: URL) async -> ConvertFileInfo {
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isReadable)) == true,
              let video = try? await asset.loadTracks(withMediaType: .video).first else {
            return ConvertFileInfo(kind: .video, isReadable: false)
        }
        let duration = (try? await asset.load(.duration))?.seconds
        let size = (try? await video.load(.naturalSize)) ?? .zero
        let transform = (try? await video.load(.preferredTransform)) ?? .identity
        let upright = CGRect(origin: .zero, size: size).applying(transform).size
        let hasAudio = !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty
        var repackages: [ConvertFormat] = []
        for (format, type) in [(ConvertFormat.mp4, AVFileType.mp4), (.mov, .mov)] {
            if await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough, with: asset, outputFileType: type) {
                repackages.append(format)
            }
        }
        return ConvertFileInfo(
            kind: .video, duration: duration, videoWidth: Int(abs(upright.width).rounded()),
            videoHeight: Int(abs(upright.height).rounded()), hasAudio: hasAudio, repackages: repackages
        )
    }
}

/// The pictures a PDF page draws, read from its resources without decoding them.
enum PDFPictures {
    /// A page's resources, which it may take from the page list it's in.
    static func resources(of page: CGPDFPage) -> CGPDFDictionaryRef? {
        var node = page.dictionary
        for _ in 0..<32 {
            guard let current = node else { return nil }
            var resources: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(current, "Resources", &resources), let resources { return resources }
            var parent: CGPDFDictionaryRef?
            node = CGPDFDictionaryGetDictionary(current, "Parent", &parent) ? parent : nil
        }
        return nil
    }

    /// The biggest picture drawn from these resources (and forms inside them), in decoded bytes.
    static func largestPictureBytes(in resources: CGPDFDictionaryRef, depth: Int = 0) -> Int {
        var objects: CGPDFDictionaryRef?
        guard depth < 4, CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return 0 }
        let largest = Largest()
        CGPDFDictionaryApplyBlock(objects, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let info = CGPDFStreamGetDictionary(stream) else { return true }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(info, "Subtype", &subtype), let subtype else { return true }
            switch String(cString: subtype) {
            case "Image":
                var width: CGPDFInteger = 0, height: CGPDFInteger = 0
                guard CGPDFDictionaryGetInteger(info, "Width", &width), CGPDFDictionaryGetInteger(info, "Height", &height) else { return true }
                largest.bytes = max(largest.bytes, max(0, width) * max(0, height) * bytesPerPixel(info))
            case "Form":
                var inner: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(info, "Resources", &inner), let inner {
                    largest.bytes = max(largest.bytes, largestPictureBytes(in: inner, depth: depth + 1))
                }
            default:
                break
            }
            return true
        }, nil)
        return largest.bytes
    }

    private final class Largest { var bytes = 0 }

    /// Grey pictures (and black-and-white masks and scans) decode to a byte a pixel, the rest to four.
    private static func bytesPerPixel(_ info: CGPDFDictionaryRef) -> Int {
        var isMask: CGPDFBoolean = 0
        if CGPDFDictionaryGetBoolean(info, "ImageMask", &isMask), isMask != 0 { return 1 }
        var name: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(info, "ColorSpace", &name), let name {
            return ["DeviceGray", "CalGray", "G"].contains(String(cString: name)) ? 1 : 4
        }
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(info, "ColorSpace", &array), let array,
              CGPDFArrayGetName(array, 0, &name), let name else { return 4 }
        switch String(cString: name) {
        case "CalGray":
            return 1
        case "ICCBased":
            var profile: CGPDFStreamRef?
            var components: CGPDFInteger = 0
            guard CGPDFArrayGetStream(array, 1, &profile), let profile, let profileInfo = CGPDFStreamGetDictionary(profile),
                  CGPDFDictionaryGetInteger(profileInfo, "N", &components) else { return 4 }
            return components == 1 ? 1 : 4
        default:
            return 4
        }
    }
}
