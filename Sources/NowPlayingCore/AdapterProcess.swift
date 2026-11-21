import AppKit
import os

/// Where the mediaremote-adapter files are: the Perl script and its framework.
struct AdapterLocation: Equatable, Sendable {
    static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    static let scriptName = "mediaremote-adapter.pl"
    static let frameworkName = "MediaRemoteAdapter.framework"

    var script: URL
    var framework: URL

    /// In the app: `Contents/Resources/mediaremote-adapter.pl` and
    /// `Contents/Frameworks/MediaRemoteAdapter.framework`. `PANCAKENOTCH_ADAPTER_DIR` (a folder holding
    /// both) wins, for runs from `.build`. nil when a file is missing.
    /// Perl gets only what it needs, so nothing in the app's environment (`PERL5OPT`, `PERL5LIB`,
    /// `DYLD_*`…) can make it run other code.
    static var perlEnvironment: [String: String] {
        let current = ProcessInfo.processInfo.environment
        var environment = ["PATH": "/usr/bin:/bin"]
        for key in ["HOME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE"] { environment[key] = current[key] }
        return environment
    }

    static func find(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> AdapterLocation? {
        let location: AdapterLocation
        // Testing builds only: a published app never loads code from a folder an environment names.
        #if PANCAKENOTCH_INTERNAL_TESTING
        let folder = environment["PANCAKENOTCH_ADAPTER_DIR"]
        #else
        let folder: String? = nil
        #endif
        if let folder, !folder.isEmpty {
            let base = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL
            location = AdapterLocation(
                script: base.appending(path: scriptName),
                framework: base.appending(path: frameworkName, directoryHint: .isDirectory)
            )
        } else {
            guard let resources = bundle.resourceURL, let frameworks = bundle.privateFrameworksURL else { return nil }
            location = AdapterLocation(
                script: resources.appending(path: scriptName),
                framework: frameworks.appending(path: frameworkName, directoryHint: .isDirectory)
            )
        }
        guard fileManager.isExecutableFile(atPath: perl.path),
              fileManager.fileExists(atPath: location.script.path),
              fileManager.fileExists(atPath: location.framework.path)
        else { return nil }
        return location
    }

    /// The arguments after `perl` for one command.
    func arguments(_ function: [String]) -> [String] {
        [script.path, framework.standardizedFileURL.path] + function
    }

    /// The long-running stream: microsecond times, at most one update per 100 ms.
    static let streamFunction = ["stream", "--micros", "--debounce=100"]

    /// The adapter function for a command (`send <id>`, `seek <µs>`, `shuffle <mode>`, `repeat <mode>`).
    static func function(for command: NowPlayingCommand) -> [String] {
        switch command {
        case .play: ["send", "0"]
        case .pause: ["send", "1"]
        case .togglePlayPause: ["send", "2"]
        case .next: ["send", "4"]
        case .previous: ["send", "5"]
        case .seek(let seconds): ["seek", String(Int64((max(0, seconds) * 1_000_000).rounded()))]
        case .setShuffle(let mode): ["shuffle", String(mode.rawValue)]
        case .setRepeat(let mode): ["repeat", String(mode.rawValue)]
        }
    }
}

/// Runs `mediaremote-adapter stream` as a child process and short-lived processes for commands.
/// Doesn't decide anything: `CompositeBackend` handles restarts and the fallback.
@MainActor
final class AdapterProcess {
    /// A new state from the stream (already parsed and merged off the main thread).
    var onOutput: ((NowPlayingUpdate) -> Void)?
    /// The stream ended without `stop()` being called.
    var onExit: ((_ status: Int32) -> Void)?

    private var process: Process?
    private var outputHandle: FileHandle?
    /// Bumped on every launch and stop, so output and exits of an old process are ignored.
    private var generation = 0
    /// Command processes, kept until they finish.
    private var commands: [ObjectIdentifier: Process] = [:]
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "nowplaying")

    var processID: pid_t? { process?.isRunning == true ? process?.processIdentifier : nil }
    var isRunning: Bool { process != nil }

    /// Starts the stream. Throws when Perl couldn't be started.
    func launch(_ location: AdapterLocation) throws {
        stop()
        generation += 1
        let generation = generation

        let process = Process()
        process.executableURL = AdapterLocation.perl
        process.arguments = location.arguments(AdapterLocation.streamFunction)
        process.environment = AdapterLocation.perlEnvironment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        let reader = AdapterStreamReader { [weak self] update in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.onOutput?(update)
            }
        }
        process.terminationHandler = { [weak self] ended in
            let status = ended.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == generation else { return }
                    self.logger.notice("Now Playing helper ended (status \(status))")
                    self.outputHandle?.readabilityHandler = nil
                    self.outputHandle = nil
                    self.process = nil
                    // Output still on its way from this helper mustn't count after its exit.
                    self.generation += 1
                    self.onExit?(status)
                }
            }
        }

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil  // end of output
            } else {
                reader.consume(data)
            }
        }
        do {
            try process.run()
        } catch {
            handle.readabilityHandler = nil
            logger.error("Couldn't start the Now Playing helper: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        self.process = process
        outputHandle = handle
        logger.info("Now Playing helper started (pid \(process.processIdentifier))")
    }

    /// Ends the stream (if any). Its exit isn't reported.
    func stop() {
        generation += 1
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
    }

    /// Sends a command with a short-lived helper process.
    func send(_ command: NowPlayingCommand, location: AdapterLocation) {
        let process = Process()
        process.executableURL = AdapterLocation.perl
        process.arguments = location.arguments(AdapterLocation.function(for: command))
        process.environment = AdapterLocation.perlEnvironment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let id = ObjectIdentifier(process)
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.commands[id] = nil }
            }
        }
        do {
            try process.run()
            commands[id] = process
        } catch {
            logger.error("Couldn't send a Now Playing command: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Parses the stream on its own serial queue (JSON and artwork decoding stay off the main thread).
final class AdapterStreamReader: @unchecked Sendable {
    // `parser` is only touched on `queue`, which makes this safe to share.
    private let queue = DispatchQueue(label: "io.github.sickpancake.PancakeNotch.nowplaying.stream", qos: .utility)
    private var parser = AdapterStreamParser()
    private let lock = NSLock()
    private var latest: NowPlayingUpdate?
    private var scheduled = false
    private let deliver: @Sendable (NowPlayingUpdate) -> Void

    init(deliver: @escaping @Sendable (NowPlayingUpdate) -> Void) {
        self.deliver = deliver
    }

    func consume(_ data: Data) {
        // Parse before returning to the pipe: the producer waits instead of queuing raw chunks.
        queue.sync {
            guard let update = autoreleasepool(invoking: { parser.feed(data, receivedAt: Date()) }) else { return }
            lock.lock()
            latest = update
            let needsDelivery = !scheduled
            scheduled = true
            lock.unlock()
            if needsDelivery { DispatchQueue.main.async { self.flush() } }
        }
    }

    private func flush() {
        lock.lock()
        let update = latest
        latest = nil
        scheduled = false
        lock.unlock()
        if let update { deliver(update) }
    }
}
