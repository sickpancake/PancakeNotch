import AppKit

extension NSScreen {
    /// The Mac's built-in display, if it is currently active (e.g. `nil` with the lid closed).
    public static var builtIn: NSScreen? {
        screens.first { CGDisplayIsBuiltin($0.displayID) != 0 }
    }

    public var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Notch geometry for this screen, or `nil` if it has no notch.
    /// Apple advises not to cache these values; recompute after screen-parameter changes.
    public var notchGeometry: NotchGeometry? {
        NotchGeometry(
            screenFrame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: auxiliaryTopRightArea?.width
        )
    }
}
