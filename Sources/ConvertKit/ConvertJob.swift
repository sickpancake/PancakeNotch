import Foundation

/// What the app asks `pancakenotch-convert` to do: `convert '<request JSON>'`. The helper writes its
/// results into `outputFolder` and reports them as JSON lines on standard output (`ConvertMessage`).
public struct ConvertRequest: Codable, Equatable, Sendable {
    public var sources: [String]
    public var format: ConvertFormat
    public var quality: ConvertQuality
    /// An empty folder the app made; the app moves the results out of it.
    public var outputFolder: String
    /// The word before a page number in a folder of page pictures ("Page 01.png"), in the app's language.
    public var pageName: String

    public init(sources: [String], format: ConvertFormat, quality: ConvertQuality, outputFolder: String, pageName: String) {
        self.sources = sources
        self.format = format
        self.quality = quality
        self.outputFolder = outputFolder
        self.pageName = pageName
    }
}

/// One result: a file, or a folder of page pictures. `source` is the index of the file it came from,
/// `nil` for a combined PDF.
public struct ConvertOutput: Codable, Equatable, Sendable {
    public var source: Int?
    public var path: String

    public init(source: Int?, path: String) {
        self.source = source
        self.path = path
    }
}

/// Why a file wasn't converted.
public enum ConvertFailure: String, Codable, Error, Sendable {
    /// It couldn't be opened or decoded.
    case unreadable
    /// The new file couldn't be written.
    case cantWrite
    /// Over a limit after all (the size check is done again in the helper).
    case tooBig
    /// This file can't become that format (or a PDF needs a password).
    case unsupported
    /// A PDF with no text in it (scanned pages are pictures).
    case noText
    /// Anything else (a framework error).
    case failed

    public var message: String {
        switch self {
        case .unreadable: String(localized: "The file couldn't be read. It may be damaged, or in a format macOS can't open.")
        case .cantWrite: String(localized: "The new file couldn't be saved.")
        case .tooBig: String(localized: "The file is too big to convert without using too much memory.")
        case .unsupported: String(localized: "This file can't be converted to that format.")
        case .noText: String(localized: "This PDF has no text to copy. Its pages may be scanned pictures.")
        case .failed: String(localized: "macOS couldn't convert this file.")
        }
    }
}

/// A file the helper gave up on.
public struct ConvertError: Codable, Equatable, Sendable {
    public var source: Int?
    public var failure: ConvertFailure

    public init(source: Int?, failure: ConvertFailure) {
        self.source = source
        self.failure = failure
    }
}

/// One line from the helper: progress so far (0…1), or the end of the job.
public struct ConvertMessage: Codable, Equatable, Sendable {
    public var progress: Double?
    public var outputs: [ConvertOutput]?
    public var errors: [ConvertError]?

    public init(progress: Double? = nil, outputs: [ConvertOutput]? = nil, errors: [ConvertError]? = nil) {
        self.progress = progress
        self.outputs = outputs
        self.errors = errors
    }

    /// The last line of a job.
    public var isFinal: Bool { outputs != nil || errors != nil }
}

/// File names for results: never overwrite anything.
public enum ConvertNaming {
    /// `base.ext` in `folder`, or "base 2.ext", "base 3.ext"… when taken. `ext` nil names a folder.
    public static func uniqueURL(in folder: URL, base: String, ext: String?, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let safe = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let name = safe.isEmpty ? "Converted" : safe
        func url(_ candidate: String) -> URL {
            let file = ext.map { candidate + "." + $0 } ?? candidate
            return folder.appending(path: file, directoryHint: ext == nil ? .isDirectory : .notDirectory)
        }
        var candidate = url(name)
        var number = 2
        while exists(candidate) {
            candidate = url("\(name) \(number)")
            number += 1
        }
        return candidate
    }
}
