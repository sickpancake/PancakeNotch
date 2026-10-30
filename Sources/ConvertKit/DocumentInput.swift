import Darwin
import Foundation

/// AppKit expands text into attributed runs and layout objects. Keep that expansion inside the
/// helper's 65 MiB share: 1 MiB plain text, 256 KiB RTF/DOC, 128 KiB unpacked XML, at most 128 entries.
public enum DocumentInput {
    public static func bytes(_ url: URL, kind: ConvertKind) throws -> Int {
        let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw ConvertFailure.unreadable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else { throw ConvertFailure.unreadable }
        let limit = kind == .plainText ? 1_048_576 : 262_144
        guard info.st_size <= limit else { throw ConvertFailure.tooBig }
        guard ["docx", "odt"].contains(url.pathExtension.lowercased()) else { return Int(info.st_size) }
        // ZIP64, split archives, encrypted entries and malformed indexes are refused, not unpacked.
        let size = UInt64(info.st_size)
        let tailSize = min(size, 65_557)
        try handle.seek(toOffset: size - tailSize)
        let tail = try handle.readToEnd() ?? Data()
        func word(_ data: Data, _ offset: Int, _ count: Int) -> Int {
            guard offset >= 0, offset + count <= data.count else { return -1 }
            return (0..<count).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
        }
        guard tail.count >= 22, let end = stride(from: tail.count - 22, through: 0, by: -1).first(where: {
            word(tail, $0, 4) == 0x06054b50 && $0 + 22 + word(tail, $0 + 20, 2) == tail.count
        }) else { throw ConvertFailure.tooBig }
        let entries = word(tail, end + 10, 2)
        let length = word(tail, end + 12, 4), offset = word(tail, end + 16, 4)
        guard word(tail, end + 4, 2) == 0, word(tail, end + 6, 2) == 0,
              word(tail, end + 8, 2) == entries, entries <= 128,
              length >= 0, length <= 131_072, offset >= 0,
              UInt64(offset) + UInt64(length) == size - tailSize + UInt64(end) else { throw ConvertFailure.tooBig }
        try handle.seek(toOffset: UInt64(offset))
        let directory = try handle.read(upToCount: length) ?? Data()
        guard directory.count == length else { throw ConvertFailure.tooBig }
        var cursor = 0, total = 0
        for _ in 0..<entries {
            guard word(directory, cursor, 4) == 0x02014b50, cursor + 46 <= directory.count else { throw ConvertFailure.tooBig }
            let unpacked = word(directory, cursor + 24, 4)
            let name = word(directory, cursor + 28, 2), extra = word(directory, cursor + 30, 2), comment = word(directory, cursor + 32, 2)
            guard word(directory, cursor + 8, 2) & 1 == 0, word(directory, cursor + 34, 2) == 0,
                  unpacked >= 0, unpacked <= 131_072 - total else { throw ConvertFailure.tooBig }
            total += unpacked
            cursor += 46 + name + extra + comment
            guard cursor <= directory.count else { throw ConvertFailure.tooBig }
        }
        guard cursor == directory.count else { throw ConvertFailure.tooBig }
        return total
    }
}
