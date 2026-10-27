import Foundation
import UniformTypeIdentifiers

/// The kinds of file Convert takes, told apart by extension only (no disk access, so it works while a
/// file is still being dragged).
public enum ConvertKind: String, Codable, Sendable {
    case image, pdf, audio, video, plainText, richText, wordDocument

    private static let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "aifc", "flac", "caf"]
    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
    private static let richTextExtensions: Set<String> = ["rtf", "rtfd"]
    private static let wordExtensions: Set<String> = ["doc", "docx", "odt"]

    public init?(url: URL) {
        let ext = url.pathExtension.lowercased()
        if Self.audioExtensions.contains(ext) { self = .audio; return }
        if Self.videoExtensions.contains(ext) { self = .video; return }
        if Self.richTextExtensions.contains(ext) { self = .richText; return }
        if Self.wordExtensions.contains(ext) { self = .wordDocument; return }
        guard let type = UTType(filenameExtension: ext) else { return nil }
        if type.conforms(to: .pdf) {
            self = .pdf
        } else if type.conforms(to: .image), !type.conforms(to: .rawImage), !type.conforms(to: .svg) {
            // Camera RAW decoding is too heavy for the memory budget; SVG isn't read on every macOS.
            self = .image
        } else if type.conforms(to: .plainText) {
            self = .plainText
        } else {
            return nil
        }
    }
}

/// Why a format is dimmed, or a warning that still lets it run.
public enum ConvertNote: String, Codable, Sendable {
    /// Over the memory budget for this file (ADR-0006).
    case tooBig
    /// A GIF from a clip longer than 15 seconds.
    case tooLong
    /// The video's codec can't go into the other container without re-encoding.
    case cantRepackage
    /// "Audio only" for a video without sound.
    case noSound
    /// A PDF that needs a password.
    case locked
    /// The file couldn't be read.
    case unreadable
    /// Word → PDF (experimental): runs, but the pictures are left out.
    case picturesNotKept

    /// Whether the format can still be picked.
    public var allowsConverting: Bool { self == .picturesNotKept }

    public var text: String {
        switch self {
        case .tooBig: String(localized: "Too big", comment: "Convert: the file is too big for this format")
        case .tooLong: String(localized: "Too long", comment: "Convert: the clip is too long for a GIF")
        case .cantRepackage: String(localized: "Can't repackage", comment: "Convert: the video can't change container")
        case .noSound: String(localized: "No sound", comment: "Convert: the video has no audio")
        case .locked: String(localized: "Locked", comment: "Convert: the PDF needs a password")
        case .unreadable: String(localized: "Can't read", comment: "Convert: the file couldn't be read")
        case .picturesNotKept: String(localized: "Pictures won't be kept", comment: "Convert: Word to PDF leaves pictures out")
        }
    }
}

/// What the helper found out about a file before converting (sizes, pages, length).
public struct ConvertFileInfo: Codable, Equatable, Sendable {
    public var kind: ConvertKind?
    public var isReadable: Bool
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var hasAlpha: Bool?
    public var pageCount: Int?
    public var isLocked: Bool?
    public var duration: Double?
    public var videoWidth: Int?
    public var videoHeight: Int?
    public var hasAudio: Bool?
    /// The containers the video goes into without re-encoding.
    public var repackages: [ConvertFormat]?
    /// A Word or ODT file that holds pictures.
    public var hasPictures: Bool?
    /// A picture's file type as ImageIO reads it (`public.jpeg`, `public.heic`…).
    public var imageType: String?
    /// A picture stored as print colours (CMYK), which has to be decoded to go into a PDF.
    public var isCMYK: Bool?
    /// The biggest picture inside a PDF, decoded, in bytes (grey pictures take a quarter of colour ones).
    public var largestPictureBytes: Int?
    /// A PDF's biggest page, in square points.
    public var largestPageArea: Double?

    public init(
        kind: ConvertKind?, isReadable: Bool = true, pixelWidth: Int? = nil, pixelHeight: Int? = nil,
        hasAlpha: Bool? = nil, pageCount: Int? = nil, isLocked: Bool? = nil, duration: Double? = nil,
        videoWidth: Int? = nil, videoHeight: Int? = nil, hasAudio: Bool? = nil, repackages: [ConvertFormat]? = nil,
        hasPictures: Bool? = nil, imageType: String? = nil, isCMYK: Bool? = nil, largestPictureBytes: Int? = nil,
        largestPageArea: Double? = nil
    ) {
        self.kind = kind
        self.isReadable = isReadable
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.hasAlpha = hasAlpha
        self.pageCount = pageCount
        self.isLocked = isLocked
        self.duration = duration
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.hasAudio = hasAudio
        self.repackages = repackages
        self.hasPictures = hasPictures
        self.imageType = imageType
        self.isCMYK = isCMYK
        self.largestPictureBytes = largestPictureBytes
        self.largestPageArea = largestPageArea
    }

    var pixelCount: Int { (pixelWidth ?? 0) * (pixelHeight ?? 0) }

    /// How the picture decodes, which decides what converting it costs.
    var family: PictureFamily {
        switch imageType {
        case "public.jpeg": .jpeg
        case "public.heic", "public.heif", "public.heics", "public.avif": .heif
        default: .other
        }
    }

    /// A picture that goes into a PDF as JPEG data without being decoded: a JPEG or HEIF photo
    /// without transparency or print colours.
    public var passesThroughToPDF: Bool {
        kind == .image && family != .other && hasAlpha != true && isCMYK != true
    }
}

/// Picture formats by what decoding them costs: JPEG and HEIF stream through ImageIO, the rest
/// (PNG, TIFF, GIF…) are read whole.
enum PictureFamily {
    case jpeg, heif, other
}

/// One tile in the format row.
public struct ConvertOption: Equatable, Sendable, Identifiable {
    public var format: ConvertFormat
    public var note: ConvertNote?

    public var id: ConvertFormat { format }
    public var isAvailable: Bool { note?.allowsConverting ?? true }

    public init(format: ConvertFormat, note: ConvertNote? = nil) {
        self.format = format
        self.note = note
    }
}

/// How much a conversion may hold so the app plus the helper stay under 100 MB (ADR-0006, ADR-0038).
/// Set from measuring the helper (`scripts/check-convert-memory.sh` checks the estimates stay above
/// what it measures), not from guesses.
public enum ConvertLimits {
    /// The helper's share of the peak, in MiB: the app is about 20 MiB with the Shelf open.
    public static let helperBudget = 65.0
    /// A PDF page drawn as a picture holds at most this many pixels (a poster-sized page is drawn smaller).
    public static let maxPagePixels = 8_000_000.0
    /// A GIF's clip: at most this long…
    public static let gifSeconds = 15.0
    /// …from a video at most this big (1080p either way up).
    public static let gifVideoLongSide = 1920
    public static let gifVideoShortSide = 1080

    /// The helper's peak in MiB for turning this file into `format`, or nil where the size doesn't matter
    /// (audio, video and text stream). `passesThrough`: whether a PDF of pictures is written without
    /// decoding them (every picture going in passes through).
    public static func estimatedPeak(of format: ConvertFormat, from info: ConvertFileInfo, quality: ConvertQuality, passesThrough: Bool) -> Double? {
        switch info.kind {
        case .image:
            return picturePeak(of: format, from: info, quality: quality, passesThrough: passesThrough)
        case .pdf:
            // macOS decodes each picture on a page it draws, colour ones at about 2 bytes per byte.
            let pictures = 2.1 * Double(info.largestPictureBytes ?? 0) / 1_048_576
            switch format {
            case .pagePNG, .pageJPEG:
                let area = (info.largestPageArea ?? .infinity) * quality.pageScale * quality.pageScale
                return 12 + 10 * min(maxPagePixels, area) / 1_000_000 + pictures
            case .combinedPDF:
                return 11 + pictures
            default:
                return nil
            }
        default:
            return nil
        }
    }

    /// The helper's peak for Combine. Files go in one after another, but each kind of decoder keeps its
    /// memory once used, so the heaviest file of each kind adds up (less the helper's own few MiB, counted once).
    public static func combinedPeak(of infos: [ConvertFileInfo], quality: ConvertQuality) -> Double {
        let passesThrough = ConvertCatalog.picturesPassThrough(infos)
        var heaviest: [String: Double] = [:]
        for info in infos {
            let kind = info.kind == .pdf ? "pdf" : "\(info.family)"
            let peak = estimatedPeak(of: .combinedPDF, from: info, quality: quality, passesThrough: passesThrough) ?? 0
            heaviest[kind] = max(heaviest[kind] ?? 0, peak)
        }
        return heaviest.values.reduce(0, +) - 5 * Double(max(0, heaviest.count - 1))
    }

    private static func picturePeak(of format: ConvertFormat, from info: ConvertFileInfo, quality: ConvertQuality, passesThrough: Bool) -> Double? {
        let source = Double(info.pixelCount) / 1_000_000
        let longSide = Double(max(info.pixelWidth ?? 0, info.pixelHeight ?? 0))
        let shrinkSide = quality.maxPixelSize.map(Double.init).flatMap { longSide > $0 ? $0 : nil }
        let shrinks = shrinkSide != nil
        let output = shrinkSide.map { source * ($0 / longSide) * ($0 / longSide) } ?? source
        // A JPEG decodes at a half, quarter or eighth of its size for free, so shrinking one decodes it at
        // the smallest of those still bigger than the result.
        var jpegScale = 1.0
        if let shrinkSide {
            while longSide * jpegScale / 2 >= shrinkSide, jpegScale > 1.0 / 8 { jpegScale /= 2 }
        }
        let jpegDecoded = source * jpegScale * jpegScale
        let family = info.family
        let flattens = info.hasAlpha == true || info.isCMYK == true

        // MiB, fitted to the helper's peak on each path (with room above it):
        // ImageIO re-encoding straight from the file…
        let streamed: Double = switch family {
        case .jpeg: shrinks ? 24 + 2 * jpegDecoded : 16 + 0.45 * source
        case .heif: shrinks ? 21 + 0.4 * source : 12 + 1.3 * source
        case .other: shrinks ? 10 + 8 * source : 5 + 6.5 * source
        }
        // …decoding it whole for an encoder that needs every pixel (PNG, TIFF)…
        let decoded: Double = switch family {
        case .jpeg: shrinks ? 17 + 9.5 * jpegDecoded + 0.6 * source : 5 + 9.6 * source
        case .heif: shrinks ? max(48 + 0.5 * source, 36 + source) : 20 + 11.5 * output
        case .other: 5 + 10 * output + (shrinks ? 7 * source : 0)
        }
        // …and drawing it onto white first.
        let flattened = 5 + 12 * output + (shrinks ? 7 * source : 0)
        switch format {
        case .jpeg:
            return flattens ? max(flattened, decoded) : streamed
        case .heic:
            if flattens { return 8 + 20 * output + (shrinks ? 2 * source : 0) }
            switch family {
            case .jpeg: return shrinks ? decoded : max(28 + 1.7 * source, 8 + 3.6 * source)
            case .heif, .other: return 8 + 15.5 * output + (shrinks ? 2 * source : 0)
            }
        case .png, .tiff:
            return decoded
        case .pdf, .combinedPDF:
            if passesThrough { return family == .jpeg && !shrinks ? 10 : streamed }
            // macOS's PDF writer decodes every picture it's given: a photo goes in as JPEG, anything
            // else as it is.
            if flattens { return 11 + 12.5 * output + (shrinks ? 7 * source : 0) }
            if family == .other { return 11 + 10.5 * output + (shrinks ? 4 * source : 0) }
            return max(streamed, 11 + 8.5 * output)
        default:
            return nil
        }
    }
}

/// Which formats a set of files can become (ADR-0038).
public enum ConvertCatalog {
    /// The formats for one kind of file, most common first, leaving out the one it already is.
    public static func formats(for kind: ConvertKind, url: URL, wordToPDF: Bool) -> [ConvertFormat] {
        let ext = url.pathExtension.lowercased()
        switch kind {
        case .image:
            let own: ConvertFormat? = switch ext {
            case "jpg", "jpeg": .jpeg
            case "png": .png
            case "heic", "heif": .heic
            case "tif", "tiff": .tiff
            default: nil
            }
            return [.jpeg, .png, .heic, .tiff, .pdf].filter { $0 != own }
        case .pdf:
            return [.pagePNG, .pageJPEG, .text]
        case .audio:
            let own: ConvertFormat? = switch ext {
            case "m4a", "m4b", "aac": .m4a
            case "wav": .wav
            case "aif", "aiff", "aifc": .aiff
            default: nil
            }
            return [.m4a, .appleLossless, .wav, .aiff].filter { $0 != own }
        case .video:
            let containers: [ConvertFormat] = switch ext {
            case "mov": [.mp4]
            case "mp4": [.mov]
            default: [.mp4, .mov]
            }
            return containers + [.audioOnly, .gif]
        case .plainText:
            return [.pdf, .rtf]
        case .richText:
            return [.pdf, .text]
        case .wordDocument:
            return wordToPDF ? [.pdf, .text] : [.text]
        }
    }

    /// The formats every one of `urls` can become; several pictures and PDFs also get "Combine".
    /// Empty when nothing fits (unknown kinds, or files with nothing in common).
    public static func formats(for urls: [URL], wordToPDF: Bool) -> [ConvertFormat] {
        let kinds = urls.map(ConvertKind.init(url:))
        guard !urls.isEmpty, !kinds.contains(nil) else { return [] }
        var shared: [ConvertFormat]?
        for (url, kind) in zip(urls, kinds.compactMap { $0 }) {
            let formats = formats(for: kind, url: url, wordToPDF: wordToPDF)
            shared = shared.map { $0.filter(formats.contains) } ?? formats
        }
        let combines = urls.count > 1 && kinds.allSatisfy { $0 == .image || $0 == .pdf }
        return (combines ? [.combinedPDF] : []) + (shared ?? [])
    }

    /// The tiles for files the helper has looked at: each format, with a note when it doesn't fit.
    public static func options(for urls: [URL], infos: [ConvertFileInfo], wordToPDF: Bool, quality: ConvertQuality) -> [ConvertOption] {
        formats(for: urls, wordToPDF: wordToPDF).map { format in
            var notes = infos.compactMap { note(for: format, info: $0, quality: quality) }
            if format == .combinedPDF, let note = combineNote(for: infos, quality: quality) { notes.append(note) }
            // A blocking note wins over a warning.
            return ConvertOption(format: format, note: notes.first { !$0.allowsConverting } ?? notes.first)
        }
    }

    /// Whether one PDF of these files can be written without decoding the pictures: only when every
    /// one is a picture that passes through (a PDF among them goes through macOS's PDF writer).
    public static func picturesPassThrough(_ infos: [ConvertFileInfo]) -> Bool {
        !infos.isEmpty && infos.allSatisfy(\.passesThroughToPDF)
    }

    /// Combine's size check, made over all the files at once (`note` leaves it out).
    public static func combineNote(for infos: [ConvertFileInfo], quality: ConvertQuality) -> ConvertNote? {
        ConvertLimits.combinedPeak(of: infos, quality: quality) > ConvertLimits.helperBudget ? .tooBig : nil
    }

    /// Why `format` doesn't fit this file, if it doesn't (or a warning that still lets it run). For
    /// Combine, the size is checked over all the files by `combineNote`.
    public static func note(for format: ConvertFormat, info: ConvertFileInfo, quality: ConvertQuality) -> ConvertNote? {
        guard info.isReadable else { return .unreadable }
        let peak = format == .combinedPDF ? nil : ConvertLimits.estimatedPeak(
            of: format, from: info, quality: quality, passesThrough: info.passesThroughToPDF
        )
        let tooBig = (peak ?? 0) > ConvertLimits.helperBudget
        switch info.kind {
        case .image:
            return tooBig ? .tooBig : nil
        case .pdf:
            if info.isLocked == true { return .locked }
            return tooBig ? .tooBig : nil
        case .video:
            switch format {
            case .mp4, .mov:
                return info.repackages?.contains(format) == true ? nil : .cantRepackage
            case .audioOnly:
                return info.hasAudio == true ? nil : .noSound
            case .gif:
                if (info.duration ?? .infinity) > ConvertLimits.gifSeconds + 0.05 { return .tooLong }
                let long = max(info.videoWidth ?? .max, info.videoHeight ?? .max)
                let short = min(info.videoWidth ?? .max, info.videoHeight ?? .max)
                return long > ConvertLimits.gifVideoLongSide || short > ConvertLimits.gifVideoShortSide ? .tooBig : nil
            default:
                return nil
            }
        case .wordDocument:
            return format == .pdf && info.hasPictures == true ? .picturesNotKept : nil
        case .audio, .plainText, .richText, nil:
            return nil
        }
    }
}
