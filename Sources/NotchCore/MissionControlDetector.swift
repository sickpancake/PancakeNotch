import AppKit

/// Tells whether Mission Control (or App Exposé) is on screen, from the window server's own overlays.
/// macOS posts no usable notification for it, so this is read on demand, when the notch is about to
/// open, never on a timer. Owner, layer and size are readable without Screen Recording; window titles
/// are not, so they're not used. If macOS changes these overlays it reports `false` and the notch simply
/// behaves as before.
public enum MissionControlDetector {
    /// One on-screen window, as `CGWindowListCopyWindowInfo` describes it.
    struct Surface: Equatable {
        var owner: String
        var layer: Int
        var bounds: CGRect
    }

    /// Process that draws the Mission Control shield and Spaces bar (measured on macOS 27, 2026-10-10).
    static let windowManager = "WindowManager"
    /// Full-screen shield behind the window thumbnails (Mission Control and App Exposé).
    static let shieldLayer = 19
    /// The Spaces bar along the top (Mission Control only).
    static let spacesBarLayer = 14
    /// The Dock also puts a full-screen window above the shield while Mission Control is up.
    static let dockOverlayLayer = 20

    public static var isActive: Bool {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] else { return false }
        let surfaces = list.compactMap { info -> Surface? in
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner == windowManager || owner == "Dock",
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = (info[kCGWindowBounds as String] as? [String: Any])
                      .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) })
            else { return nil }
            return Surface(owner: owner, layer: layer, bounds: bounds)
        }
        return isActive(surfaces, screenSizes: NSScreen.screens.map(\.frame.size))
    }

    static func isActive(_ surfaces: [Surface], screenSizes: [CGSize]) -> Bool {
        surfaces.contains { surface in
            switch (surface.owner, surface.layer) {
            case (windowManager, spacesBarLayer):
                true
            case (windowManager, shieldLayer), ("Dock", dockOverlayLayer):
                // Only when it covers a whole screen: the Dock itself sits at the same layer, and Stage
                // Manager can leave small icons at the shield's layer.
                screenSizes.contains { surface.bounds.width >= $0.width && surface.bounds.height >= $0.height }
            default:
                false
            }
        }
    }
}
