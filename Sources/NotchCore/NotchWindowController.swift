import AppKit
import SwiftUI

/// Shows the notch window on the built-in display and keeps it aligned with the hardware notch.
@MainActor
public final class NotchWindowController {
    private var panel: NotchPanel?
    public private(set) var model: NotchViewModel?
    private let initialState: NotchState?

    /// - Parameter initialState: if set, start in this state and pin it (debug/screenshot aid).
    public init(initialState: NotchState? = nil) {
        self.initialState = initialState
    }

    /// Show, move, or hide the notch for new geometry. `nil` hides it (e.g. lid closed).
    public func update(geometry: NotchGeometry?) {
        guard let geometry else {
            panel?.orderOut(nil)
            return
        }
        let layout = NotchLayout(geometry: geometry)

        if let panel, let model {
            model.layout = layout
            panel.setFrame(layout.windowFrame, display: true)
            panel.orderFrontRegardless()
            return
        }

        let model = NotchViewModel(layout: layout, state: initialState ?? .closed)
        model.isPinned = initialState != nil
        let panel = NotchPanel(contentRect: layout.windowFrame)
        let hostingView = NSHostingView(rootView: NotchView(model: model))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setFrame(layout.windowFrame, display: true)
        panel.orderFrontRegardless()
        self.model = model
        self.panel = panel
    }
}
