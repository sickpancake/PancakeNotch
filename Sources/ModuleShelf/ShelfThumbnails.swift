import AppKit
import Observation
import QuickLookThumbnailing

/// Small previews for file tiles, made by macOS's Quick Look service (outside our process).
///
/// Memory: one 56 pt @2x image per file item, so at most 20 (~1–2 MB). They exist only while the notch
/// is open; `clear()` drops them and cancels pending requests when it closes (ADR-0006).
@MainActor
@Observable
final class ShelfThumbnails {
    static let pointSize = CGSize(width: 56, height: 56)

    private(set) var images: [UUID: NSImage] = [:]
    @ObservationIgnored private var requests: [UUID: QLThumbnailGenerator.Request] = [:]
    @ObservationIgnored private var generation = 0

    /// Requests previews for file items that don't have one yet.
    func load(_ items: [ShelfItem], scale: CGFloat) {
        let current = generation
        for item in items where images[item.id] == nil && requests[item.id] == nil {
            guard let url = item.fileURL else { continue }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: Self.pointSize, scale: scale, representationTypes: .all)
            requests[item.id] = request
            let id = item.id
            Self.generate(request) { [weak self] image in
                Task { @MainActor in
                    // Skip results for items removed (or a notch closed) in the meantime.
                    guard let self, self.generation == current, self.requests[id] != nil else { return }
                    self.requests[id] = nil
                    self.images[id] = image.map { NSImage(cgImage: $0, size: Self.pointSize) }
                        ?? Self.smallIcon(forFile: url.path)
                }
            }
        }
    }

    /// Sets previews directly (off-screen snapshots render synchronously).
    func preload(_ images: [UUID: NSImage]) {
        self.images.merge(images) { $1 }
    }

    /// Forgets previews of removed items.
    func keepOnly(_ ids: Set<UUID>) {
        for id in images.keys where !ids.contains(id) { images[id] = nil }
        for (id, request) in requests where !ids.contains(id) {
            QLThumbnailGenerator.shared.cancel(request)
            requests[id] = nil
        }
    }

    /// The Finder icon at tile size only, not every size the full icon carries.
    static func smallIcon(forFile path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        let small = NSImage(size: pointSize)
        var rect = CGRect(origin: .zero, size: CGSize(width: pointSize.width * 2, height: pointSize.height * 2))
        if let cgImage = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            small.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        }
        return small
    }

    /// Drops every preview and cancels pending work (the notch closed).
    func clear() {
        generation += 1
        for request in requests.values { QLThumbnailGenerator.shared.cancel(request) }
        requests = [:]
        images = [:]
    }

    /// `nonisolated` so Quick Look's completion runs on its own queue, not the main actor.
    nonisolated static func generate(_ request: QLThumbnailGenerator.Request, done: @escaping @Sendable (CGImage?) -> Void) {
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            done(representation?.cgImage)
        }
    }
}

/// The big preview in the tall notch, for the one file being shown. Made by Quick Look out of process,
/// like the tiles, and dropped as soon as the file is closed (ADR-0006): at most one ~0.6 MB image.
@MainActor
@Observable
final class ShelfLargePreview {
    static let pointSize = CGSize(width: 200, height: 200)

    private(set) var image: NSImage?
    @ObservationIgnored private var request: QLThumbnailGenerator.Request?
    @ObservationIgnored private var generation = 0

    func load(_ id: UUID, url: URL, scale: CGFloat) {
        clear()
        let request = QLThumbnailGenerator.Request(fileAt: url, size: Self.pointSize, scale: scale, representationTypes: .all)
        self.request = request
        let current = generation
        ShelfThumbnails.generate(request) { [weak self] cgImage in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.request = nil
                self.image = cgImage.map { NSImage(cgImage: $0, size: CGSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale)) }
                    ?? Self.icon(forFile: url.path)
            }
        }
    }

    /// The Finder icon at preview size only.
    private static func icon(forFile path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        let image = NSImage(size: pointSize)
        var rect = CGRect(origin: .zero, size: CGSize(width: pointSize.width * 2, height: pointSize.height * 2))
        if let cgImage = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        }
        return image
    }

    func clear() {
        generation += 1
        if let request { QLThumbnailGenerator.shared.cancel(request) }
        request = nil
        image = nil
    }

    /// Sets the image directly (off-screen snapshots).
    func preload(_ image: NSImage) {
        self.image = image
    }
}
