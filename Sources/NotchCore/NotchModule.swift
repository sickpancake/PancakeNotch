import AppKit
import SwiftUI

/// A feature that lives in the notch: the Shelf, later Now Playing (ADR-0014).
///
/// The notch hosts one module at a time for now; the Module Menu (ADR-0010) arrives in M4.
/// A module is attached by setting `NotchViewModel.module`, which calls `attach(to:)`.
@MainActor
public protocol NotchModule: AnyObject {
    /// Called with the notch model when the module is attached, and with `nil` when it's removed.
    func attach(to notch: NotchViewModel?)

    /// The open panel's content, laid out at `layout.bodySize(for: .expanded)`.
    func expandedView(layout: NotchLayout) -> AnyView
    /// Content for the compact ears, one view per side, or `nil` to leave them empty. The views stay
    /// alive while the notch is closed or open (hidden, under the notch), so they can slide in and out.
    func compactEars(layout: NotchLayout) -> CompactEars?

    /// Read by VoiceOver while the notch is closed or compact (e.g. "Shelf is full").
    var accessibilityStatus: String? { get }

    /// True while something must keep the notch open: a menu, a preview, a prompt, a drag in progress.
    /// Call `NotchViewModel.holdReleased()` when it turns false.
    var holdsOpen: Bool { get }

    /// The notch finished opening or started closing. Heavy resources should be released on close.
    func notchDidOpen()
    func notchDidClose()

    /// A drag elsewhere on screen came near the notch carrying this content. Return `true` to open the
    /// notch early, before the drag reaches the top edge where macOS starts Mission Control.
    func canAcceptDrag(_ pasteboard: NSPasteboard) -> Bool
    /// A drag from another app moved over the open notch. `point` is in notch-body coordinates
    /// (origin at the body's top-left, y down). Return `[]` to refuse it.
    func dragUpdated(_ info: any NSDraggingInfo, at point: CGPoint) -> NSDragOperation
    /// A drag that opened the notch early moved inside the open panel's area, before AppKit reports it
    /// over the window: show where it would land. `point` is in notch-body coordinates, as above.
    func dragApproaching(_ pasteboard: NSPasteboard, at point: CGPoint)
    /// The drag was released over the notch. Return whether the module took it.
    func performDrop(_ info: any NSDraggingInfo, at point: CGPoint) -> Bool
    /// The drag left, ended, or the notch was hidden mid-drag: clear any drop highlight.
    func dragEnded()

    /// A key press while the notch has keyboard focus. Return `true` if handled.
    func handleKey(_ event: NSEvent) -> Bool
}

public extension NotchModule {
    func compactEars(layout: NotchLayout) -> CompactEars? { nil }
    var holdsOpen: Bool { false }
    var accessibilityStatus: String? { nil }
    func notchDidOpen() {}
    func notchDidClose() {}
    func canAcceptDrag(_ pasteboard: NSPasteboard) -> Bool { false }
    func dragUpdated(_ info: any NSDraggingInfo, at point: CGPoint) -> NSDragOperation { [] }
    func dragApproaching(_ pasteboard: NSPasteboard, at point: CGPoint) {}
    func performDrop(_ info: any NSDraggingInfo, at point: CGPoint) -> Bool { false }
    func dragEnded() {}
    func handleKey(_ event: NSEvent) -> Bool { false }
}

/// A module's content for the compact ears, each laid out at `compactEarWidth` × the compact height.
public struct CompactEars {
    public var leading: AnyView?
    public var trailing: AnyView?

    public init(leading: AnyView? = nil, trailing: AnyView? = nil) {
        self.leading = leading
        self.trailing = trailing
    }
}
