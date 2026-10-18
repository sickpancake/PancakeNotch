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
    /// Height of the taller expanded panel a module can ask for (the Shelf's editor and preview).
    public static let tallExpandedBodyHeight: CGFloat = 360
    /// Transparent margin around the expanded panel so its shadow isn't clipped.
    public static let shadowPadding: CGFloat = 24
    /// Height of the strip a module can show under the compact notch for a moment (the new song).
    public static let peekStripHeight: CGFloat = 24

    public let geometry: NotchGeometry
    /// The expanded panel is the taller version (see `NotchViewModel.setTall`).
    public var isTall: Bool
    /// The compact notch shows a module's peek strip under it (see `NotchViewModel.peek`).
    public var isPeeking: Bool

    public init(geometry: NotchGeometry, isTall: Bool = false, isPeeking: Bool = false) {
        self.geometry = geometry
        self.isTall = isTall
        self.isPeeking = isPeeking
    }

    public func radii(for state: NotchState) -> NotchRadii {
        switch state {
        // No top ears when closed: everything drawn stays inside the hardware cutout, where black is invisible.
        case .closed: NotchRadii(top: 0, bottom: 14)
        case .compact: NotchRadii(top: 6, bottom: isPeeking ? 16 : 14)
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
            let peek = isPeeking ? Self.peekStripHeight : 0
            return CGSize(width: notch.width + 2 * compactEarWidth, height: geometry.compactHeight + peek)
        case .expanded:
            let available = geometry.screenFrame.width - 2 * (Self.shadowPadding + radii(for: .expanded).top)
            let width = max(notch.width, min(Self.maxExpandedBodySize.width, available))
            // The tall panel keeps a third of the screen free below it.
            let tall = min(Self.tallExpandedBodyHeight, geometry.screenFrame.height * 2 / 3)
            let height = isTall ? max(tall, Self.maxExpandedBodySize.height) : Self.maxExpandedBodySize.height
            return CGSize(width: width, height: max(notch.height, height))
        }
    }

    /// Size of the full outline (body plus ears) for a state, i.e. the `NotchShape` frame.
    public func shapeSize(for state: NotchState) -> CGSize {
        let body = bodySize(for: state)
        return CGSize(width: body.width + 2 * radii(for: state).top, height: body.height)
    }

    /// The biggest window any state needs, tall panel included; the notch view is laid out at this size once.
    public var largestWindowSize: CGSize {
        let tall = NotchLayout(geometry: geometry, isTall: true)
        return NotchState.allCases.map { tall.windowFrame(for: $0).size }.reduce(.zero) {
            CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height))
        }
    }

    /// Top-left corner of a state's notch body inside the hosted content, which is laid out at
    /// `largestWindowSize` with the notch top-centred (y down).
    public func bodyOrigin(for state: NotchState) -> CGPoint {
        CGPoint(x: (largestWindowSize.width - bodySize(for: state).width) / 2, y: 0)
    }

    /// The notch outline on screen for a state: the window frame without the shadow margin.
    /// This is what the pointer hovers.
    public func outlineFrame(for state: NotchState) -> CGRect {
        let window = windowFrame(for: state)
        let padding = state == .expanded ? Self.shadowPadding : 0
        return CGRect(x: window.minX + padding, y: window.minY + padding, width: window.width - 2 * padding, height: window.height - padding)
    }

    /// The pointer is on the notch outline for a state (see `area(_:contains:)`).
    public func outline(for state: NotchState, contains point: CGPoint) -> Bool {
        Self.area(outlineFrame(for: state), contains: point)
    }

    /// `CGRect.contains` for an area hanging from the top of the screen, with its top edge included: a
    /// pointer pushed against the top of the screen sits exactly there (y == the screen's maxY).
    static func area(_ frame: CGRect, contains point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }

    /// Window frame for a state: just the outline (plus shadow room when expanded), centered on the
    /// notch and touching the top of the screen, so the window never covers more than it shows.
    public func windowFrame(for state: NotchState) -> CGRect {
        let shape = shapeSize(for: state)
        let padding = state == .expanded ? Self.shadowPadding : 0
        let width = shape.width + 2 * padding
        let height = shape.height + padding
        return CGRect(
            x: geometry.notchRect.midX - width / 2,
            y: geometry.screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}
