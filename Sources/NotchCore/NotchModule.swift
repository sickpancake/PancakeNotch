import AppKit
import SwiftUI

/// A feature that lives in the notch: Now Playing, the Shelf (ADR-0014).
///
/// The notch hosts several modules (`NotchViewModel.modules`). The open notch shows one at a time
/// (the selected one) or the Module Menu (ADR-0010); the compact ears go to the top two active
/// modules by ranking (ADR-0011). Attaching a module calls `attach(to:)`.
@MainActor
public protocol NotchModule: AnyObject {
    /// Stable identifier: the ranking, favorites and statistics key on it ("nowPlaying", "shelf").
    var moduleID: String { get }
    /// The module's name in tabs, the Module Menu and VoiceOver.
    var title: String { get }
    /// SF Symbol for tabs and the Module Menu.
    var symbol: String { get }
    /// One short line for the Module Menu's list (e.g. "Playing", "3 items"); `nil` for none.
    var menuStatus: String? { get }

    /// Called with the notch model when the module is attached, and with `nil` when it's removed.
    func attach(to notch: NotchViewModel?)

    /// The open panel's content, laid out at `layout.bodySize(for: .expanded)`. Its top band, beside
    /// the hardware notch, leaves `notchModuleBarWidth` (environment) free on the left for the tabs.
    func expandedView(layout: NotchLayout) -> AnyView
    /// Content for the compact ears, or `nil`. The views stay alive while the notch is closed or open
    /// (hidden, under the notch), so they can slide in and out.
    func compactEars(layout: NotchLayout) -> CompactEars?
    /// A slim strip under the compact notch, shown for a moment by `NotchViewModel.peek(_:for:)`
    /// (the new song's title), laid out at the compact width × `NotchLayout.peekStripHeight`.
    func peekView(layout: NotchLayout) -> AnyView?

    /// Wants a place in the compact ears right now (music playing or paused, the Shelf nearly full).
    /// Call `NotchViewModel.activityChanged()` when it changes.
    var isActive: Bool { get }
    /// The notch should open on this module (music is playing). The first such module by ranking
    /// wins; otherwise the notch opens on the one used last (ADR-0010).
    var wantsFocus: Bool { get }

    /// Read by VoiceOver while the notch is closed or compact (e.g. "Shelf is full").
    var accessibilityStatus: String? { get }

    /// True while something must keep the notch open: a menu, a preview, a prompt, a drag in progress.
    /// Call `NotchViewModel.holdReleased()` when it turns false.
    var holdsOpen: Bool { get }

    /// The module's open view appeared (the notch opened on it, or the user switched to it), or went
    /// away (the notch closed, or the user switched to another module or the Menu). Heavy resources
    /// should be released when it goes away.
    func notchDidOpen()
    func notchDidClose()
    /// The user picked another module in the open notch (tab, Menu or swipe).
    func userSwitchedAway()

    /// Whether a sideways two-finger scroll at `point` (notch-body coordinates) scrolls something
    /// inside the module, so it mustn't switch modules (e.g. the Shelf's long tile row).
    func scrollsHorizontally(at point: CGPoint) -> Bool

    /// A drag elsewhere on screen came near the notch carrying this content. Return `true` to open the
    /// notch early, before the drag reaches the top edge where macOS starts Mission Control.
    func canAcceptDrag(_ pasteboard: NSPasteboard) -> Bool
    /// Whether a drag this module takes should stop just below the menu bar over the open notch, so
    /// macOS 27 doesn't start Mission Control (`MissionControlDragGuard`).
    var keepsDragsBelowMenuBar: Bool { get }
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

    /// A click landed elsewhere in the window hosting a preview of the notch (the app window). The real
    /// notch watches clicks in other apps itself; a preview's window is this app's, so it's told here.
    func clickedOutsidePreview()
}

public extension NotchModule {
    var moduleID: String { String(describing: Self.self) }
    var title: String { moduleID }
    var symbol: String { "square" }
    var menuStatus: String? { nil }
    func compactEars(layout: NotchLayout) -> CompactEars? { nil }
    func peekView(layout: NotchLayout) -> AnyView? { nil }
    var isActive: Bool { false }
    var wantsFocus: Bool { false }
    var holdsOpen: Bool { false }
    var accessibilityStatus: String? { nil }
    func notchDidOpen() {}
    func notchDidClose() {}
    func userSwitchedAway() {}
    func scrollsHorizontally(at point: CGPoint) -> Bool { false }
    func canAcceptDrag(_ pasteboard: NSPasteboard) -> Bool { false }
    var keepsDragsBelowMenuBar: Bool { false }
    func dragUpdated(_ info: any NSDraggingInfo, at point: CGPoint) -> NSDragOperation { [] }
    func dragApproaching(_ pasteboard: NSPasteboard, at point: CGPoint) {}
    func performDrop(_ info: any NSDraggingInfo, at point: CGPoint) -> Bool { false }
    func dragEnded() {}
    func handleKey(_ event: NSEvent) -> Bool { false }
    func clickedOutsidePreview() {}
}

/// A module's content for the compact ears, each laid out at `compactEarWidth` × the compact height.
///
/// `main` goes in the ear the module's ranking gives it (#1 left, #2 right, or swapped). `extra` fills
/// the other ear only while the module is the one active module (Now Playing: art + sound bars).
public struct CompactEars {
    public var main: AnyView
    public var extra: AnyView?

    public init(main: AnyView, extra: AnyView? = nil) {
        self.main = main
        self.extra = extra
    }
}

public extension EnvironmentValues {
    /// Width the module tabs take at the left of the open notch's top band (0 when there are none):
    /// modules start their own header content after it.
    var notchModuleBarWidth: CGFloat {
        get { self[NotchModuleBarWidthKey.self] }
        set { self[NotchModuleBarWidthKey.self] = newValue }
    }
}

// A plain key rather than `@Entry`: that macro's plugin ships only with Xcode (AGENTS.md).
private struct NotchModuleBarWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
