import CoreGraphics

/// The position and size of the notch on a screen, in AppKit screen coordinates
/// (origin at the bottom-left of the primary display).
public struct NotchGeometry: Equatable, Sendable {
    /// Size used when no hardware notch exists but a simulated one is requested (CI, testing).
    public static let simulatedSize = CGSize(width: 185, height: 32)

    public let screenFrame: CGRect
    public let notchRect: CGRect
    public let isSimulated: Bool
    /// Height of the compact ears: the menu bar's, which macOS sizes to reach the bottom of the notch.
    /// `safeAreaInsets.top` is rounded and can end a fraction short of it on scaled resolutions.
    public let compactHeight: CGFloat

    /// Builds geometry from the values `NSScreen` reports. Returns `nil` when the screen has no notch.
    ///
    /// - Parameters:
    ///   - screenFrame: `NSScreen.frame`.
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top`.
    ///   - auxiliaryTopLeftWidth: width of `NSScreen.auxiliaryTopLeftArea`.
    ///   - auxiliaryTopRightWidth: width of `NSScreen.auxiliaryTopRightArea`.
    ///   - menuBarHeight: `frame.maxY - visibleFrame.maxY`; 0 when the menu bar hides itself.
    public init?(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?,
        menuBarHeight: CGFloat = 0
    ) {
        guard safeAreaTop > 0,
              let leftWidth = auxiliaryTopLeftWidth,
              let rightWidth = auxiliaryTopRightWidth
        else { return nil }

        let notchWidth = screenFrame.width - leftWidth - rightWidth
        guard notchWidth > 0 else { return nil }

        self.screenFrame = screenFrame
        self.notchRect = CGRect(
            x: screenFrame.minX + leftWidth,
            y: screenFrame.maxY - safeAreaTop,
            width: notchWidth,
            height: safeAreaTop
        )
        self.isSimulated = false
        // Only a value just above the safe area is the notch's real bottom; anything else (hidden
        // menu bar, odd layouts) falls back to the safe area.
        self.compactHeight = (safeAreaTop...safeAreaTop + 3).contains(menuBarHeight) ? menuBarHeight : safeAreaTop
    }

    /// A notch-sized rectangle centered at the top of `screenFrame`, for screens without a notch.
    public static func simulated(in screenFrame: CGRect, size: CGSize = simulatedSize) -> NotchGeometry {
        NotchGeometry(
            screenFrame: screenFrame,
            notchRect: CGRect(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.maxY - size.height,
                width: size.width,
                height: size.height
            ),
            isSimulated: true
        )
    }

    private init(screenFrame: CGRect, notchRect: CGRect, isSimulated: Bool) {
        self.screenFrame = screenFrame
        self.notchRect = notchRect
        self.isSimulated = isSimulated
        self.compactHeight = notchRect.height
    }
}
