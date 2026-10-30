import ConvertKit
import Foundation

/// Runs Convert's work (ADR-0038). The app only ever talks to this; the real one starts the
/// `pancakenotch-convert` helper, and tests use a fake.
protocol ShelfConvertRunning: Sendable {
    /// What each file is (sizes, pages, length), in order.
    func probe(_ files: [URL]) async throws -> [ConvertFileInfo]
    /// Runs one conversion; `progress` hears 0…1. Cancelling the task stops it.
    func convert(_ request: ConvertRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> ConvertMessage
}

/// The `pancakenotch-convert` helper: one process per job, gone when the job ends, so the media
/// frameworks never load into the app and their memory goes with the helper.
struct ShelfConvertHelper: ShelfConvertRunning {
    let executable: URL

    /// Beside the app's own executable (Contents/MacOS in the app, the build folder when developing).
    static var bundled: ShelfConvertHelper? {
        guard let url = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "pancakenotch-convert"),
              FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return ShelfConvertHelper(executable: url)
    }

    func probe(_ files: [URL]) async throws -> [ConvertFileInfo] {
        let job = try Job(executable, arguments: ["probe"] + files.map(\.path), timeout: 5 + Double(files.count))
        var infos: [ConvertFileInfo]?
        for try await line in job.lines {
            infos = try? JSONDecoder().decode([ConvertFileInfo].self, from: Data(line.utf8))
        }
        _ = await job.exitStatus()
        guard let infos, infos.count == files.count else { throw ConvertFailure.failed }
        return infos
    }

    func convert(_ request: ConvertRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> ConvertMessage {
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let job = try Job(executable, arguments: ["convert", json])
        var result: ConvertMessage?
        for try await line in job.lines {
            guard let message = try? JSONDecoder().decode(ConvertMessage.self, from: Data(line.utf8)) else { continue }
            if message.isFinal {
                result = message
            } else if let value = message.progress {
                progress(value)
            }
        }
        _ = await job.exitStatus()
        try Task.checkCancellation()
        // No final line: the helper crashed (or was stopped by the system).
        guard let result else { throw ConvertFailure.failed }
        return result
    }

    /// A running helper: its output line by line, and its exit. Cancelling the task that reads the
    /// lines stops the helper.
    private final class Job: @unchecked Sendable {
        private let process = Process()
        private let output = Pipe()
        private let exit: AsyncStream<Int32>
        private var watchdog: Task<Void, Never>?

        init(_ executable: URL, arguments: [String], timeout: Double? = nil) throws {
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            // The heavy lifting stays out of the way of what the user is doing.
            process.qualityOfService = .utility
            let process = process
            exit = AsyncStream { continuation in
                process.terminationHandler = { finished in
                    continuation.yield(finished.terminationStatus)
                    continuation.finish()
                }
            }
            try process.run()
            if let timeout {
                // A framework probe may block on a damaged file; kill the disposable helper too.
                watchdog = Task.detached {
                    try? await Task.sleep(for: .seconds(timeout))
                    guard !Task.isCancelled, process.isRunning else { return }
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }

        var lines: AsyncThrowingStream<String, any Error> {
            let handle = output.fileHandleForReading
            let process = process
            return AsyncThrowingStream { continuation in
                let reader = Task {
                    do {
                        for try await line in handle.bytes.lines { continuation.yield(line) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { reason in
                    reader.cancel()
                    if case .cancelled = reason, process.isRunning { process.terminate() }
                }
            }
        }

        func exitStatus() async -> Int32 {
            for await status in exit { return status }
            return -1
        }

        deinit {
            watchdog?.cancel()
            if process.isRunning { process.terminate() }
        }
    }
}
