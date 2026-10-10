import Foundation

/// Something parked on the Shelf (ADR-0013).
public struct ShelfItem: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        /// A file or folder, kept as a bookmark so it follows moves and renames. `owned` files live in the
        /// Shelf's own folder (promised files, dropped image data, long text) and are deleted with the item.
        case file(bookmark: Data, owned: Bool)
        case text(String)
        case link(URL)
    }

    public let id: UUID
    public var kind: Kind
    /// Last known path of a file item, refreshed whenever the notch opens.
    public var path: String?
    public let addedAt: Date

    public init(id: UUID = UUID(), kind: Kind, path: String? = nil, addedAt: Date) {
        self.id = id
        self.kind = kind
        self.path = path
        self.addedAt = addedAt
    }

    /// Identifies the same content when it's dropped again (duplicates).
    var key: String {
        switch kind {
        case .file: "file:" + (path ?? id.uuidString)
        case .text(let text): "text:" + text
        case .link(let url): "link:" + url.absoluteString
        }
    }

    /// Short name shown under the tile.
    public var displayName: String {
        switch kind {
        case .file:
            return path.map { FileManager.default.displayName(atPath: $0) } ?? String(localized: "File")
        case .text(let text):
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            return String(line.trimmingCharacters(in: .whitespaces).prefix(60))
        case .link(let url):
            return url.host(percentEncoded: false) ?? url.absoluteString
        }
    }

    public var isFile: Bool {
        if case .file = kind { return true }
        return false
    }

    public var isOwnedFile: Bool {
        if case .file(_, let owned) = kind { return owned }
        return false
    }

    /// The file URL from the last known path (no disk access).
    public var fileURL: URL? {
        guard isFile, let path else { return nil }
        return URL(fileURLWithPath: path)
    }
}

/// Content offered to the Shelf by a drop, before it becomes a `ShelfItem`.
public enum ShelfInput: Equatable, Sendable {
    case file(URL, owned: Bool)
    case text(String)
    case link(URL)

    var key: String {
        switch self {
        case .file(let url, _): "file:" + url.resolvingSymlinksInPath().path
        case .text(let text): "text:" + text
        case .link(let url): "link:" + url.absoluteString
        }
    }
}
