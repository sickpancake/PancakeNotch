import AppKit
import UniformTypeIdentifiers

/// What the tall view shows about the open item, gathered once when it opens.
struct ShelfDetailInfo: Equatable {
    var kind: String
    var size: String?
    var path: String?
    /// The app "Open in …" uses: the file's default app, or the default text editor for text.
    var defaultApp: URL?

    var defaultAppName: String? { defaultApp.map(ShelfOpenWith.name) }
}

/// Opening files (and text, saved as a temporary `.txt`) in the user's apps.
@MainActor
enum ShelfOpenWith {
    static func defaultApp(for item: ShelfItem, url: URL?) -> URL? {
        switch item.kind {
        case .file: url.flatMap(NSWorkspace.shared.urlForApplication(toOpen:))
        case .text: NSWorkspace.shared.urlForApplication(toOpen: .plainText)
        case .link(let link): NSWorkspace.shared.urlForApplication(toOpen: link)
        }
    }

    /// Every app that can open it, default first, sorted by name.
    static func apps(for item: ShelfItem, url: URL?) -> [URL] {
        let all: [URL] = switch item.kind {
        case .file: url.map(NSWorkspace.shared.urlsForApplications(toOpen:)) ?? []
        case .text: NSWorkspace.shared.urlsForApplications(toOpen: .plainText)
        case .link(let link): NSWorkspace.shared.urlsForApplications(toOpen: link)
        }
        let first = defaultApp(for: item, url: url)
        var seen = Set<String>()
        let unique = all.filter { seen.insert($0.standardizedFileURL.path).inserted && $0 != first }
        let sorted = unique.sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }
        return (first.map { [$0] } ?? []) + sorted
    }

    nonisolated static func name(of app: URL) -> String {
        let name = (try? app.resourceValues(forKeys: [.localizedNameKey]))?.localizedName
            ?? app.deletingPathExtension().lastPathComponent
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Text is handed over as a temporary `.txt` named after its first line (cleared at next launch).
    static func temporaryTextFile(_ text: String, name: String) -> URL? {
        let base = name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        let fileName = (base.isEmpty ? String(localized: "Text") : String(base.prefix(40))) + ".txt"
        guard let folder = try? ShelfSharing.makeTemporaryFolder() else { return nil }
        let url = folder.appending(path: fileName)
        do {
            try Data(text.utf8).write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

extension ShelfModule {
    /// The item open in the tall view.
    var detailItem: ShelfItem? {
        detailID.flatMap { id in store.items.first { $0.id == id } }
    }

    // MARK: Opening and closing

    /// One click (after the double-click time), Space or Return: show the item in the tall notch.
    func openDetail(_ id: UUID) {
        cancelPendingExpand()
        guard !isChoosing, prompt == nil, store.items.contains(where: { $0.id == id }) else { return }
        selection = [id]
        detailID = id
    }

    /// Back to the tiles (back arrow, Esc). The notch stays open under the normal hover rules.
    func closeDetail() {
        guard detailID != nil else { return }
        setHold { $0.detailID = nil }
    }

    /// A single click waits out the double-click time first, so a double-click can still copy.
    func scheduleExpand(_ id: UUID) {
        cancelPendingExpand()
        let delay = min(NSEvent.doubleClickInterval, 0.35)
        pendingExpand = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let notch = self.notch, notch.state == .expanded,
                  notch.layout.outlineFrame(for: .expanded).contains(NSEvent.mouseLocation) else { return }
            self.openDetail(id)
        }
    }

    func cancelPendingExpand() {
        pendingExpand?.cancel()
        pendingExpand = nil
    }

    /// Called when `detailID` changes: grow or shrink the notch and load or drop the preview.
    func detailChanged(from old: UUID?) {
        if let old {
            finishEditing(old)
            largePreview.clear()
            detailInfo = nil
        }
        guard let item = detailItem else {
            stopWatchingClicksAway()
            notch?.setTall(false)
            return
        }
        let url = item.isFile ? store.resolvedURL(for: item) : nil
        detailInfo = Self.info(for: item, url: url)
        if let url { largePreview.load(item.id, url: url, scale: 2) }
        notch?.setTall(true)
        requestFocus()
        watchClicksAway()
    }

    private static func info(for item: ShelfItem, url: URL?) -> ShelfDetailInfo {
        let app = ShelfOpenWith.defaultApp(for: item, url: url)
        switch item.kind {
        case .text(let text):
            return ShelfDetailInfo(kind: String(localized: "Text"), size: String(localized: "\(text.count) characters", comment: "Text item length"), defaultApp: app)
        case .link:
            return ShelfDetailInfo(kind: String(localized: "Link"), defaultApp: app)
        case .file:
            let path = url?.path ?? item.path
            let values = try? url?.resourceValues(forKeys: [.localizedTypeDescriptionKey, .fileSizeKey, .isDirectoryKey, .isPackageKey])
            let isFolder = values?.isDirectory == true && values?.isPackage != true
            let size = isFolder ? nil : values?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
            let kind = values?.localizedTypeDescription ?? (url == nil ? String(localized: "File not found") : String(localized: "File"))
            return ShelfDetailInfo(kind: kind, size: size, path: path, defaultApp: app)
        }
    }

    /// While the tall view is open, the notch stays open even when the pointer leaves; a click in
    /// another app, or switching to another app, closes it.
    private func watchClicksAway() {
        guard clickAwayMonitor == nil else { return }
        clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeDetail() }
        }
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.closeDetail() }
        }
    }

    func stopWatchingClicksAway() {
        if let clickAwayMonitor { NSEvent.removeMonitor(clickAwayMonitor) }
        clickAwayMonitor = nil
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        appSwitchObserver = nil
    }

    // MARK: Editing

    /// The editor's text changed: keep it in memory now, write it to disk shortly after typing stops.
    func editText(_ id: UUID, _ text: String) {
        store.update(id, kind: .text(text), save: false)
        if detailID == id { detailInfo?.size = String(localized: "\(text.count) characters", comment: "Text item length") }
        saveSoon()
    }

    /// The address field changed. Returns whether it's a valid link (only valid ones are kept).
    @discardableResult
    func editLink(_ id: UUID, _ string: String) -> Bool {
        guard let url = Self.link(from: string) else { return false }
        store.update(id, kind: .link(url), save: false)
        saveSoon()
        return true
    }

    /// A typed address, with `https://` added when it's missing. Web links need a host with a dot
    /// (or `localhost`), mail links an address.
    static func link(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let hasScheme = trimmed.contains("://") || trimmed.lowercased().hasPrefix("mailto:")
        guard let url = ShelfDropReader.webURL(hasScheme ? trimmed : "https://" + trimmed) else { return nil }
        if url.scheme?.lowercased() == "mailto" { return url.path().contains("@") ? url : nil }
        guard let host = url.host(), host == "localhost" || (host.contains(".") && !host.hasSuffix(".")) else { return nil }
        return url
    }

    private func saveSoon() {
        saveTask?.cancel()
        let store = store
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            store.saveEdits()
        }
    }

    /// Leaving the editor: write pending edits; a text item emptied in the editor is removed.
    func finishEditing(_ id: UUID) {
        saveTask?.cancel()
        saveTask = nil
        store.saveEdits()
        if let item = store.items.first(where: { $0.id == id }), case .text(let text) = item.kind,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.remove([id])
        }
    }

    // MARK: Opening in apps

    func open(_ item: ShelfItem, with app: URL?) {
        let target: URL?
        switch item.kind {
        case .file: target = store.resolvedURL(for: item)
        case .link(let url): target = url
        case .text(let text): target = ShelfOpenWith.temporaryTextFile(text, name: item.displayName)
        }
        guard let target else { return }
        guard let app else {
            NSWorkspace.shared.open(target)
            return
        }
        NSWorkspace.shared.open([target], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The "Open with" list, at the pointer.
    func showOpenWithMenu(for item: ShelfItem) {
        let url = item.isFile ? store.resolvedURL(for: item) : nil
        let apps = ShelfOpenWith.apps(for: item, url: url)
        guard !apps.isEmpty else { return }
        let defaultApp = ShelfOpenWith.defaultApp(for: item, url: url)
        let entries = apps.enumerated().map { index, app in
            ShelfMenuEntry(
                title: app == defaultApp
                    ? String(localized: "\(ShelfOpenWith.name(of: app)) (default)", comment: "Open-with menu; the default app")
                    : ShelfOpenWith.name(of: app),
                startsGroup: index == 1 && app != defaultApp && defaultApp != nil
            ) { [weak self] in self?.open(item, with: app) }
        }
        showMenu(entries)
    }
}
