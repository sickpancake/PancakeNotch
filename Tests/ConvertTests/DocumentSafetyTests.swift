import ConvertKit
import Darwin
import Foundation
import Testing
@testable import ConvertEngine

@MainActor
struct DocumentSafetyTests {
    @Test func largeTextAndRichTextAreRefusedBeforeLoading() async throws {
        let fixture = try ConvertFixture()
        for name in ["large.txt", "large.rtf", "large.doc"] {
            let url = fixture.folder.appending(path: name)
            try Data(repeating: 65, count: 2 * 1024 * 1024).write(to: url)
            let info = await ConvertProbe.info(for: url)
            #expect(ConvertCatalog.note(for: .pdf, info: info, quality: .balanced) == .tooBig)
            #expect(throws: ConvertFailure.tooBig) { try DocumentConversion.read(url, kind: ConvertKind(url: url)!) }
        }
    }

    /// A tiny ZIP index can claim gigabytes without storing them: the check must never unpack it.
    func archive(entries: Int, unpacked: UInt32) -> Data {
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
            for _ in 0..<5 { append(0, bytes: 2) }
            append(0, bytes: 4); append(0, bytes: 4)
        }
        let length = data.count
        append(0x06054b50, bytes: 4)
        append(0, bytes: 2); append(0, bytes: 2)
        append(UInt32(entries), bytes: 2); append(UInt32(entries), bytes: 2)
        append(UInt32(length), bytes: 4); append(0, bytes: 4); append(0, bytes: 2)
        return data
    }

    @Test func zipExpansionAndEntryCountsAreCapped() async throws {
        let fixture = try ConvertFixture()
        for ext in ["docx", "odt"] {
            let url = fixture.folder.appending(path: "bomb." + ext)
            for data in [archive(entries: 1, unpacked: 900_000_000), archive(entries: 129, unpacked: 1), Data("broken".utf8)] {
                try data.write(to: url)
                #expect(throws: ConvertFailure.tooBig) { try DocumentInput.bytes(url, kind: .wordDocument) }
                let info = await ConvertProbe.info(for: url)
                #expect(ConvertCatalog.note(for: .text, info: info, quality: .balanced) == .tooBig)
            }
            try archive(entries: 1, unpacked: 120).write(to: url)
            #expect(try DocumentInput.bytes(url, kind: .wordDocument) == 120)
        }
    }

    @Test func aSymlinkToAPipeIsNotProbed() async throws {
        let fixture = try ConvertFixture()
        let pipe = fixture.folder.appending(path: "pipe")
        #expect(mkfifo(pipe.path, 0o600) == 0)
        let link = fixture.folder.appending(path: "linked.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: pipe)
        let start = Date()
        #expect(await ConvertProbe.info(for: link).isReadable == false)
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(await ConvertProbe.info(for: fixture.folder).isReadable == false)
    }
}
