import AppKit
import os
import Quartz

/// AirDrop and the Share menu. Both run in system processes; we only hand over URLs and text.
@MainActor
final class ShelfSharing: NSObject, NSSharingServiceDelegate, @preconcurrency NSSharingServicePickerDelegate {
    /// Called when sharing is over (sent, failed or cancelled), so the notch may close again.
    var onFinish: (() -> Void)?
    /// Kept alive until sharing ends: AppKit holds both only weakly through their delegates.
    private var service: NSSharingService?
    private var picker: NSSharingServicePicker?
    /// Temporary content sent from the AirDrop zone, deleted once it's sent.
    private var temporaryFolders: [URL] = []
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "shelf")

    /// Whether a drag's content can be AirDropped: files, promised files, images, links, or text (sent as `.txt`).
    static func canAirDrop(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else { return false }
        let promises = Set(NSFilePromiseReceiver.readableDraggedTypes)
        return types.contains { [.fileURL, .URL, .png, .tiff, .string].contains($0) || promises.contains($0.rawValue) }
    }

    private static var temporaryRoot: URL {
        FileManager.default.temporaryDirectory.appending(path: "PancakeNotch", directoryHint: .isDirectory)
    }

    /// A fresh temporary folder for content that's only passing through (AirDrop zone, promised files).
    static func makeTemporaryFolder() throws -> URL {
        let folder = temporaryRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Clears leftovers from an earlier run (called at launch, before anything is in flight).
    static func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    /// Deletes `folders` when the current sharing ends.
    func deleteWhenFinished(_ folders: [URL]) {
        temporaryFolders += folders
    }

    func airDrop(_ items: [Any]) {
        let items = items.compactMap(airDroppable)
        guard !items.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: items) else {
            logger.error("AirDrop can't send these items")
            NSSound.beep()
            finish()
            return
        }
        service.delegate = self
        self.service = service
        // We're an accessory app that's rarely in front: without this the AirDrop window opens behind
        // the active app, so nothing seems to happen. Wait for a closing menu to finish first.
        NSApp.activate()
        Task { @MainActor in
            service.perform(withItems: items)
        }
    }

    /// AirDrop takes files and links but not plain text: text goes as a `.txt` file.
    private func airDroppable(_ item: Any) -> Any? {
        guard let text = item as? String else { return item }
        let name = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        guard let url = ShelfOpenWith.temporaryTextFile(text, name: name) else { return nil }
        deleteWhenFinished([url.deletingLastPathComponent()])
        return url
    }

    func share(_ items: [Any], from view: NSView) {
        guard !items.isEmpty else {
            finish()
            return
        }
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        self.picker = picker
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    private func finish() {
        service = nil
        picker = nil
        for folder in temporaryFolders { try? FileManager.default.removeItem(at: folder) }
        temporaryFolders = []
        onFinish?()
    }

    // MARK: NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finish()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        finish()
    }

    // MARK: NSSharingServicePickerDelegate

    /// Once a service is picked it runs in its own window, so the notch doesn't need to stay open.
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        finish()
    }
}

/// Quick Look for shelf files. The tile views pass control of the shared preview panel to this object.
@MainActor
final class ShelfQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private(set) var urls: [URL] = []
    /// Called when the preview panel closes.
    var onEnd: (() -> Void)?

    func show(_ urls: [URL]) {
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else {
            onEnd?()
            return
        }
        // Set directly too, in case no tile is in the responder chain to take control.
        panel.dataSource = self
        panel.delegate = self
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Called from a tile view's `beginPreviewPanelControl`.
    func begin(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    /// Called from a tile view's `endPreviewPanelControl`.
    func end(_ panel: QLPreviewPanel) {
        guard panel.dataSource === self else { return }
        panel.dataSource = nil
        panel.delegate = nil
        onEnd?()
    }

    /// Closes the panel if it's showing our files (the Shelf is going away; the panel doesn't retain us).
    func closeIfShowing() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
              panel.dataSource === self else { return }
        end(panel)
        panel.orderOut(nil)
    }

    /// The panel closed (also when no tile ever took control of it).
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let panel = QLPreviewPanel.shared() else { return }
            end(panel)
        }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}
