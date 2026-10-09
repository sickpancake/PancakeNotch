import AppKit
import SwiftUI

/// Renders every notch state off-screen to a PNG, for design work without Screen Recording permission.
/// Triggered by `PANCAKENOTCH_SNAPSHOT=/path/out.png`.
@MainActor
public enum NotchSnapshot {
    public static func write(geometry: NotchGeometry, to url: URL) throws {
        let layout = NotchLayout(geometry: geometry)
        let window = layout.windowFrame.size
        let view = VStack(spacing: 12) {
            ForEach(NotchState.allCases, id: \.self) { state in
                ZStack(alignment: .top) {
                    // Stand-in for a light menu bar and desktop, so the black outline is visible.
                    Color(white: 0.55)
                    Color(white: 0.85).frame(height: geometry.notchRect.height)
                    NotchView(model: NotchViewModel(layout: layout, state: state))
                }
                .frame(width: window.width, height: window.height)
            }
        }
        .padding(12)
        .background(Color(white: 0.3))
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
