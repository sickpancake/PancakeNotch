import AppKit
import SwiftUI

/// Renders every notch state off-screen to a PNG, for design work without Screen Recording permission.
/// Triggered by `PANCAKENOTCH_SNAPSHOT=/path/out.png`.
@MainActor
public enum NotchSnapshot {
    /// - Parameters:
    ///   - includesStates: start with the bare closed, compact and open notch.
    ///   - additionalRows: custom expanded panels, drawn with the same desktop and camera mask.
    ///   - moduleRows: extra rows, each a notch model already set up with a module in some state.
    public static func write(
        geometry: NotchGeometry,
        to url: URL,
        includesStates: Bool = true,
        additionalRows: (NotchLayout) -> [AnyView] = { _ in [] },
        moduleRows: (NotchLayout) -> [NotchViewModel] = { _ in [] }
    ) throws {
        let layout = NotchLayout(geometry: geometry)
        let models = (includesStates ? NotchState.allCases.map { NotchViewModel(layout: layout, state: $0) } : []) + moduleRows(layout)
        let rows = models.map { (view: AnyView(NotchView(model: $0)), size: $0.layout.windowFrame(for: .expanded).size) }
            + additionalRows(layout).map { (view: $0, size: layout.windowFrame(for: .expanded).size) }
        let view = VStack(spacing: 12) {
            ForEach(rows.indices, id: \.self) { index in
                let window = rows[index].size
                ZStack(alignment: .top) {
                    // Stand-in for a light menu bar and desktop, so the black outline is visible.
                    Color(white: 0.55)
                    Color(white: 0.85).frame(height: geometry.notchRect.height)
                    rows[index].view
                    // The camera cutout hides pixels on a real Mac. Cover them here too so
                    // a button under the hardware cannot look correct in an off-screen picture.
                    Color.black.frame(width: geometry.notchRect.width, height: geometry.notchRect.height)
                }
                .frame(width: window.width, height: window.height)
            }
        }
        .padding(12)
        .background(Color(white: 0.3))
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        // Keep a long contact sheet below the renderer's large-image limit.
        let sheetHeight = rows.reduce(CGFloat(12)) { $0 + $1.size.height + 12 }
        renderer.scale = min(2, 16_000 / sheetHeight)
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
