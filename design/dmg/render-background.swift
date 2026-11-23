// Renders the disk image window's background (scripts/make-dmg.sh): PancakeNotch on the left, an
// arrow, Applications on the right, and one line saying what to do. The window is 600 × 380 points;
// the icons sit at (160, 180) and (440, 180), as Resources/DMG/DS_Store places them.
//
// Usage: design/dmg/make-layout.sh (renders this at 1x and 2x and rebuilds the layout).

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct Background: View {
    var body: some View {
        ZStack {
            Color(white: 0.965)
            Image(systemName: "arrow.right")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color(white: 0.62))
                .position(x: 300, y: 172)
            Text("Drag PancakeNotch to Applications")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(white: 0.32))
                .position(x: 300, y: 318)
        }
        .frame(width: 600, height: 380)
    }
}

@main
@MainActor
struct RenderBackground {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3, let scale = Double(args[2]) else {
            fatalError("usage: render-background <out.png> <scale>")
        }
        let renderer = ImageRenderer(content: Background().environment(\.colorScheme, .light))
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: args[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { fatalError("Could not render \(args[1])") }
        let dpi = 72 * scale
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(args[1])") }
    }
}
