import CoreGraphics
import NotchCore

/// Where things sit in the open Agents and AI Usage panels (origin top-left, y down): a band beside the
/// hardware notch, then the list or the columns under it.
struct AgentsLayout: Equatable {
    static let sidePadding: CGFloat = 20
    static let bottomPadding: CGFloat = 14

    let body: CGSize
    /// Height of the band beside the hardware notch.
    let bandHeight: CGFloat
    /// Width of the hardware notch; nothing may sit under it.
    let notchWidth: CGFloat

    init(_ layout: NotchLayout) {
        body = layout.bodySize(for: .expanded)
        bandHeight = layout.geometry.notchRect.height
        notchWidth = layout.geometry.notchRect.width
    }

    /// Room under the band.
    var contentHeight: CGFloat { body.height - bandHeight - Self.bottomPadding }

    /// Width of each half of the band beside the notch.
    var bandSideWidth: CGFloat { max(0, (body.width - notchWidth) / 2 - Self.sidePadding) }
}
