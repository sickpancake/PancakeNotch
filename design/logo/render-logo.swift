// Renders the app's one-colour logo (LogoGlyph) to a transparent PNG.
// It is compiled together with the app's own LogoGlyph.swift, so the PNG always matches the
// menu bar mark. The output is generated locally and gitignored (see .gitignore).
//
// Usage, from design/logo/:
//   SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk | sort -V | tail -1)
//   swiftc -sdk "$SDK" -o /tmp/render-logo ../../Sources/PancakeNotch/LogoGlyph.swift render-logo.swift
//   /tmp/render-logo logo.png            # 1024 px, black on transparent
//
// (Drop the -sdk flag if you have Xcode installed.)

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
struct RenderLogo {
    static func main() {
        let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "logo.png"
        let size: CGFloat = 1024
        // One grid unit of margin on each side, so the drips never touch the edge.
        let margin = size / 20

        let logo = LogoGlyph()
            .fill(Color.black)
            .frame(width: size - 2 * margin, height: size - 2 * margin)
            .padding(margin)

        let renderer = ImageRenderer(content: logo)
        renderer.scale = 1
        guard let image = renderer.cgImage else {
            fatalError("Could not render the logo")
        }

        let url = URL(fileURLWithPath: path) as CFURL
        guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("Could not create \(path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            fatalError("Could not write \(path)")
        }
        print("Wrote \(path) (\(image.width) × \(image.height) px)")
    }
}
