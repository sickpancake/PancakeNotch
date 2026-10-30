import ConvertKit
import Darwin
import Foundation
import Testing
@testable import ConvertEngine

@MainActor
struct DocumentSafetyTests {
    /// Pages cost far more than text: 2 MiB is too big for a PDF but still fine as text or RTF.
    @Test func largeTextIsTooBigForAPDFOnly() async throws {
        let fixture = try ConvertFixture()
        for (name, other) in [("large.txt", ConvertFormat.rtf), ("large.rtf", .text), ("large.doc", .text)] {
            let url = fixture.folder.appending(path: name)
            try Data(repeating: 65, count: 2 * 1024 * 1024).write(to: url)
            let info = await ConvertProbe.info(for: url)
            #expect(ConvertCatalog.note(for: .pdf, info: info, quality: .balanced) == .tooBig)
            #expect(ConvertCatalog.note(for: other, info: info, quality: .balanced) == nil)
        }
        let huge = fixture.folder.appending(path: "huge.txt")
        try Data(repeating: 65, count: 8 * 1024 * 1024).write(to: huge)
        #expect(ConvertCatalog.note(for: .rtf, info: await ConvertProbe.info(for: huge), quality: .balanced) == .tooBig)
    }

    /// A tiny ZIP index can claim gigabytes without storing them: the check must never unpack it.
    func archive(entries: Int, unpacked: UInt32, name: String = "word/document.xml") -> Data {
        var data = Data()
        func append(_ number: UInt32, bytes: Int) {
            for shift in 0..<bytes { data.append(UInt8(truncatingIfNeeded: number >> (shift * 8))) }
        }
        for _ in 0..<entries {
            append(0x02014b50, bytes: 4)
            append(20, bytes: 2); append(20, bytes: 2)
            append(0, bytes: 2); append(8, bytes: 2)
            append(0, bytes: 4); append(0, bytes: 4)
            append(0, bytes: 4); append(unpacked, bytes: 4)
            append(UInt32(name.utf8.count), bytes: 2)
            for _ in 0..<4 { append(0, bytes: 2) }
            append(0, bytes: 4); append(0, bytes: 4)
            data.append(contentsOf: Array(name.utf8))
        }
        let length = data.count
        append(0x06054b50, bytes: 4)
        append(0, bytes: 2); append(0, bytes: 2)
        append(UInt32(entries), bytes: 2); append(UInt32(entries), bytes: 2)
        append(UInt32(length), bytes: 4); append(0, bytes: 4); append(0, bytes: 2)
        return data
    }

    @Test func zipExpansionIsCountedFromTheIndex() async throws {
        let fixture = try ConvertFixture()
        for ext in ["docx", "odt"] {
            let url = fixture.folder.appending(path: "bomb." + ext)
            for data in [archive(entries: 1, unpacked: 900_000_000), archive(entries: 1, unpacked: 900_000_000, name: "word/media/a.png"),
                         Data("broken".utf8)] {
                try data.write(to: url)
                let info = await ConvertProbe.info(for: url)
                #expect(ConvertCatalog.note(for: .text, info: info, quality: .balanced) == .tooBig)
            }
            let small = archive(entries: 300, unpacked: 120)
            try small.write(to: url)
            let size = try DocumentInput.size(of: url)
            #expect(size.text == 300 * 120 && size.other == small.count)
            #expect(ConvertCatalog.note(for: .text, info: await ConvertProbe.info(for: url), quality: .balanced) == nil)
        }
    }

    /// Opening a pipe for reading waits for a writer forever; the probe must not (the time limit fails it).
    @Test(.timeLimit(.minutes(1))) func aSymlinkToAPipeIsNotProbed() async throws {
        let fixture = try ConvertFixture()
        let pipe = fixture.folder.appending(path: "pipe")
        #expect(mkfifo(pipe.path, 0o600) == 0)
        let link = fixture.folder.appending(path: "linked.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: pipe)
        #expect(await ConvertProbe.info(for: link).isReadable == false)
        #expect(await ConvertProbe.info(for: fixture.folder).isReadable == false)
    }
}
