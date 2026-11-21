import AppKit
import Foundation

@main @MainActor struct ShelfBenchmark {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let items = try ["txt", "swift", "pdf", "png", "zip", "json", "md", "csv", "mp3", "html"].map { ext in
            let url = directory.appending(path: "sample.\(ext)")
            try Data("test".utf8).write(to: url)
            return ShelfItem(kind: .file(bookmark: Data(), owned: false), path: url.path, addedAt: .now)
        }
        for item in items { _ = NSWorkspace.shared.icon(forFile: item.path!) }
        for redraws in [1, 30] {
            var base: [Double] = []
            var candidate: [Double] = []
            for i in 0..<9 {
                for old in i.isMultiple(of: 2) ? [true, false] : [false, true] {
                    let tiles = items.map { _ in ShelfWidgetFilePresentation() }
                    var names = 0
                    let start = DispatchTime.now().uptimeNanoseconds
                    for _ in 0..<redraws {
                        autoreleasepool {
                            for (item, tile) in zip(items, tiles) {
                                if old {
                                    let icon = ShelfThumbnails.smallIcon(forFile: item.path!)
                                    let name = item.displayName
                                    names += name.utf8.count
                                    precondition(!icon.representations.isEmpty)
                                } else {
                                    let file = tile.file(for: item, scale: 2)!
                                    names += file.name.utf8.count
                                    let rep = file.icon.representations[0]
                                    precondition(rep.pixelsWide <= 52 && rep.pixelsHigh <= 52)
                                }
                            }
                        }
                    }
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    precondition(names == redraws * items.reduce(0) { $0 + $1.displayName.utf8.count })
                    if old { base.append(elapsed) } else { candidate.append(elapsed) }
                }
            }
            print("Shelf, 10 files, \(redraws) evaluation(s): \(base.sorted()[4]) -> \(candidate.sorted()[4]) ms")
        }
    }
}
