import AppKit
import SwiftUI

/// The app's "Short Stack" logo as a one-colour mark: the notch pill on top, syrup dripping from
/// it, and two outlined pancakes below. Used in the menu bar and the app window's sidebar.
struct LogoGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        // Drawn on an 18 × 18 grid, then scaled to fit.
        let scale = min(rect.width, rect.height) / 18
        let origin = CGPoint(x: rect.midX - 9 * scale, y: rect.midY - 9 * scale)
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: origin.x + x * scale, y: origin.y + y * scale, width: width * scale, height: height * scale)
        }

        let pancakeStroke = StrokeStyle(lineWidth: 1.3 * scale)
        let pancakes = Path(roundedRect: box(1.65, 8.55, 14.7, 2.6), cornerRadius: 1.3 * scale)
            .strokedPath(pancakeStroke)
            .union(Path(roundedRect: box(1.65, 13.45, 14.7, 2.6), cornerRadius: 1.3 * scale).strokedPath(pancakeStroke))

        let pill = Path(roundedRect: box(2.5, 1.5, 13, 5), cornerRadius: 2.5 * scale)
            .subtracting(Path(ellipseIn: box(12.3, 3.1, 1.8, 1.8))) // camera lens
        // (x, bottom): syrup runs down over the top pancake.
        let drips = [(4.6, 10.0), (7.6, 11.0), (10.6, 9.4)].reduce(Path()) { drips, drip in
            drips.union(Path(roundedRect: box(drip.0, 5, 1.7, drip.1 - 5), cornerRadius: 0.85 * scale))
        }
        // A hairline gap around the syrup keeps it in front of the pancake outline.
        let gap = drips.strokedPath(StrokeStyle(lineWidth: 1.6 * scale)).union(drips)
        return pancakes.subtracting(gap).union(pill).union(drips)
    }

    /// The mark as a template image, which macOS tints for the menu bar (light, dark, highlighted).
    @MainActor
    static func templateImage(pointSize: CGFloat = 18) -> NSImage {
        let size = CGSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(LogoGlyph().path(in: rect).cgPath)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = String(localized: "PancakeNotch")
        return image
    }
}
