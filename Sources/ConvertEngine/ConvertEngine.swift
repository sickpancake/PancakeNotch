import ConvertKit
import Foundation

/// Runs one request in `pancakenotch-convert`: each file in turn (or all at once for Combine), each into its
/// own subfolder of the output folder, so results with the same name can't clash. The app moves them out.
public enum ConvertEngine {
    /// Progress so far, 0…1.
    public typealias Progress = @Sendable (Double) -> Void

    @MainActor
    public static func run(_ request: ConvertRequest, progress: @escaping Progress) async -> ConvertMessage {
        let folder = URL(fileURLWithPath: request.outputFolder, isDirectory: true)
        let sources = request.sources.map { URL(fileURLWithPath: $0) }

        if request.format.combinesSources {
            do {
                var infos: [ConvertFileInfo] = []
                for source in sources { infos.append(await ConvertProbe.info(for: source)) }
                for info in infos { try check(info, for: request.format, quality: request.quality) }
                if !measuresEverything, ConvertCatalog.combineNote(for: infos, quality: request.quality) != nil { throw ConvertFailure.tooBig }
                let passesThrough = ConvertCatalog.picturesPassThrough(infos)
                let output = folder.appending(path: "Combined.pdf")
                try PDFConversion.combine(sources, passesThrough: passesThrough, quality: request.quality, into: output, progress: progress)
                return ConvertMessage(outputs: [ConvertOutput(source: nil, path: output.path)], errors: [])
            } catch {
                return ConvertMessage(outputs: [], errors: [ConvertError(source: nil, failure: failure(error))])
            }
        }

        var outputs: [ConvertOutput] = []
        var errors: [ConvertError] = []
        let share = 1 / Double(max(1, sources.count))
        for (index, source) in sources.enumerated() {
            let start = Double(index) * share
            do {
                let subfolder = folder.appending(path: String(index), directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
                let output = try await convert(
                    source, to: request.format, quality: request.quality, in: subfolder, pageName: request.pageName
                ) { progress(start + $0 * share) }
                outputs.append(ConvertOutput(source: index, path: output.path))
            } catch {
                errors.append(ConvertError(source: index, failure: failure(error)))
            }
            progress(start + share)
        }
        return ConvertMessage(outputs: outputs, errors: errors)
    }

    /// Set by scripts/check-convert-memory.sh to measure conversions the row would call too big.
    static let measuresEverything = ProcessInfo.processInfo.environment["PANCAKENOTCH_CONVERT_MEASURE_ALL"] == "1"

    /// The same check the row did, made again here: the file may have changed since.
    static func check(_ info: ConvertFileInfo, for format: ConvertFormat, quality: ConvertQuality) throws {
        if measuresEverything, info.isReadable { return }
        guard let note = ConvertCatalog.note(for: format, info: info, quality: quality),
              !note.allowsConverting else { return }
        switch note {
        case .tooBig, .tooLong: throw ConvertFailure.tooBig
        case .unreadable: throw ConvertFailure.unreadable
        default: throw ConvertFailure.unsupported
        }
    }

    @MainActor
    static func convert(
        _ source: URL, to format: ConvertFormat, quality: ConvertQuality, in folder: URL, pageName: String,
        progress: @escaping Progress
    ) async throws -> URL {
        guard let kind = ConvertKind(url: source) else { throw ConvertFailure.unsupported }
        let info = await ConvertProbe.info(for: source)
        try check(info, for: format, quality: quality)
        let base = source.deletingPathExtension().lastPathComponent
        let output = folder.appending(path: base + "." + format.fileExtension)
        switch (kind, format) {
        case (.image, .jpeg), (.image, .png), (.image, .heic), (.image, .tiff):
            try ImageConversion.convert(source, to: format, quality: quality, output: output)
        case (.image, .pdf):
            try PDFConversion.combine([source], passesThrough: info.passesThroughToPDF, quality: quality, into: output, progress: progress)
        case (.pdf, .pagePNG), (.pdf, .pageJPEG):
            return try PDFConversion.pages(of: source, as: format, quality: quality, in: folder, base: base, pageName: pageName, progress: progress)
        case (.pdf, .text):
            try PDFConversion.text(of: source, output: output, progress: progress)
        case (.audio, .m4a), (.audio, .appleLossless), (.audio, .wav), (.audio, .aiff), (.video, .audioOnly):
            try await AudioConversion.convert(source, to: format, quality: quality, output: output, progress: progress)
        case (.video, .mp4), (.video, .mov):
            try await VideoConversion.repackage(source, to: format, output: output, progress: progress)
        case (.video, .gif):
            try await VideoConversion.gif(source, quality: quality, output: output, progress: progress)
        case (.plainText, .pdf), (.plainText, .rtf), (.richText, .pdf), (.richText, .text), (.wordDocument, .pdf), (.wordDocument, .text):
            try DocumentConversion.convert(source, kind: kind, to: format, output: output)
        default:
            throw ConvertFailure.unsupported
        }
        return output
    }

    static func failure(_ error: any Error) -> ConvertFailure {
        error as? ConvertFailure ?? .failed
    }
}
