import Foundation
import UniformTypeIdentifiers

/// Reads dropped text files as note text.
public enum NotesImport {
    /// Bigger files stay on the Shelf: a note is for a few paragraphs, not a book.
    public static let maxFileBytes = 256 * 1024

    /// The file extensions that become notes. Other plain text (`.csv`, `.log`, …) is usually data to
    /// pass on somewhere else, so it stays a file.
    public static let textExtensions: Set<String> = ["txt", "text", "md", "markdown"]

    /// Whether a file is a text file a note can hold (`.txt`, `.text`, `.md`, `.markdown`).
    public static func isTextFile(_ url: URL) -> Bool {
        url.isFileURL && !url.hasDirectoryPath && textExtensions.contains(url.pathExtension.lowercased())
    }

    /// The text in a plain text file, or nil when it's too big, empty or not readable text.
    public static func text(of url: URL) -> String? {
        guard isTextFile(url),
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= maxFileBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        guard let text = decode(data), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// UTF-8, UTF-16 with a byte order mark, or else Windows Latin 1 (what older editors save). Data with
    /// NUL bytes isn't text.
    static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        let bom = Array(data.prefix(2))
        if bom == [0xFE, 0xFF] || bom == [0xFF, 0xFE] { return String(data: data, encoding: .utf16) }
        guard !data.contains(0) else { return nil }
        return String(data: data, encoding: .windowsCP1252)
    }
}
