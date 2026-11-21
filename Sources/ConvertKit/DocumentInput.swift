import Darwin
import Foundation

/// How much a text document holds, for Convert's estimate (`ConvertLimits`): read from the file's size or,
/// for Word and ODT files, from the ZIP's index, so a tiny file that unpacks to gigabytes is caught
/// without unpacking anything.
public enum DocumentInput {
    public struct Size: Equatable, Sendable {
        /// The text AppKit lays out: the file itself, or a ZIP's unpacked XML.
        public var text: Int
        /// Everything else it may hold while reading: the file, plus a ZIP's unpacked pictures and other parts.
        public var other: Int
    }

    public static func size(of url: URL) throws -> Size {
        let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw ConvertFailure.unreadable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else { throw ConvertFailure.unreadable }
        let size = Int(info.st_size)
        guard ["docx", "odt"].contains(url.pathExtension.lowercased()) else { return Size(text: size, other: size) }
        let (text, other) = try unpacked(handle, size: UInt64(size))
        return Size(text: text, other: size + other)
    }

    /// A ZIP's unpacked XML and other bytes, from its central directory. ZIP64, split archives, encrypted
    /// entries and malformed indexes are refused as too big, not unpacked.
    private static func unpacked(_ handle: FileHandle, size: UInt64) throws -> (xml: Int, other: Int) {
        let tailSize = min(size, 65_557)
        try handle.seek(toOffset: size - tailSize)
        let tail = try handle.readToEnd() ?? Data()
        func word(_ data: Data, _ offset: Int, _ count: Int) -> Int {
            guard offset >= 0, offset + count <= data.count else { return -1 }
            return (0..<count).reduce(0) { $0 | Int(data[data.startIndex + offset + $1]) << (8 * $1) }
        }
        guard tail.count >= 22, let end = stride(from: tail.count - 22, through: 0, by: -1).first(where: {
            word(tail, $0, 4) == 0x06054b50 && $0 + 22 + word(tail, $0 + 20, 2) == tail.count
        }) else { throw ConvertFailure.tooBig }
        let entries = word(tail, end + 10, 2)
        let length = word(tail, end + 12, 4), offset = word(tail, end + 16, 4)
        // A full index of 65,535 entries with long names fits in about 20 MiB; anything longer is lying.
        guard word(tail, end + 4, 2) == 0, word(tail, end + 6, 2) == 0, word(tail, end + 8, 2) == entries,
              length >= 0, length <= 20 * 1_048_576, offset >= 0,
              UInt64(offset) + UInt64(length) == size - tailSize + UInt64(end) else { throw ConvertFailure.tooBig }
        try handle.seek(toOffset: UInt64(offset))
        let directory = try handle.read(upToCount: length) ?? Data()
        guard directory.count == length else { throw ConvertFailure.tooBig }
        var cursor = 0, xml = 0, other = 0
        for _ in 0..<entries {
            guard word(directory, cursor, 4) == 0x02014b50, cursor + 46 <= directory.count else { throw ConvertFailure.tooBig }
            let unpacked = word(directory, cursor + 24, 4)
            let name = word(directory, cursor + 28, 2), extra = word(directory, cursor + 30, 2), comment = word(directory, cursor + 32, 2)
            let nameStart = directory.startIndex + cursor + 46
            guard word(directory, cursor + 8, 2) & 1 == 0, word(directory, cursor + 34, 2) == 0,
                  unpacked >= 0, cursor + 46 + name <= directory.count else { throw ConvertFailure.tooBig }
            let path = String(decoding: directory[nameStart..<(nameStart + name)], as: UTF8.self).lowercased()
            if [".xml", ".rels", ".rdf"].contains(where: path.hasSuffix) { xml += unpacked } else { other += unpacked }
            cursor += 46 + name + extra + comment
            guard cursor <= directory.count else { throw ConvertFailure.tooBig }
        }
        guard cursor == directory.count else { throw ConvertFailure.tooBig }
        return (xml, other)
    }
}
