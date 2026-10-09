// Turns the app icon artwork into Resources/AppIcon.icns.
//
// short-stack-source.png is the "Short Stack" icon, generated with an image model from the
// concept drawn by render.swift. It comes on a flat grey backdrop, so this script finds the
// rounded-square body, cuts it out with the macOS icon shape, adds the usual soft shadow, and
// writes every size macOS wants.
//
// Usage (from the repo root):
//   swift design/icon/make-icns.swift design/icon/short-stack-source.png Resources/AppIcon.icns

import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: swift make-icns.swift <source.png> <out.icns>")
    exit(1)
}
let source = NSImage(contentsOfFile: args[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let width = source.width, height = source.height

// Read brightness so the body's edges can be found against the backdrop.
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let reader = CGContext(
    data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
reader.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
func brightness(_ x: Int, _ y: Int) -> Int { Int(pixels[(y * width + x) * 4]) } // y = 0 is the top row

/// First position along a line where brightness jumps up by more than 20 within 4 pixels — the
/// body's edge, where its lit rim meets the darker drop shadow (the rim is anti-aliased).
func edge(_ positions: [Int], _ sample: (Int) -> Int) -> Int {
    for (previous, position) in zip(positions, positions.dropFirst(4)) where sample(position) - sample(previous) > 20 {
        return position
    }
    fatalError("edge not found")
}
let mid = width / 2
let left = edge(Array(0..<mid)) { brightness($0, mid) }
let right = edge(Array((mid..<width).reversed())) { brightness($0, mid) }
let top = edge(Array(0..<mid)) { brightness(mid, $0) }
let bottom = edge(Array((mid..<height).reversed())) { brightness(mid, $0) }
let inset = 3 // stay clear of the anti-aliased rim
let body = CGRect(x: left + inset, y: top + inset, width: right - left - 2 * inset, height: bottom - top - 2 * inset)
print("icon body at \(body)")
let cropped = source.cropping(to: body)!

/// The artwork on a transparent canvas: macOS icon grid (824 body in 1024, radius 185), with shadow.
func render(size: Int) -> CGImage {
    let canvas = CGFloat(size)
    let scale = canvas / 1024
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    let frame = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    // A slightly larger radius than the artwork's own corners, so none of the backdrop shows.
    let shape = CGPath(roundedRect: frame, cornerWidth: 185 * scale, cornerHeight: 185 * scale, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()
    context.addPath(shape)
    context.clip()
    context.draw(cropped, in: frame)
    return context.makeImage()!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for (factor, suffix) in [(1, ""), (2, "@2x")] {
        let url = iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, render(size: points * factor), nil)
        CGImageDestinationFinalize(destination)
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", args[2]]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "wrote \(args[2])" : "iconutil failed")
exit(iconutil.terminationStatus)
