import CoreServices
import Foundation

/// Calls back when files change under some folders (FSEvents). macOS gathers changes for `latency`
/// seconds and reports them in one batch, so a busy agent writing its log many times a second wakes
/// PancakeNotch at most once per `latency`. Nothing runs while nothing changes. The stream keeps the
/// watcher alive until `stop()`.
final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private var info: UnsafeMutableRawPointer?
    private let queue: DispatchQueue
    private let onChange: @Sendable ([String]) -> Void

    /// - Parameter onChange: the changed paths, on `queue`.
    init?(paths: [String], latency: TimeInterval, queue: DispatchQueue, onChange: @escaping @Sendable ([String]) -> Void) {
        // A new account may not have its sessions/projects directory yet. Watch its nearest existing
        // parent so creating the directory and the first log still reaches the same stream.
        let existing = Array(Set(paths.map { path in
            var folder = URL(fileURLWithPath: path)
            while !FileManager.default.fileExists(atPath: folder.path), folder.path != "/" {
                folder.deleteLastPathComponent()
            }
            return folder.path
        }.filter { $0 != "/" }))
        guard !existing.isEmpty else { return nil }
        self.queue = queue
        self.onChange = onChange
        let info = Unmanaged.passRetained(self).toOpaque()
        var context = FSEventStreamContext(version: 0, info: info,
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.onChange(Array(list.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(nil, callback, &context, existing as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else {
            Unmanaged<FolderWatcher>.fromOpaque(info).release()
            return nil
        }
        self.stream = stream
        self.info = info
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    /// Call once, on `queue` or while no callback can be running; the watcher goes away afterwards.
    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        if let info { Unmanaged<FolderWatcher>.fromOpaque(info).release() }
        info = nil
    }
}

/// Calls back when one file is written, replaced or deleted (a kqueue vnode source): for files outside
/// any folder worth watching, like `~/.claude.json` in the home folder. A file replaced by an atomic
/// save is followed to its new copy.
final class FileChangeWatcher: @unchecked Sendable {
    private let path: String
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var stopped = false

    init(path: String, queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        self.path = path
        self.queue = queue
        self.onChange = onChange
        queue.async { self.arm() }
    }

    private func arm() {
        source?.cancel()
        source = nil
        guard !stopped else { return }
        // Non-blocking: a path that turns out to be a pipe would otherwise hang this queue on open.
        let fd = open(path, O_EVTONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            // A first-use config may not exist yet. The parent directory tells us when it is created,
            // without a retry timer or a watch over everything below the user's home folder.
            let parent = open((path as NSString).deletingLastPathComponent, O_EVTONLY | O_NONBLOCK | O_CLOEXEC)
            guard parent >= 0 else { return }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: parent, eventMask: [.write], queue: queue)
            source.setEventHandler { [weak self] in
                self?.arm()
                self?.onChange()
            }
            source.setCancelHandler { close(parent) }
            self.source = source
            source.resume()
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self, let current = self.source else { return }
            let replaced = !current.data.isDisjoint(with: [.rename, .delete])
            self.onChange()
            // The old file went away (an atomic save): follow the new one.
            if replaced { self.arm() }
        }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }

    func stop() {
        queue.async {
            self.stopped = true
            self.source?.cancel()
            self.source = nil
        }
    }
}
