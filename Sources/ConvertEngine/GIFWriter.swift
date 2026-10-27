import ConvertKit
import Foundation

/// A GIF written to disk a frame at a time. ImageIO's GIF writer keeps every frame until the end, which
/// a 15-second clip can't afford (about 250 MB measured); here only the frame being written is held.
/// Each frame gets its own 256-colour palette (median cut) and a light ordered dither, which stays still
/// from frame to frame instead of crawling.
final class GIFWriter {
    let width: Int
    let height: Int
    private let handle: FileHandle
    private let quantizer: GIFQuantizer
    private let lzw = GIFLZW()
    /// The last frame, waiting for the next one to know how long it shows.
    private var pending: Data?
    private var pendingTime = 0.0
    private var firstTime: Double?

    init(url: URL, width: Int, height: Int) throws {
        guard (1...0xFFFF).contains(width), (1...0xFFFF).contains(height),
              FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { throw ConvertFailure.cantWrite }
        self.width = width
        self.height = height
        self.handle = handle
        quantizer = GIFQuantizer(pixels: width * height)
        var header = Data("GIF89a".utf8)
        header.appendLittleEndian(width)
        header.appendLittleEndian(height)
        header.append(contentsOf: [0x00, 0x00, 0x00]) // no global palette; every frame brings its own
        header.append(contentsOf: [0x21, 0xFF, 0x0B])
        header.append(Data("NETSCAPE2.0".utf8))
        header.append(contentsOf: [0x03, 0x01, 0x00, 0x00, 0x00]) // loop forever
        try write(header)
    }

    deinit { try? handle.close() }

    /// A frame of BGRA pixels, rows `bytesPerRow` apart, shown from `time` (seconds) until the next.
    func add(bgra: UnsafeRawPointer, bytesPerRow: Int, time: Double) throws {
        try flushPending(until: time)
        let palette = quantizer.quantize(bgra: bgra.assumingMemoryBound(to: UInt8.self), width: width, height: height, bytesPerRow: bytesPerRow)
        var frame = Data()
        frame.reserveCapacity(width * height / 2 + 1024)
        // Graphic control: leave the frame in place, delay filled in when the next frame comes.
        frame.append(contentsOf: [0x21, 0xF9, 0x04, 0x04, 0x00, 0x00, 0x00, 0x00])
        frame.append(0x2C)
        frame.appendLittleEndian(0)
        frame.appendLittleEndian(0)
        frame.appendLittleEndian(width)
        frame.appendLittleEndian(height)
        frame.append(0x87) // a local palette of 256 colours
        frame.append(contentsOf: palette)
        frame.append(0x08) // LZW minimum code size
        lzw.encode(quantizer.indices, into: &frame)
        if firstTime == nil { firstTime = time }
        pending = frame
        pendingTime = time
    }

    /// Writes the last frame, shown until `end` (seconds), and closes the GIF.
    func finish(end: Double) throws {
        try flushPending(until: max(end, pendingTime + 1 / 12))
        try write(Data([0x3B]))
        try handle.close()
    }

    private func flushPending(until time: Double) throws {
        guard var frame = pending, let firstTime else { return }
        // Rounded from the start, so the hundredths left over by one frame go to the next and the
        // GIF keeps time. Under 2 hundredths, browsers slow a frame down to 10.
        let delay = max(2, centiseconds(time - firstTime) - centiseconds(pendingTime - firstTime))
        frame[4] = UInt8(delay & 0xFF)
        frame[5] = UInt8(min(delay >> 8, 0xFF))
        try write(frame)
        pending = nil
    }

    private func centiseconds(_ seconds: Double) -> Int { Int((seconds * 100).rounded()) }

    private func write(_ data: Data) throws {
        do { try handle.write(contentsOf: data) } catch { throw ConvertFailure.cantWrite }
    }
}

/// Median cut over a 15-bit colour histogram, then each pixel, nudged by a 4×4 ordered dither, mapped to
/// the nearest palette colour (worked out once per 15-bit colour per frame).
final class GIFQuantizer {
    private(set) var indices: [UInt8]
    private var palette = [UInt8](repeating: 0, count: 768)
    private var colours = 0
    private var counts = [Int](repeating: 0, count: 1 << 15)
    private var sums = [Int](repeating: 0, count: 3 << 15)
    private var nearest = [UInt16](repeating: .max, count: 1 << 15)
    private var bins: [Int] = []

    /// The dither's nudge per position, in 8-bit steps: about one 15-bit step from end to end.
    private static let dither: [Int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 * 2 - 15) * 8 / 30 }

    init(pixels: Int) {
        indices = [UInt8](repeating: 0, count: pixels)
    }

    /// The frame's palette (768 bytes, unused entries black); `indices` then holds each pixel's entry.
    func quantize(bgra: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> [UInt8] {
        countColours(bgra, width: width, height: height, bytesPerRow: bytesPerRow)
        cutPalette()
        mapPixels(bgra, width: width, height: height, bytesPerRow: bytesPerRow)
        return palette
    }

    private static func key(_ r: Int, _ g: Int, _ b: Int) -> Int { (r >> 3) << 10 | (g >> 3) << 5 | b >> 3 }

    private func countColours(_ bgra: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) {
        for i in counts.indices { counts[i] = 0 }
        for i in sums.indices { sums[i] = 0 }
        counts.withUnsafeMutableBufferPointer { counts in
            sums.withUnsafeMutableBufferPointer { sums in
                for y in 0..<height {
                    let row = bgra + y * bytesPerRow
                    for x in 0..<width {
                        let b = Int(row[x * 4]), g = Int(row[x * 4 + 1]), r = Int(row[x * 4 + 2])
                        let key = Self.key(r, g, b)
                        counts[key] += 1
                        sums[key * 3] += r
                        sums[key * 3 + 1] += g
                        sums[key * 3 + 2] += b
                    }
                }
            }
        }
    }

    private struct Box {
        var start: Int
        var end: Int
        var count: Int
        var axis: Int
        var range: Int
        var score: Int { range > 0 ? count * range : -1 }
    }

    private static func component(_ key: Int, _ axis: Int) -> Int { key >> (10 - axis * 5) & 31 }

    private func box(_ start: Int, _ end: Int) -> Box {
        var low = [31, 31, 31], high = [0, 0, 0], count = 0
        for key in bins[start..<end] {
            count += counts[key]
            for axis in 0..<3 {
                let value = Self.component(key, axis)
                low[axis] = min(low[axis], value)
                high[axis] = max(high[axis], value)
            }
        }
        let ranges = (0..<3).map { high[$0] - low[$0] }
        let axis = ranges.indices.max { ranges[$0] < ranges[$1] } ?? 0
        return Box(start: start, end: end, count: count, axis: axis, range: ranges[axis])
    }

    private func cutPalette() {
        bins = counts.indices.filter { counts[$0] > 0 }
        var boxes = bins.isEmpty ? [] : [box(0, bins.count)]
        while boxes.count < 256, let index = boxes.indices.max(by: { boxes[$0].score < boxes[$1].score }), boxes[index].score > 0 {
            let cut = boxes[index]
            bins[cut.start..<cut.end].sort { Self.component($0, cut.axis) < Self.component($1, cut.axis) }
            // Split where half the pixels are on each side, keeping at least one colour on each.
            var running = 0, split = cut.start + 1
            for i in cut.start..<(cut.end - 1) {
                running += counts[bins[i]]
                if running * 2 >= cut.count { split = i + 1; break }
            }
            boxes[index] = box(cut.start, split)
            boxes.append(box(split, cut.end))
        }
        for i in palette.indices { palette[i] = 0 }
        colours = max(1, boxes.count)
        for (entry, box) in boxes.enumerated() {
            var r = 0, g = 0, b = 0
            for key in bins[box.start..<box.end] {
                r += sums[key * 3]
                g += sums[key * 3 + 1]
                b += sums[key * 3 + 2]
            }
            let count = max(1, box.count)
            palette[entry * 3] = UInt8((r + count / 2) / count)
            palette[entry * 3 + 1] = UInt8((g + count / 2) / count)
            palette[entry * 3 + 2] = UInt8((b + count / 2) / count)
        }
        for i in nearest.indices { nearest[i] = .max }
    }

    private func mapPixels(_ bgra: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) {
        let colours = colours
        palette.withUnsafeBufferPointer { palette in
            nearest.withUnsafeMutableBufferPointer { nearest in
                indices.withUnsafeMutableBufferPointer { indices in
                    for y in 0..<height {
                        let row = bgra + y * bytesPerRow
                        for x in 0..<width {
                            let nudge = Self.dither[(y & 3) << 2 | (x & 3)]
                            let b = min(255, max(0, Int(row[x * 4]) + nudge))
                            let g = min(255, max(0, Int(row[x * 4 + 1]) + nudge))
                            let r = min(255, max(0, Int(row[x * 4 + 2]) + nudge))
                            let key = Self.key(r, g, b)
                            if nearest[key] == .max {
                                nearest[key] = UInt16(Self.closest(to: key, in: palette, colours: colours))
                            }
                            indices[y * width + x] = UInt8(nearest[key])
                        }
                    }
                }
            }
        }
    }

    private static func closest(to key: Int, in palette: UnsafeBufferPointer<UInt8>, colours: Int) -> Int {
        // The middle of the 15-bit colour's cell.
        let r = (key >> 10 & 31) << 3 | 4, g = (key >> 5 & 31) << 3 | 4, b = (key & 31) << 3 | 4
        var best = 0, bestDistance = Int.max
        for entry in 0..<colours {
            let dr = r - Int(palette[entry * 3]), dg = g - Int(palette[entry * 3 + 1]), db = b - Int(palette[entry * 3 + 2])
            // Eyes are most sensitive to green, least to blue.
            let distance = 3 * dr * dr + 4 * dg * dg + 2 * db * db
            if distance < bestDistance {
                best = entry
                bestDistance = distance
            }
        }
        return best
    }
}

/// GIF's LZW: codes of 9 to 12 bits, packed low bit first into blocks of up to 255 bytes.
final class GIFLZW {
    /// The code for "string `code` then byte `b`" at `code << 8 | b`, tagged with the table's
    /// generation so starting a new table doesn't mean clearing 4 MB.
    private var table = [UInt32](repeating: 0, count: 4096 << 8)
    private var generation: UInt32 = 0

    private static let clear = 256
    private static let end = 257

    func encode(_ indices: [UInt8], into data: inout Data) {
        var packer = BitPacker()
        var size = 9
        var last = Self.end
        startTable()
        packer.put(Self.clear, size: size, into: &data)
        guard var current = indices.first.map(Int.init) else {
            packer.put(Self.end, size: size, into: &data)
            packer.finish(into: &data)
            return
        }
        table.withUnsafeMutableBufferPointer { table in
            for value in indices.dropFirst() {
                let slot = current << 8 | Int(value)
                let entry = table[slot]
                if entry >> 12 == generation {
                    current = Int(entry & 0xFFF)
                    continue
                }
                packer.put(current, size: size, into: &data)
                last += 1
                table[slot] = generation << 12 | UInt32(last)
                if last >= 1 << size { size += 1 }
                if last == 4095 {
                    packer.put(Self.clear, size: size, into: &data)
                    generation += 1
                    if generation >= 1 << 20 {
                        for i in table.indices { table[i] = 0 }
                        generation = 1
                    }
                    size = 9
                    last = Self.end
                }
                current = Int(value)
            }
        }
        packer.put(current, size: size, into: &data)
        // The reader adds a code after reading that one, and may move to a wider code for the end.
        if last > Self.end, last + 1 >= 1 << size, size < 12 { size += 1 }
        packer.put(Self.end, size: size, into: &data)
        packer.finish(into: &data)
    }

    private func startTable() {
        generation += 1
        if generation >= 1 << 20 {
            for i in table.indices { table[i] = 0 }
            generation = 1
        }
    }

    private struct BitPacker {
        var bits: UInt32 = 0
        var count = 0
        var block: [UInt8] = []

        init() { block.reserveCapacity(255) }

        mutating func put(_ code: Int, size: Int, into data: inout Data) {
            bits |= UInt32(code) << count
            count += size
            while count >= 8 {
                block.append(UInt8(bits & 0xFF))
                bits >>= 8
                count -= 8
                if block.count == 255 { flush(into: &data) }
            }
        }

        mutating func finish(into data: inout Data) {
            if count > 0 { block.append(UInt8(bits & 0xFF)) }
            bits = 0
            count = 0
            flush(into: &data)
            data.append(0x00) // end of the frame's blocks
        }

        private mutating func flush(into data: inout Data) {
            guard !block.isEmpty else { return }
            data.append(UInt8(block.count))
            data.append(contentsOf: block)
            block.removeAll(keepingCapacity: true)
        }
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: Int) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8 & 0xFF))
    }
}
