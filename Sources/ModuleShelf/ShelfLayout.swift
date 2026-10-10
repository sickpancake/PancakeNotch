import CoreGraphics
import NotchCore

/// Where things sit inside the expanded notch body (origin top-left, y down). Shared by the views and
/// the drop-zone hit test, so what you see is where a drop lands.
struct ShelfLayout: Equatable {
    static let sidePadding: CGFloat = 18
    static let bottomPadding: CGFloat = 12
    static let airDropWidth: CGFloat = 128
    static let tileSize = CGSize(width: 74, height: 90)
    static let tileSpacing: CGFloat = 6

    let body: CGSize
    /// Height of the band beside the hardware notch (the header lives there).
    let bandHeight: CGFloat
    /// Width of the hardware notch; nothing may sit under it.
    let notchWidth: CGFloat

    init(_ layout: NotchLayout) {
        body = layout.bodySize(for: .expanded)
        bandHeight = layout.geometry.notchRect.height
        notchWidth = layout.geometry.notchRect.width
    }

    /// Width of each header half beside the notch.
    var headerSideWidth: CGFloat { max(0, (body.width - notchWidth) / 2 - Self.sidePadding - 8) }

    /// The area below the header: tiles, drop zones and cards.
    var content: CGRect {
        let top = bandHeight + 6
        return CGRect(
            x: Self.sidePadding,
            y: top,
            width: body.width - 2 * Self.sidePadding,
            height: max(0, body.height - top - Self.bottomPadding)
        )
    }

    /// The AirDrop drop zone at the trailing end of the content area.
    var airDropZone: CGRect {
        CGRect(x: content.maxX - Self.airDropWidth, y: content.minY, width: Self.airDropWidth, height: content.height)
    }
}
