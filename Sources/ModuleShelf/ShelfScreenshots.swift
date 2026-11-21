import FileWatching
import Foundation
import Observation
import os

/// Catches new screenshots onto the Shelf (opt-in, Shelf settings). It watches the folder macOS saves
/// screenshots to (FSEvents, nothing runs while nothing changes) only while the setting and the Shelf
/// are both on. A file counts as a screenshot when macOS marked it as one, so screen recordings,
/// other apps' pictures and old screenshots being renamed are left alone.
@MainActor
@Observable
public final class ShelfScreenshots {
    /// Whether PancakeNotch may look in the screenshot folder (Desktop, Documents and Downloads are
    /// guarded by macOS's Files and Folders privacy setting).
    public enum Access: Equatable, Sendable {
        case unknown
        case checking
        case allowed
        case denied
    }

    /// Where screenshots go right now. Nil until the setting is first switched on.
    public private(set) var location: ScreenshotLocation?
    public private(set) var access: Access = .unknown

    /// The Shelf that receives them: the real notch's, while the Shelf is switched on.
    @ObservationIgnored private weak var shelf: ShelfModule?
    @ObservationIgnored private let settings: ShelfSettings
    @ObservationIgnored private let readLocation: @Sendable () -> ScreenshotLocation
    @ObservationIgnored private let preferencesFile: String?
    @ObservationIgnored private var folderWatcher: FolderWatcher?
    @ObservationIgnored private var watchedFolder: String?
    @ObservationIgnored private var preferencesWatcher: FileChangeWatcher?
    /// Screenshots already offered (by file identity: a rename is still the same file), so a later
    /// change to the same file (macOS adds its details in steps) doesn't add it again after it was removed.
    @ObservationIgnored private var caught: [NSObject] = []
    @ObservationIgnored private let queue = DispatchQueue(label: "io.github.sickpancake.PancakeNotch.screenshots", qos: .utility)
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "shelf")

    /// - Parameters:
    ///   - readLocation: where macOS saves screenshots (a fixed one in tests).
    ///   - preferencesFile: macOS's screenshot settings file, watched so a new folder chosen in the
    ///     Screenshot app (⇧⌘5) is followed. Nil in tests.
    public init(
        settings: ShelfSettings,
        readLocation: @escaping @Sendable () -> ScreenshotLocation = ScreenshotLocation.current,
        preferencesFile: String? = ScreenshotLocation.preferencesFile
    ) {
        self.settings = settings
        self.readLocation = readLocation
        self.preferencesFile = preferencesFile
        observeSettings()
    }

    /// The Shelf to catch screenshots onto, or nil when the Shelf is switched off.
    public func follow(_ shelf: ShelfModule?) {
        guard shelf !== self.shelf else { return }
        self.shelf = shelf
        update()
    }

    private var isRunning: Bool { settings.catchesScreenshots && shelf != nil }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.catchesScreenshots
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observeSettings()
            }
        }
    }

    /// Starts or stops watching to match the setting and the Shelf.
    private func update() {
        guard isRunning else {
            stopWatching()
            return
        }
        if preferencesWatcher == nil, let preferencesFile {
            preferencesWatcher = FileChangeWatcher(path: preferencesFile, queue: queue) { [weak self] in
                Task { @MainActor in self?.locationMayHaveChanged() }
            }
        }
        refreshLocation()
    }

    /// The Screenshot app's settings changed (or macOS wrote them again): follow a new folder.
    private func locationMayHaveChanged() {
        refreshLocation()
    }

    /// Try Again in Shelf settings, after allowing access in System Settings.
    public func tryAgain() {
        refreshLocation(checkingAgain: true)
    }

    /// Reads where screenshots go and watches that folder, checking access when it's a new folder.
    private func refreshLocation(checkingAgain: Bool = false) {
        guard isRunning else { return }
        let location = readLocation()
        if self.location != location { self.location = location }
        guard watchedFolder != location.folder.path || folderWatcher == nil else {
            if checkingAgain { checkAccess(location.folder) }
            return
        }
        folderWatcher?.stop()
        folderWatcher = nil
        watchedFolder = location.folder.path
        checkAccess(location.folder)
        // FSEvents reports real paths (/private/var/…, no symbolic links): compare with both.
        let folders = Set([location.folder.path, ScreenshotLocation.realPath(location.folder.path)])
        folderWatcher = FolderWatcher(paths: [location.folder.path], latency: 0.5, queue: queue) { [weak self] paths in
            // Reading each file's details happens here, off the main thread.
            let found = ScreenshotLocation.newScreenshots(in: paths, folders: folders, now: Date())
            guard !found.isEmpty else { return }
            Task { @MainActor in self?.arrived(found) }
        }
        if folderWatcher == nil { logger.error("Couldn't watch the screenshot folder") }
    }

    /// Asks macOS for the folder once (the first time it may show its "would like to access" prompt),
    /// off the main thread since that prompt waits for an answer.
    private func checkAccess(_ folder: URL) {
        access = .checking
        Task {
            let allowed = await Task.detached(priority: .userInitiated) {
                ScreenshotLocation.canRead(folder)
            }.value
            guard watchedFolder == folder.path else { return }
            access = allowed ? .allowed : .denied
        }
    }

    private func stopWatching() {
        folderWatcher?.stop()
        folderWatcher = nil
        watchedFolder = nil
        preferencesWatcher?.stop()
        preferencesWatcher = nil
        access = .unknown
    }

    /// New screenshots in the watched folder, oldest first.
    func arrived(_ urls: [URL]) {
        guard isRunning, let shelf else { return }
        for url in urls {
            guard let identity = ScreenshotLocation.fileIdentity(url),
                  !caught.contains(where: { $0.isEqual(identity) }) else { continue }
            caught.append(identity)
            if caught.count > 50 { caught.removeFirst(caught.count - 50) }
            // A screenshot read and kept means access works (it may have been allowed since).
            let kept = shelf.catchScreenshot(url)
            if access != .checking { access = kept ? .allowed : .denied }
        }
    }
}

/// Where macOS saves screenshots: its Screenshot app's "Save to" (`com.apple.screencapture`).
public struct ScreenshotLocation: Equatable, Sendable {
    public var folder: URL
    /// False when screenshots go to the clipboard, Preview, Mail or Messages instead of a file.
    public var savesFiles: Bool

    public init(folder: URL, savesFiles: Bool) {
        self.folder = folder
        self.savesFiles = savesFiles
    }

    public static let domain = "com.apple.screencapture"

    public static var preferencesFile: String {
        NSHomeDirectory() + "/Library/Preferences/\(domain).plist"
    }

    /// The location macOS uses now. Re-reads its settings rather than an earlier cached copy.
    @Sendable public static func current() -> ScreenshotLocation {
        CFPreferencesAppSynchronize(domain as CFString)
        let location = CFPreferencesCopyAppValue("location" as CFString, domain as CFString) as? String
        let target = CFPreferencesCopyAppValue("target" as CFString, domain as CFString) as? String
        return resolve(location: location, target: target, home: NSHomeDirectory()) { path in
            var isFolder: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && isFolder.boolValue
        }
    }

    /// The folder for a "Save to" setting, like macOS: `~` is the home folder, and a missing or
    /// deleted folder means the Desktop.
    static func resolve(location: String?, target: String?, home: String, isFolder: (String) -> Bool) -> ScreenshotLocation {
        let desktop = URL(fileURLWithPath: home + "/Desktop", isDirectory: true)
        let savesFiles = target.map { $0.isEmpty || $0 == "file" } ?? true
        guard var path = location?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return ScreenshotLocation(folder: desktop, savesFiles: savesFiles)
        }
        if path.hasPrefix("file://"), let url = URL(string: path), url.isFileURL { path = url.path }
        if path == "~" { path = home } else if path.hasPrefix("~/") { path = home + path.dropFirst(1) }
        // Plain strings: on macOS 15 URL's path walking differs (AGENTS.md rule 4).
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        guard path.hasPrefix("/"), isFolder(path) else { return ScreenshotLocation(folder: desktop, savesFiles: savesFiles) }
        return ScreenshotLocation(folder: URL(fileURLWithPath: path, isDirectory: true), savesFiles: savesFiles)
    }

    /// The folder's name for settings: "Desktop", "Captures".
    public var folderName: String {
        FileManager.default.displayName(atPath: folder.path)
    }

    /// Whether PancakeNotch may list the folder. The first try may show macOS's access prompt.
    static func canRead(_ folder: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
    }

    /// macOS marks its screenshots with this (a Spotlight detail kept on the file itself).
    static let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"
    /// How recent a file must be. macOS saves a screenshot a few seconds after it's taken (once its
    /// thumbnail goes away), so this is generous; renaming an old screenshot doesn't count.
    static let freshness: TimeInterval = 120

    /// The path with symbolic links followed, as FSEvents reports it.
    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The changed paths that are new screenshots, directly in the folder (`folders`: its path and
    /// its real path), oldest first.
    static func newScreenshots(in paths: [String], folders: Set<String>, now: Date) -> [URL] {
        var seen = Set<String>()
        let found: [(url: URL, created: Date)] = paths.compactMap { path in
            guard seen.insert(path).inserted else { return nil }
            let url = URL(fileURLWithPath: path)
            guard folders.contains((path as NSString).deletingLastPathComponent),
                  let created = screenshotDate(url), now.timeIntervalSince(created) < freshness,
                  created.timeIntervalSince(now) < 60 else { return nil }
            return (url, created)
        }
        return found.sorted { $0.created < $1.created }.map(\.url)
    }

    /// When the file was made, if it's a visible, ordinary file macOS marked as a screenshot.
    static func screenshotDate(_ url: URL) -> Date? {
        // macOS writes a hidden ".Screenshot…" first, then renames it.
        guard !url.lastPathComponent.hasPrefix("."),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey, .creationDateKey]),
              values.isRegularFile == true, values.isHidden != true,
              isMarkedAsScreenshot(url) else { return nil }
        return values.creationDate
    }

    /// The file's identity, so a rename within the freshness window isn't caught a second time.
    static func fileIdentity(_ url: URL) -> NSObject? {
        (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? NSObject
    }

    static func isMarkedAsScreenshot(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, screenCaptureAttribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
    }
}
