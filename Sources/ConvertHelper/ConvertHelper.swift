import ConvertEngine
import ConvertKit
import Foundation

/// `pancakenotch-convert`, the Shelf's conversion helper (ADR-0038). The app starts it for one job and
/// it's gone when the job ends, so the media frameworks never load into the app.
///
///     pancakenotch-convert probe <file>…         one JSON array of `ConvertFileInfo`
///     pancakenotch-convert convert '<request>'   JSON lines of `ConvertMessage`: progress, then the results
///     pancakenotch-convert estimate '<request>'  the peak the row expects, in MiB (scripts/check-convert-memory.sh)
@main
struct ConvertHelper {
    @MainActor
    static func main() async {
        // Darwin's RLIMIT_AS/RLIMIT_RSS limits virtual address space, not physical footprint;
        // media frameworks reserve far more than their resident bytes. Bound inputs instead.
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "probe" where arguments.count > 1:
            var infos: [ConvertFileInfo] = []
            for path in arguments.dropFirst() {
                infos.append(await ConvertProbe.info(for: URL(fileURLWithPath: path)))
            }
            Output.shared.write(infos)
        case "convert" where arguments.count == 2:
            guard let request = try? JSONDecoder().decode(ConvertRequest.self, from: Data(arguments[1].utf8)) else {
                FileHandle.standardError.write(Data("Not a convert request.\n".utf8))
                exit(2)
            }
            let message = await ConvertEngine.run(request) { Output.shared.progress($0) }
            Output.shared.write(message)
        case "estimate" where arguments.count == 2:
            guard let request = try? JSONDecoder().decode(ConvertRequest.self, from: Data(arguments[1].utf8)) else {
                FileHandle.standardError.write(Data("Not a convert request.\n".utf8))
                exit(2)
            }
            var infos: [ConvertFileInfo] = []
            for path in request.sources {
                infos.append(await ConvertProbe.info(for: URL(fileURLWithPath: path)))
            }
            let peak = request.format.combinesSources
                ? ConvertLimits.combinedPeak(of: infos, quality: request.quality)
                : infos.compactMap {
                    ConvertLimits.estimatedPeak(of: request.format, from: $0, quality: request.quality, passesThrough: $0.passesThroughToPDF)
                }.max()
            Output.shared.write(Estimate(peak: peak, budget: ConvertLimits.helperBudget))
        default:
            FileHandle.standardError.write(Data("Usage: pancakenotch-convert probe <file>… | convert '<request JSON>' | estimate '<request JSON>'\n".utf8))
            exit(2)
        }
    }
}

/// What a request is expected to cost: nil when its size doesn't matter (it streams).
private struct Estimate: Encodable {
    var peak: Double?
    var budget: Double
}

/// Lines on standard output, from any thread. Progress is sent in steps of 1% at most.
private final class Output: @unchecked Sendable {
    static let shared = Output()
    private let lock = NSLock()
    private var lastProgress = -1.0

    func progress(_ value: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard value >= lastProgress + 0.01 else { return }
        lastProgress = value
        line(ConvertMessage(progress: min(1, value)))
    }

    func write(_ value: some Encodable) {
        lock.lock()
        defer { lock.unlock() }
        line(value)
    }

    private func line(_ value: some Encodable) {
        guard var data = try? JSONEncoder().encode(value) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
