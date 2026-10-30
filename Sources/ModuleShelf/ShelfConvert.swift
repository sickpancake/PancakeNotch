import AppKit
import ConvertKit
import NotchCore
import Observation
import os
import SwiftUI

/// One Convert: the files, the row of formats, then progress and what came out (ADR-0038).
@MainActor
@Observable
final class ShelfConversion {
    enum Phase: Equatable {
        /// Files dropped as promises (Photos, Mail) are still arriving.
        case receiving
        /// The helper is reading the files (sizes, pages, length) to dim what doesn't fit.
        case looking
        case choosing
        case converting(ConvertFormat)
        case done(Done)
        case failed(String)
    }

    struct Done: Equatable {
        var format: ConvertFormat
        var files: [URL]
        /// How many files couldn't be converted (the others were).
        var failed: Int
        /// Kept in the Shelf's own storage, because where it would have gone can't be written to.
        var keptInShelf: Bool
    }

    var sources: [URL]
    var options: [ConvertOption] = []
    /// The tile the arrow keys are on.
    var focus: ConvertFormat?
    var phase: Phase
    var progress = 0.0
    /// The notch closed while it converted: it carries on, and says so in a strip under the notch.
    var isDetached = false
    @ObservationIgnored var temporaryFolders: [URL] = []
    @ObservationIgnored var task: Task<Void, Never>?
    /// Promised files still to arrive.
    @ObservationIgnored var waiting = 0

    init(sources: [URL], phase: Phase) {
        self.sources = sources
        self.phase = phase
    }

    /// "Report.docx", or "3 files".
    var title: String {
        if sources.count == 1, let source = sources.first { return source.lastPathComponent }
        return String(localized: "\(sources.count) files", comment: "Convert: several dropped files")
    }

    var isConverting: Bool {
        if case .converting = phase { return true }
        return false
    }

    var focusedOption: ConvertOption? { options.first { $0.format == focus } }
}

extension ShelfModule {
    /// Convert is switched on and its helper is in the app.
    var canConvert: Bool { settings.convertEnabled && convertRunner != nil }

    /// The Convert session on screen (one that carries on after the notch closed isn't).
    var visibleConversion: ShelfConversion? {
        conversion.flatMap { $0.isDetached ? nil : $0 }
    }

    /// The formats files could become, from their names only (no disk access: works mid-drag).
    func convertFormats(for files: [URL]) -> [ConvertFormat] {
        ConvertCatalog.formats(for: files, wordToPDF: settings.convertWordToPDF)
    }

    /// Whether "Convert…" shows for these Shelf items: all files, with a format in common.
    func canConvert(_ items: [ShelfItem]) -> Bool {
        let files = items.compactMap(\.fileURL)
        return canConvert && !files.isEmpty && files.count == items.count && !convertFormats(for: files).isEmpty
    }

    // MARK: Starting

    /// "Convert…" on Shelf items (the menu, the preview).
    func convert(_ items: [ShelfItem]) {
        let files = items.compactMap { $0.isFile ? store.resolvedURL(for: $0) : nil }
        guard !files.isEmpty else { return }
        closeDetail()
        startConversion(files)
    }

    /// Shows the format row for `files` (and promised files still to come) in the taller panel.
    func startConversion(_ files: [URL], promises: [NSFilePromiseReceiver] = [], temporaryFolders: [URL] = []) {
        endConversion()
        guard canConvert else { return }
        let session = ShelfConversion(sources: files, phase: promises.isEmpty ? .looking : .receiving)
        session.temporaryFolders = temporaryFolders
        selection = []
        setHold { $0.conversion = session }
        notch?.setPanelHeight(.medium)
        requestFocus()
        watchConvertClicksAway()
        if promises.isEmpty {
            look(at: session)
        } else {
            receive(promises, for: session)
        }
    }

    /// Promised files arrive in a temporary folder; the row shows once they're all here.
    private func receive(_ promises: [NSFilePromiseReceiver], for session: ShelfConversion) {
        guard let folder = try? ShelfSharing.makeTemporaryFolder() else {
            session.phase = .failed(ConvertFailure.unreadable.message)
            return
        }
        session.temporaryFolders.append(folder)
        session.waiting = ShelfDropReader.expectedFileCount(promises)
        for promise in promises {
            ShelfDropReader.receive(promise, into: folder, queue: promiseQueue) { [weak self, weak session] url in
                Task { @MainActor in
                    guard let self, let session, self.conversion === session, session.phase == .receiving else { return }
                    if let url { session.sources.append(url) }
                    session.waiting -= 1
                    guard session.waiting <= 0 else { return }
                    if session.sources.isEmpty {
                        session.phase = .failed(String(localized: "The files didn't arrive.", comment: "Convert: promised files failed"))
                    } else {
                        session.phase = .looking
                        self.look(at: session)
                    }
                }
            }
        }
    }

    /// The row from the files' names straight away; the helper then reads them to dim what won't fit.
    private func look(at session: ShelfConversion) {
        let resolved = session.sources.map { $0.resolvingSymlinksInPath() }
        guard resolved.allSatisfy({ (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }) else {
            session.phase = .failed(ConvertFailure.unreadable.message)
            return
        }
        session.sources = resolved
        let wordToPDF = settings.convertWordToPDF
        let formats = convertFormats(for: session.sources)
        guard !formats.isEmpty else {
            session.phase = .failed(session.sources.count == 1
                ? String(localized: "This file can't be converted.", comment: "Convert: unsupported file")
                : String(localized: "These files have no format in common.", comment: "Convert: several files of different kinds"))
            return
        }
        session.options = formats.map { ConvertOption(format: $0) }
        session.focus = formats.first
        guard let runner = convertRunner else { return }
        let quality = settings.convertQuality
        session.task = Task { [weak self, weak session] in
            guard let sources = session?.sources else { return }
            let infos = try? await runner.probe(sources)
            guard !Task.isCancelled, let self, let session, self.conversion === session else { return }
            guard let infos else {
                session.phase = .failed(ConvertFailure.failed.message)
                return
            }
            session.options = ConvertCatalog.options(for: sources, infos: infos, wordToPDF: wordToPDF, quality: quality)
            session.focus = session.options.first(where: \.isAvailable)?.format ?? session.options.first?.format
            session.phase = .choosing
        }
    }

    // MARK: Converting

    /// A tile was picked (click, Return): convert every file to it.
    func chooseConvertFormat(_ format: ConvertFormat) {
        guard let session = visibleConversion, session.phase == .choosing, let runner = convertRunner,
              session.options.contains(where: { $0.format == format && $0.isAvailable }),
              let output = try? ShelfSharing.makeTemporaryFolder() else { return }
        session.focus = format
        session.progress = 0
        session.phase = .converting(format)
        let request = ConvertRequest(
            sources: session.sources.map(\.path), format: format, quality: settings.convertQuality,
            outputFolder: output.path,
            pageName: String(localized: "Page", comment: "Convert: a PDF page's picture, as in \"Page 01.png\"")
        )
        AccessibilityNotification.Announcement(String(localized: "Converting to \(format.title)", comment: "VoiceOver; Convert started")).post()
        session.task = Task { [weak self, weak session] in
            let result: Result<ConvertMessage, any Error>
            do {
                result = .success(try await runner.convert(request) { value in
                    Task { @MainActor in session?.progress = value }
                })
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, let self, let session, self.conversion === session else {
                try? FileManager.default.removeItem(at: output)
                return
            }
            switch result {
            case .success(let message): self.finish(session, format: format, message: message, output: output)
            case .failure: session.phase = .failed(ConvertFailure.failed.message)
            }
            if session.isDetached { self.finishedInBackground(session) }
        }
    }

    /// The stop button (or Esc) while converting: back to the row, nothing kept.
    func stopConverting() {
        guard let session = conversion, session.isConverting else { return }
        session.task?.cancel()
        session.task = nil
        session.phase = .choosing
        session.progress = 0
    }

    /// Moves what the helper made to where it goes, never over an existing file, and adds it to the Shelf.
    private func finish(_ session: ShelfConversion, format: ConvertFormat, message: ConvertMessage, output: URL) {
        defer { try? FileManager.default.removeItem(at: output) }
        var files: [URL] = []
        var inputs: [ShelfInput] = []
        var keptInShelf = false
        for made in message.outputs ?? [] {
            let produced = URL(fileURLWithPath: made.path)
            let source = made.source.flatMap { session.sources.indices.contains($0) ? session.sources[$0] : nil } ?? session.sources.first
            let isFolder = (try? produced.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let base: String
            if format == .combinedPDF {
                base = String(localized: "Combined", comment: "Convert: the name of a PDF made from several files")
            } else if isFolder {
                let name = source?.deletingPathExtension().lastPathComponent ?? produced.lastPathComponent
                base = String(localized: "\(name) pages", comment: "Convert: the folder of a PDF's page pictures")
            } else {
                base = produced.deletingPathExtension().lastPathComponent
            }
            let ext = isFolder ? nil : produced.pathExtension
            if let folder = convertDestination(for: source) {
                let target = ConvertNaming.uniqueURL(in: folder, base: base, ext: ext)
                if (try? FileManager.default.moveItem(at: produced, to: target)) != nil {
                    files.append(target)
                    inputs.append(.file(target, owned: false))
                    continue
                }
            }
            // The usual place can't be written to: the Shelf keeps it.
            guard let folder = try? store.newFilesFolder() else { continue }
            let target = ConvertNaming.uniqueURL(in: folder, base: base, ext: ext)
            if (try? FileManager.default.moveItem(at: produced, to: target)) != nil {
                files.append(target)
                inputs.append(.file(target, owned: true))
                keptInShelf = true
            }
        }
        let failures = message.errors ?? []
        guard !files.isEmpty else {
            session.phase = .failed((failures.first?.failure ?? .failed).message)
            AccessibilityNotification.Announcement(String(localized: "Couldn't convert", comment: "VoiceOver; Convert failed")).post()
            return
        }
        session.phase = .done(ShelfConversion.Done(format: format, files: files, failed: failures.count, keptInShelf: keptInShelf))
        AccessibilityNotification.Announcement(Self.doneText(files: files)).post()
        offer(inputs)
    }

    /// Where a converted file goes: the chosen folder, or beside the original. Nil: the Shelf keeps it
    /// (the original is the Shelf's own or a dropped picture, or the place can't be written to).
    func convertDestination(for source: URL?) -> URL? {
        guard !keepsConvertedFiles else { return nil }
        let manager = FileManager.default
        if settings.convertDestination == .folder, let folder = settings.convertFolder {
            return manager.isWritableFile(atPath: folder.path) ? folder : nil
        }
        guard let source else { return nil }
        let realSource = source.resolvingSymlinksInPath()
        guard (try? realSource.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
        let path = realSource.standardizedFileURL.path
        let ownFolders = [store.filesDirectory, ShelfSharing.temporaryRoot].map { $0.standardizedFileURL.path + "/" }
        guard !ownFolders.contains(where: path.hasPrefix) else { return nil }
        let folder = realSource.deletingLastPathComponent()
        return manager.isWritableFile(atPath: folder.path) ? folder : nil
    }

    static func doneText(files: [URL]) -> String {
        files.count == 1
            ? String(localized: "Converted \(files[0].lastPathComponent)", comment: "Convert finished; the new file's name")
            : String(localized: "Converted \(files.count) files", comment: "Convert finished; how many files")
    }

    // MARK: Ending

    /// Back to the Shelf (Esc, the back button, a click elsewhere): stops a conversion still running.
    func endConversion() {
        guard let session = conversion else { return }
        session.task?.cancel()
        session.task = nil
        for folder in session.temporaryFolders { try? FileManager.default.removeItem(at: folder) }
        stopWatchingConvertClicksAway()
        setHold { $0.conversion = nil }
        if !session.isDetached { notch?.setPanelHeight(.regular) }
    }

    /// The notch is closing (or a click went elsewhere): a conversion carries on out of sight; anything
    /// else ends.
    func leaveConversion() {
        guard let session = conversion, !session.isDetached else { return }
        guard session.isConverting else {
            endConversion()
            return
        }
        stopWatchingConvertClicksAway()
        setHold { _ in session.isDetached = true }
        notch?.setPanelHeight(.regular)
    }

    /// Opening the notch again while it converts out of sight brings the progress back.
    func returnToConversion() {
        guard let session = conversion, session.isDetached, session.isConverting else { return }
        session.isDetached = false
        notch?.setPanelHeight(.medium)
        watchConvertClicksAway()
    }

    /// Finished out of sight: a strip under the notch says so, and the session ends.
    private func finishedInBackground(_ session: ShelfConversion) {
        switch session.phase {
        case .done(let done):
            convertPeekText = Self.doneText(files: done.files)
            convertPeekFailed = false
        case .failed:
            convertPeekText = String(localized: "Couldn't convert \(session.title)", comment: "Convert failed while the notch was closed")
            convertPeekFailed = true
        default:
            return
        }
        endConversion()
        notch?.peek(self, for: .seconds(3))
    }

    // MARK: Keys and clicks

    /// Arrows move along the row, Return converts, Esc stops or goes back.
    func handleConvertKey(_ event: NSEvent) -> Bool {
        guard let session = visibleConversion else { return false }
        switch event.keyCode {
        case 123, 124: // ← →
            guard session.phase == .choosing || session.phase == .looking else { return true }
            let formats = session.options.map(\.format)
            guard let current = session.focus.flatMap(formats.firstIndex(of:)) else {
                session.focus = formats.first
                return true
            }
            session.focus = formats[min(max(current + (event.keyCode == 123 ? -1 : 1), 0), formats.count - 1)]
            return true
        case 36, 76, 49: // Return, Enter, Space
            if session.phase == .choosing, let focus = session.focus { chooseConvertFormat(focus) }
            return true
        case 53: // Esc
            if session.isConverting { stopConverting() } else { endConversion() }
            return true
        default:
            // ⌘ shortcuts (⌘Q…) still go through.
            return !event.modifierFlags.contains(.command)
        }
    }

    /// While the row shows, a click in another app (or switching apps) puts it away, like an open item.
    private func watchConvertClicksAway() {
        guard convertClickMonitor == nil else { return }
        convertClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.leaveConversion() }
        }
        convertAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.leaveConversion() }
        }
    }

    func stopWatchingConvertClicksAway() {
        if let convertClickMonitor { NSEvent.removeMonitor(convertClickMonitor) }
        convertClickMonitor = nil
        if let convertAppObserver { NSWorkspace.shared.notificationCenter.removeObserver(convertAppObserver) }
        convertAppObserver = nil
    }
}
