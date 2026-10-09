import AppKit
import SwiftUI

/// Shows the notch window on the built-in display and keeps it aligned with the hardware notch.
@MainActor
public final class NotchWindowController {
    private var panel: NotchPanel?
    private var container: NotchContainerView?
    public private(set) var model: NotchViewModel?
    private let initialState: NotchState?
    private var hasGeometry = false

    /// - Parameter initialState: if set, start in this state and pin it (debug/screenshot aid).
    public init(initialState: NotchState? = nil) {
        self.initialState = initialState
    }

    /// Hides the notch completely, e.g. while a full-screen app on the user's hide list is in front.
    public var isSuppressed = false {
        didSet {
            guard isSuppressed != oldValue else { return }
            updateVisibility()
        }
    }

    /// The user's on/off switch: off hides the notch until it's turned back on.
    public var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            updateVisibility()
        }
    }

    /// Called each time the notch opens (usage stats).
    public var onOpen: (() -> Void)? {
        didSet { model?.onOpen = onOpen }
    }

    /// Hover delays and haptics from Settings.
    public var behavior = NotchBehavior() {
        didSet { model?.behavior = behavior }
    }

    /// Opens or closes the notch (keyboard shortcut).
    public func toggle() {
        guard hasGeometry, !isSuppressed, isEnabled else { return }
        model?.toggle()
    }

    /// Show, move, or hide the notch for new geometry. `nil` hides it (e.g. lid closed).
    public func update(geometry: NotchGeometry?) {
        hasGeometry = geometry != nil
        guard let geometry else {
            updateVisibility()
            return
        }
        let layout = NotchLayout(geometry: geometry)

        if let panel, let model {
            model.layout = layout
            container?.contentSize = layout.largestWindowSize
            panel.setFrame(layout.windowFrame(for: model.state), display: true)
        } else {
            createPanel(layout: layout)
        }
        updateVisibility()
    }

    private func updateVisibility() {
        if hasGeometry && !isSuppressed && isEnabled {
            panel?.orderFrontRegardless()
        } else {
            model?.reset()
            panel?.orderOut(nil)
        }
    }

    private func createPanel(layout: NotchLayout) {
        let model = NotchViewModel(layout: layout, state: initialState ?? .closed, behavior: behavior)
        model.isPinned = initialState != nil
        model.onOpen = onOpen
        let panel = NotchPanel(contentRect: layout.windowFrame(for: model.state))
        let hostingView = NSHostingView(rootView: NotchView(model: model))
        hostingView.sizingOptions = []
        let container = NotchContainerView(content: hostingView, contentSize: layout.largestWindowSize)
        panel.contentView = container
        model.fitWindow = { [weak panel, weak model] state in
            guard let panel, let model else { return }
            panel.setFrame(model.layout.windowFrame(for: state), display: true)
        }
        self.model = model
        self.panel = panel
        self.container = container
    }
}
