import AppKit

/// Tells whether Mission Control (or App Exposé) is on screen, from the window server's own overlays.
/// macOS posts no usable notification for it, so this is read on demand, when the notch is about to
/// open, never on a timer. Owner, layer and size are readable without Screen Recording; window titles
/// are not, so they're not used. If macOS changes these overlays it reports `false` and the notch simply
/// behaves as before.
public enum MissionControlDetector {
    /// One on-screen window, as `CGWindowListCopyWindowInfo` describes it.
    struct Surface: Equatable {
        enum Owner { case windowManager, dock, other }
        var owner: Owner
        var layer: Int
        var bounds: CGRect
    }

    /// macOS 27: WindowManager's full-screen shield behind the window thumbnails (Mission Control and
    /// App Exposé), measured 2026-10-10. Its Spaces bar (layer 14) isn't used: it outlives the shield.
    static let shieldLayer = 19
    /// Up to macOS 26 the Dock draws Mission Control, with a full-screen window at this layer. The Dock's
    /// own window is full-screen at layer 20 on some versions even at rest, so that one never counts.
    static let dockOverlayLayer = 18

    public static var isActive: Bool {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] else { return false }
        // By bundle identifier: process names can be localized.
        let windowManager = pid(of: "com.apple.WindowManager")
        let dock = pid(of: "com.apple.dock")
        let surfaces = list.compactMap { info -> Surface? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid == windowManager || pid == dock,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = (info[kCGWindowBounds as String] as? [String: Any])
                      .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) })
            else { return nil }
            return Surface(owner: pid == windowManager ? .windowManager : .dock, layer: layer, bounds: bounds)
        }
        return isActive(surfaces, screenSizes: NSScreen.screens.map(\.frame.size))
    }

    private static func pid(of bundleID: String) -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
    }

    /// Only a window covering a whole screen counts: Stage Manager can leave small icons at the
    /// shield's layer.
    static func isActive(_ surfaces: [Surface], screenSizes: [CGSize]) -> Bool {
        surfaces.contains { surface in
            let isOverlay = switch surface.owner {
            case .windowManager: surface.layer == shieldLayer
            case .dock: surface.layer == dockOverlayLayer
            case .other: false
            }
            return isOverlay && screenSizes.contains { surface.bounds.width >= $0.width && surface.bounds.height >= $0.height }
        }
    }
}
