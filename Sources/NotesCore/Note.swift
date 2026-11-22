import Foundation

/// One note: plain text kept for later, typed in the notch or made from dropped text.
public struct Note: Codable, Identifiable, Hashable, Sendable {
    /// Where a note's text came from.
    public enum Source: Codable, Hashable, Sendable {
        /// Typed in the notch.
        case typed
        /// Text dropped on the Notes page.
        case dropped
        /// A text file dropped on the Notes page.
        case file(name: String)
        /// A text file or text dropped on the Shelf, with the file's name when it was a file.
        case shelf(fileName: String?)
    }

    public let id: UUID
    public var text: String
    public let created: Date
    public var modified: Date
    public var isPinned: Bool
    public var source: Source

    public init(id: UUID = UUID(), text: String, created: Date, modified: Date? = nil, isPinned: Bool = false, source: Source = .typed) {
        self.id = id
        self.text = text
        self.created = created
        self.modified = modified ?? created
        self.isPinned = isPinned
        self.source = source
    }

    /// The first line with text in it, or nothing for an empty note.
    public var title: String {
        lines.first ?? ""
    }

    /// The lines after the title, joined by spaces, for one-line previews.
    public var preview: String {
        lines.dropFirst().joined(separator: " ")
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lines: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
