import Foundation
import ImageIO
import Testing
@testable import ConvertEngine

/// The GIF writer Convert uses instead of ImageIO's (which holds every frame until the end).
struct GIFWriterTests {
    /// GIF's LZW read back, as a GIF reader does it.
    static func decode(_ data: Data) -> [UInt8] {
        // Join the blocks (a length byte, then that many bytes) up to the empty one.
        var bytes: [UInt8] = []
        var index = data.startIndex
        while index < data.endIndex, data[index] != 0 {
            let count = Int(data[index])
            bytes += data[(index + 1)...(index + count)]
            index += count + 1
        }
        var output: [UInt8] = []
        var table: [[UInt8]] = (0..<256).map { [UInt8($0)] } + [[], []]
        var size = 9, bitPosition = 0
        var previous: [UInt8]?
        while true {
            var code = 0
            for bit in 0..<size {
                let place = bitPosition + bit
                guard place / 8 < bytes.count else { return output }
                code |= Int(bytes[place / 8] >> (place % 8) & 1) << bit
            }
            bitPosition += size
            if code == 256 {
                table = (0..<256).map { [UInt8($0)] } + [[], []]
                size = 9
                previous = nil
                continue
            }
            if code == 257 { return output }
            let entry: [UInt8]
            if code < table.count {
                entry = table[code]
                if let previous { table.append(previous + [entry[0]]) }
            } else {
                entry = previous! + [previous![0]]
                table.append(entry)
            }
            output += entry
            previous = entry
            if table.count == 1 << size, size < 12 { size += 1 }
        }
    }

    @Test(arguments: [0, 1, 2, 3])
    func lzwRoundTrips(pattern: Int) {
        var generator = SystemRandomNumberGenerator()
        let count = 300 * 300
        let indices: [UInt8] = switch pattern {
        case 0: (0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) } // the table fills often
        case 1: [UInt8](repeating: 7, count: count) // long runs
        case 2: (0..<count).map { UInt8($0 / 37 % 5) } // a few colours in stripes
        default: [42] // one pixel
        }
        var data = Data()
        GIFLZW().encode(indices, into: &data)
        #expect(Self.decode(data) == indices)
    }

    @Test func framesReadBackWithTheirColoursAndTiming() throws {
        let fixture = try ConvertFixture()
        let url = fixture.url("a.gif")
        let width = 40, height = 30
        let writer = try GIFWriter(url: url, width: width, height: height)
        // Four flat colours per frame, BGRA: each comes back exactly.
        let colours: [[UInt8]] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [40, 80, 120, 255]]
        for frame in 0..<3 {
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let colour = colours[(x / 10 + frame) % 4]
                    pixels.replaceSubrange((y * width + x) * 4..<((y * width + x) * 4 + 4), with: colour)
                }
            }
            try pixels.withUnsafeBytes { try writer.add(bgra: $0.baseAddress!, bytesPerRow: width * 4, time: Double(frame) / 12) }
        }
        try writer.finish(end: 0.25)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 3)
        let first = try #require(PictureCheck(url, frame: 0))
        #expect(first.width == width && first.height == height)
        // Blue (BGRA 255, 0, 0) in the first column of frame 0, green in the next.
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let rgba = Self.rgba(image)
        #expect(Array(rgba[0..<3]) == [0, 0, 255])
        #expect(Array(rgba[(10 * 4)..<(10 * 4 + 3)]) == [0, 255, 0])
        // 12 frames a second: 8 or 9 hundredths each, adding up to the time.
        let delays = (0..<3).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            return gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
        }
        #expect(delays.allSatisfy { (0.079...0.091).contains($0) })
    }

    @Test func manyColoursKeepTheirLook() throws {
        let fixture = try ConvertFixture()
        let url = fixture.url("b.gif")
        let width = 128, height = 64
        let writer = try GIFWriter(url: url, width: width, height: height)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                pixels[(y * width + x) * 4] = UInt8(x * 2)
                pixels[(y * width + x) * 4 + 1] = UInt8(y * 4)
                pixels[(y * width + x) * 4 + 2] = UInt8((x + y) % 256)
            }
        }
        try pixels.withUnsafeBytes { try writer.add(bgra: $0.baseAddress!, bytesPerRow: width * 4, time: 0) }
        try writer.finish(end: 1)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let rgba = Self.rgba(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
        // 256 colours for a smooth gradient: every pixel lands close to where it was.
        var worst = 0
        for index in 0..<(width * height) {
            let error = abs(Int(rgba[index * 4]) - Int(pixels[index * 4 + 2]))
                + abs(Int(rgba[index * 4 + 1]) - Int(pixels[index * 4 + 1]))
                + abs(Int(rgba[index * 4 + 2]) - Int(pixels[index * 4]))
            worst = max(worst, error)
        }
        #expect(worst < 60)
    }

    @Test func turnsFollowTheVideo() {
        #expect(VideoConversion.quarterTurns(.identity) == 0)
        #expect(VideoConversion.quarterTurns(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)) == 1)
        #expect(VideoConversion.quarterTurns(CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080)) == 2)
        #expect(VideoConversion.quarterTurns(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920)) == 3)
    }

    static func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }
}
