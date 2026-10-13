import CoreAudio
import Foundation

/// One app process that Core Audio knows about (it has used sound since it started).
struct AudioProcess: Equatable, Sendable {
    var objectID: AudioObjectID
    var processID: Int32
    var bundleID: String
    /// The process is playing sound right now.
    var isRunningOutput: Bool
}

/// Which of Core Audio's processes belong to the playing app. Pure, for tests.
struct AudioProcessSelection: Equatable {
    /// Every process of the app: their "making sound" switch is watched.
    var watched: [AudioObjectID] = []
    /// The processes to listen to: those making sound, else the one macOS named, else all of them.
    var tapped: [AudioObjectID] = []
    /// One of the app's processes is making sound.
    var isRunningOutput = false

    init(source: SoundSourceID, processes: [AudioProcess], ownProcessID: Int32) {
        let prefixes = source.bundleIDs.map { $0.lowercased() }
        let matches = processes.filter { process in
            guard process.processID != ownProcessID else { return false }
            if let processID = source.processID, process.processID == processID { return true }
            let bundleID = process.bundleID.lowercased()
            guard !bundleID.isEmpty else { return false }
            // The app itself or its helpers ("com.google.Chrome" → "com.google.Chrome.helper").
            return prefixes.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
        }
        watched = matches.map(\.objectID)
        let running = matches.filter(\.isRunningOutput)
        isRunningOutput = !running.isEmpty
        if !running.isEmpty {
            tapped = running.map(\.objectID)
        } else if let named = matches.first(where: { $0.processID == source.processID }) {
            tapped = [named.objectID]
        } else {
            tapped = watched
        }
    }
}

/// Reads Core Audio's process list (no permission needed).
enum AudioProcessList {
    static func read() -> [AudioProcess] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        ids = Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
        return ids.compactMap { id in
            guard let processID: Int32 = value(of: kAudioProcessPropertyPID, on: id) else { return nil }
            let running: UInt32 = value(of: kAudioProcessPropertyIsRunningOutput, on: id) ?? 0
            return AudioProcess(objectID: id, processID: processID, bundleID: bundleID(of: id) ?? "", isRunningOutput: running != 0)
        }
    }

    static func isRunningOutput(_ id: AudioObjectID) -> Bool {
        let running: UInt32 = value(of: kAudioProcessPropertyIsRunningOutput, on: id) ?? 0
        return running != 0
    }

    static func value<T>(of selector: AudioObjectPropertySelector, on id: AudioObjectID) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr,
              size == UInt32(MemoryLayout<T>.size) else { return nil }
        return pointer.load(as: T.self)
    }

    private static func bundleID(of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}

/// Watches whether the playing app is making sound, through Core Audio's "running output" switch on
/// its processes. Callbacks only (no polling, no permission). Also notices when the app's processes
/// come and go and when the sound output changes (headphones), so a listening tap can be set up again.
@MainActor
final class AudioOutputWatcher {
    let source: SoundSourceID
    /// Something changed. `tapChanged`: the processes to listen to are different now, or the output
    /// device changed.
    var onChange: ((_ tapChanged: Bool) -> Void)?

    /// The processes to listen to.
    private(set) var tapped: [AudioObjectID] = []
    /// Whether the app is making sound. nil until one of its processes has been seen making sound
    /// (then the switch is trusted; before that, it may be the wrong process).
    private(set) var isRunningOutput: Bool?

    private var sawOutput = false
    private var isWatching = false
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var systemListeners: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []

    init(source: SoundSourceID) {
        self.source = source
    }

    func start() {
        guard !isWatching else { return }
        isWatching = true
        for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDefaultOutputDevice] {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.refresh(deviceChanged: selector == kAudioHardwarePropertyDefaultOutputDevice)
                }
            }
            var address = Self.address(selector)
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
                systemListeners.append((selector, block))
            }
        }
        refresh(deviceChanged: false)
    }

    func stop() {
        guard isWatching else { return }
        isWatching = false
        for (selector, block) in systemListeners {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        systemListeners = []
        for id in Array(processListeners.keys) { unwatch(id) }
        onChange = nil
    }

    private func refresh(deviceChanged: Bool) {
        guard isWatching else { return }
        let selection = AudioProcessSelection(source: source, processes: AudioProcessList.read(), ownProcessID: getpid())
        let wanted = Set(selection.watched)
        for id in processListeners.keys where !wanted.contains(id) { unwatch(id) }
        for id in selection.watched where processListeners[id] == nil { watch(id) }
        if selection.isRunningOutput { sawOutput = true }
        let running: Bool? = sawOutput ? selection.isRunningOutput : nil
        let tapChanged = selection.tapped != tapped || deviceChanged
        guard tapChanged || running != isRunningOutput else { return }
        tapped = selection.tapped
        isRunningOutput = running
        onChange?(tapChanged)
    }

    private func watch(_ id: AudioObjectID) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh(deviceChanged: false) }
        }
        var address = Self.address(kAudioProcessPropertyIsRunningOutput)
        if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr {
            processListeners[id] = block
        }
    }

    private func unwatch(_ id: AudioObjectID) {
        guard let block = processListeners.removeValue(forKey: id) else { return }
        var address = Self.address(kAudioProcessPropertyIsRunningOutput)
        // Fails harmlessly when the process has already gone.
        AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}

/// Whether some apps (their helper processes included) are making sound right now, from Core Audio's
/// "running output" switch. Callbacks only, no permission. Tells whether the full-screen app plays, so
/// the notch can hide for its video but not for music playing in the background (ADR-0030).
@MainActor
public final class AppSoundWatcher {
    /// `isMakingSound` changed.
    public var onChange: (() -> Void)?
    public private(set) var isMakingSound = false
    private var sources: [SoundSourceID] = []
    private var watchers: [AudioOutputWatcher] = []

    public init() {}

    /// Watches these apps instead; an empty list stops watching.
    public func watch(_ apps: [SoundSourceID]) {
        guard apps != sources else { return }
        sources = apps
        watchers.forEach { $0.stop() }
        watchers = apps.map { source in
            let watcher = AudioOutputWatcher(source: source)
            watcher.start()
            watcher.onChange = { [weak self] _ in self?.refresh() }
            return watcher
        }
        refresh()
    }

    private func refresh() {
        let making = watchers.contains { $0.isRunningOutput == true }
        guard making != isMakingSound else { return }
        isMakingSound = making
        onChange?()
    }
}
