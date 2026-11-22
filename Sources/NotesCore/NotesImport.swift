import Foundation
import UniformTypeIdentifiers

/// Reads dropped text files as note text.
public enum NotesImport {
    /// Bigger files stay on the Shelf: a note is for a few paragraphs, not a book.
    public static let maxFileBytes = 256 * 1024

    /// Whether a file is plain text a note can hold (`.txt`, `.text`, `.md` and other plain text).
    public static func isTextFile(_ url: URL) -> Bool {
        guard url.isFileURL, !url.hasDirectoryPath else { return false }
        if ["txt", "text", "md", "markdown"].contains(url.pathExtension.lowercased()) { return true }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .plainText) && !type.conforms(to: .sourceCode)
    }

    /// The text in a plain text file, or nil when it's too big, empty or not readable text.
    public static func text(of url: URL) -> String? {
        guard isTextFile(url),
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= maxFileBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
