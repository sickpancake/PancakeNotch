import AppKit
import SwiftUI

/// Renders every notch state off-screen to a PNG, for design work without Screen Recording permission.
/// Triggered by `PANCAKENOTCH_SNAPSHOT=/path/out.png`.
@MainActor
public enum NotchSnapshot {
    /// - Parameter moduleRows: extra rows, each a notch model already set up with a module in some state.
    public static func write(
        geometry: NotchGeometry,
        to url: URL,
        moduleRows: (NotchLayout) -> [NotchViewModel] = { _ in [] }
    ) throws {
        let layout = NotchLayout(geometry: geometry)
        let models = NotchState.allCases.map { NotchViewModel(layout: layout, state: $0) } + moduleRows(layout)
        let view = VStack(spacing: 12) {
            ForEach(models.indices, id: \.self) { index in
                let window = models[index].layout.windowFrame(for: .expanded).size
                ZStack(alignment: .top) {
                    // Stand-in for a light menu bar and desktop, so the black outline is visible.
                    Color(white: 0.55)
                    Color(white: 0.85).frame(height: geometry.notchRect.height)
                    NotchView(model: models[index])
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
