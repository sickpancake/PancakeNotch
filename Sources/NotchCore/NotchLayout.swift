import CoreGraphics

/// Corner radii of the notch outline. See `NotchShape`.
public struct NotchRadii: Equatable, Sendable {
    public var top: CGFloat
    public var bottom: CGFloat

    public init(top: CGFloat, bottom: CGFloat) {
        self.top = top
        self.bottom = bottom
    }
}

/// Sizes for each notch state and the frame of the window that hosts them, derived from the
/// runtime notch geometry (never hard-coded per Mac model).
public struct NotchLayout: Equatable, Sendable {
    /// Largest size of the expanded panel body (excluding the top ears).
    public static let maxExpandedBodySize = CGSize(width: 600, height: 180)
    /// Transparent margin around the expanded panel so its shadow isn't clipped.
    public static let shadowPadding: CGFloat = 24

    public let geometry: NotchGeometry

    public init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    public func radii(for state: NotchState) -> NotchRadii {
        switch state {
        case .closed, .compact: NotchRadii(top: 6, bottom: 14)
        case .expanded: NotchRadii(top: 18, bottom: 26)
        }
    }

    /// Width of each side "ear" added to the notch in the compact state.
    public var compactEarWidth: CGFloat { geometry.notchRect.height + 6 }

    /// Size of the notch body (the part below the ears) for a state.
    public func bodySize(for state: NotchState) -> CGSize {
        let notch = geometry.notchRect.size
        switch state {
        case .closed:
            return notch
        case .compact:
            return CGSize(width: notch.width + 2 * compactEarWidth, height: notch.height)
        case .expanded:
            let available = geometry.screenFrame.width - 2 * (Self.shadowPadding + radii(for: .expanded).top)
            let width = max(notch.width, min(Self.maxExpandedBodySize.width, available))
            return CGSize(width: width, height: max(notch.height, Self.maxExpandedBodySize.height))
        }
    }

    /// Size of the full outline (body plus ears) for a state, i.e. the `NotchShape` frame.
    public func shapeSize(for state: NotchState) -> CGSize {
        let body = bodySize(for: state)
        return CGSize(width: body.width + 2 * radii(for: state).top, height: body.height)
    }

    /// The fixed window frame: big enough for the expanded panel and its shadow, centered on the
    /// notch and touching the top of the screen. Transparent parts of the window let clicks through.
    public var windowFrame: CGRect {
        let expanded = shapeSize(for: .expanded)
        let width = expanded.width + 2 * Self.shadowPadding
        let height = expanded.height + Self.shadowPadding
        return CGRect(
            x: geometry.notchRect.midX - width / 2,
            y: geometry.screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}
