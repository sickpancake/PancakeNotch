import Foundation

/// What a file can be turned into (ADR-0038).
public enum ConvertFormat: String, Codable, CaseIterable, Sendable {
    // Pictures.
    case jpeg, png, heic, tiff, pdf
    /// A PDF's pages as pictures: one picture, or a folder of them when there are several pages.
    case pagePNG, pageJPEG
    /// Plain text out of a PDF or a document.
    case text
    case rtf
    // Audio.
    case m4a, appleLossless, wav, aiff
    /// Video repackaged without re-encoding.
    case mp4, mov
    /// A video's sound as M4A.
    case audioOnly
    /// A short clip as an animated GIF.
    case gif
    /// Several pictures and PDFs as one PDF.
    case combinedPDF

    /// The short name drawn on the format's tile.
    public var badge: String {
        switch self {
        case .jpeg, .pageJPEG: "JPEG"
        case .png, .pagePNG: "PNG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        case .pdf, .combinedPDF: "PDF"
        case .text: "TXT"
        case .rtf: "RTF"
        case .m4a, .audioOnly: "M4A"
        case .appleLossless: "ALAC"
        case .wav: "WAV"
        case .aiff: "AIFF"
        case .mp4: "MP4"
        case .mov: "MOV"
        case .gif: "GIF"
        }
    }

    /// The name under the tile.
    public var title: String {
        switch self {
        case .pagePNG: String(localized: "PNG pictures", comment: "Convert: a PDF's pages as PNG pictures")
        case .pageJPEG: String(localized: "JPEG pictures", comment: "Convert: a PDF's pages as JPEG pictures")
        case .text: String(localized: "Plain text", comment: "Convert format")
        case .rtf: String(localized: "Rich text", comment: "Convert format")
        case .appleLossless: String(localized: "Apple Lossless", comment: "Convert format")
        case .audioOnly: String(localized: "Audio only", comment: "Convert: keep only a video's sound")
        case .combinedPDF: String(localized: "Combine into one PDF", comment: "Convert: several files into one PDF")
        default: badge
        }
    }

    /// The SF Symbol above the badge.
    public var symbol: String {
        switch self {
        case .jpeg, .png, .heic, .tiff, .pagePNG, .pageJPEG: "photo"
        case .pdf, .text, .rtf: "doc.text"
        case .m4a, .appleLossless, .wav, .aiff, .audioOnly: "waveform"
        case .mp4, .mov: "film"
        case .gif: "play.rectangle"
        case .combinedPDF: "doc.on.doc"
        }
    }

    /// The new file's extension.
    public var fileExtension: String {
        switch self {
        case .jpeg, .pageJPEG: "jpg"
        case .png, .pagePNG: "png"
        case .heic: "heic"
        case .tiff: "tiff"
        case .pdf, .combinedPDF: "pdf"
        case .text: "txt"
        case .rtf: "rtf"
        case .m4a, .appleLossless, .audioOnly: "m4a"
        case .wav: "wav"
        case .aiff: "aiff"
        case .mp4: "mp4"
        case .mov: "mov"
        case .gif: "gif"
        }
    }

    /// Several sources make one file instead of one each.
    public var combinesSources: Bool { self == .combinedPDF }
}

/// The Quality setting: one choice for every kind of file (ADR-0038).
public enum ConvertQuality: String, Codable, CaseIterable, Sendable {
    case best, balanced, smaller

    /// Its name in the Shelf's settings and the Convert footer.
    public var title: String {
        switch self {
        case .best: String(localized: "Best", comment: "Convert quality: largest files")
        case .balanced: String(localized: "Balanced", comment: "Convert quality: the default")
        case .smaller: String(localized: "Smaller file", comment: "Convert quality: shrinks big pictures, more compression")
        }
    }

    /// JPEG and HEIC compression (1 is best).
    public var lossyQuality: Double {
        switch self {
        case .best: 0.92
        case .balanced: 0.8
        case .smaller: 0.6
        }
    }

    /// Pictures are shrunk to this many pixels on their long side; `nil` keeps their size.
    public var maxPixelSize: Int? { self == .smaller ? 2000 : nil }

    /// AAC bit rate for stereo; mono gets half.
    public var stereoBitRate: Int {
        switch self {
        case .best: 256_000
        case .balanced: 192_000
        case .smaller: 128_000
        }
    }

    /// A GIF's long side in pixels.
    public var gifSize: Int {
        switch self {
        case .best: 640
        case .balanced: 480
        case .smaller: 320
        }
    }

    /// PDF pages drawn as pictures at this many pixels per point (2 = 144 dpi).
    public var pageScale: Double {
        switch self {
        case .best: 3
        case .balanced: 2
        case .smaller: 1
        }
    }
}
