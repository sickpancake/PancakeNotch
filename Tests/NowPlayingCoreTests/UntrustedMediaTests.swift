import AppKit
import ImageIO
import os
import Testing
@testable import NowPlayingCore

struct UntrustedMediaTests {
    private func line(_ payload: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: ["type": "data", "payload": payload])
        data.append(10)
        return data
    }

    @Test func oversizedLinesAreDiscardedThroughTheirNewline() throws {
        var parser = AdapterStreamParser()
        #expect(parser.feed(Data(repeating: 65, count: AdapterStreamParser.maxLineLength + 1), receivedAt: .now) == nil)
        // This valid-looking suffix still belongs to the rejected line.
        #expect(parser.feed(try line(["title": "forged suffix"]), receivedAt: .now) == nil)
        #expect(parser.feed(try line(["title": "next line"]), receivedAt: .now)?.track?.title == "next line")
        var singleChunk = Data(repeating: 65, count: AdapterStreamParser.maxLineLength + 1)
        singleChunk.append(10)
        singleChunk.append(try line(["title": "after huge line"]))
        #expect(parser.feed(singleChunk, receivedAt: .now)?.track?.title == "after huge line")
    }

    @Test func oversizedArtworkIsNeverDecoded() throws {
        var parser = AdapterStreamParser()
        var decoded = false
        parser.makeArtwork = { _ in decoded = true; return nil }
        let update = parser.feed(try line(["title": "song", "artworkData": String(repeating: "A", count: AdapterStreamParser.maxArtworkLength + 4)]), receivedAt: .now)
        #expect(update?.track?.title == "song")
        #expect(update?.track?.artworkID == nil)
        #expect(!decoded)
    }

    @Test func artworkHeadersAreCheckedBeforeDecoding() throws {
        // A small valid PNG with only IHDR dimensions changed; CRC is updated too.
        let original = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aG1cAAAAASUVORK5CYII="))
        #expect(ArtworkImage.accepts(width: 4000, height: 4000))
        #expect(ArtworkImage.accepts(width: 8192, height: 1))
        #expect(!ArtworkImage.accepts(width: .max, height: .max))
        for (width, height) in [(60_000, 60_000), (8193, 1), (4096, 4096)] {
            var data = original
            for (offset, value) in [(16, width), (20, height)] {
                for i in 0..<4 { data[offset + i] = UInt8(truncatingIfNeeded: value >> ((3 - i) * 8)) }
            }
            var crc = UInt32.max
            for byte in data[12..<29] {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = crc & 1 != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
            }
            crc ^= UInt32.max
            for i in 0..<4 { data[29 + i] = UInt8(truncatingIfNeeded: crc >> ((3 - i) * 8)) }
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            #expect(properties[kCGImagePropertyPixelWidth] == nil || properties[kCGImagePropertyPixelWidth] as? Int == width)
            #expect(!ArtworkImage.accepts(width: width, height: height))
            #expect(ArtworkImage.downsample(data) == nil)
        }
    }

    @Test func extremeNumbersAreRejected() throws {
        for value in [Double.greatestFiniteMagnitude, Double(Int.max), -1, 1.5] {
            var parser = AdapterStreamParser()
            let track = try #require(parser.feed(try line(["title": "song", "shuffleMode": value, "repeatMode": value, "processIdentifier": value]), receivedAt: .now)?.track)
            #expect(track.shuffle == nil && track.repeatMode == nil && track.processID == nil)
        }
        var state = AdapterState()
        state.values = ["title": .string("song"), "shuffleMode": .number(.nan), "repeatMode": .number(.infinity), "processIdentifier": .number(.infinity)]
        let track = try #require(state.track(receivedAt: .now))
        #expect(track.shuffle == nil && track.repeatMode == nil && track.processID == nil)
    }

    @MainActor @Test func streamDeliveryKeepsOnlyTheLatestUpdate() async throws {
        let titles = OSAllocatedUnfairLock(initialState: [String]())
        let reader = AdapterStreamReader { update in titles.withLock { $0.append(update.track?.title ?? "") } }
        for index in 0..<500 { reader.consume(try line(["title": "song \(index)"])) }
        #expect(titles.withLock { $0.isEmpty })
        // The main queue runs in order, so the one delivery queued above has run once this has.
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        #expect(titles.withLock { $0 } == ["song 499"])
    }
}
