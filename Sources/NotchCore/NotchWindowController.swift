import AppKit
import os
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

    /// The module shown in the notch; `nil` shows the placeholder and refuses drops.
    public var module: (any NotchModule)? {
        didSet { model?.module = module }
    }

    /// When true, taking keyboard focus also activates the app (fallback if a non-activating
    /// panel doesn't receive keys while another app stays active).
    public var activatesForKeyFocus = false

    private var appToRestore: NSRunningApplication?
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "notch")

    /// Opens or closes the notch (keyboard shortcut).
    public func toggle() {
        guard hasGeometry, !isSuppressed, isEnabled, let model else { return }
        model.toggle()
        // Opened from the keyboard: keep using the keyboard inside it.
        if model.state == .expanded, model.module != nil { takeKeyFocus() }
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
        model.module = module
        model.requestKeyFocus = { [weak self] in self?.takeKeyFocus() }
        model.releaseKeyFocus = { [weak self] in self?.releaseKeyFocus() }
        let panel = NotchPanel(contentRect: layout.windowFrame(for: model.state))
        let hostingView = NSHostingView(rootView: NotchView(model: model))
        hostingView.sizingOptions = []
        let container = NotchContainerView(content: hostingView, contentSize: layout.largestWindowSize)
        container.dropDelegate = self
        panel.contentView = container
        panel.keyHandler = { [weak model] event in model?.handleKey(event) ?? false }
        model.fitWindow = { [weak panel, weak model] state in
            guard let panel, let model else { return }
            panel.setFrame(model.layout.windowFrame(for: state), display: true)
        }
        self.model = model
        self.panel = panel
        self.container = container
    }

    private func takeKeyFocus() {
        guard let panel, !panel.isKeyWindow else { return }
        panel.allowsKey = true
        if activatesForKeyFocus {
            appToRestore = NSWorkspace.shared.frontmostApplication
            NSApp.activate()
        }
        panel.makeKey()
        logger.info("Notch took key focus (isKey=\(panel.isKeyWindow), activated=\(self.activatesForKeyFocus))")
    }

    private func releaseKeyFocus() {
        guard let panel, panel.allowsKey else { return }
        let wasKey = panel.isKeyWindow
        panel.allowsKey = false
        if wasKey { panel.resignKey() }
        if let app = appToRestore {
            appToRestore = nil
            app.activate(options: [])
        }
        logger.info("Notch released key focus (wasKey=\(wasKey))")
    }
}

extension NotchWindowController: NotchDropDelegate {
    /// Converts a point in the hosted content to the expanded notch body, where modules lay out their drop zones.
    private func bodyPoint(_ contentPoint: CGPoint, layout: NotchLayout) -> CGPoint {
        let origin = layout.bodyOrigin(for: .expanded)
        return CGPoint(x: contentPoint.x - origin.x, y: contentPoint.y - origin.y)
    }

    func dragEntered(_ info: any NSDraggingInfo, at contentPoint: CGPoint) -> NSDragOperation {
        // Our own drags (an item being dragged out of the Shelf) never drop back in.
        guard let model, let module = model.module, info.draggingSource == nil else { return [] }
        logger.info("Drag entered notch: \(info.draggingPasteboard.types?.map(\.rawValue) ?? [], privacy: .public)")
        let operation = module.dragUpdated(info, at: bodyPoint(contentPoint, layout: model.layout))
        if !operation.isEmpty { model.dragEntered() }
        return operation
    }

    func dragUpdated(_ info: any NSDraggingInfo, at contentPoint: CGPoint) -> NSDragOperation {
        guard let model, let module = model.module, info.draggingSource == nil else { return [] }
        let operation = module.dragUpdated(info, at: bodyPoint(contentPoint, layout: model.layout))
        if !operation.isEmpty, model.state != .expanded { model.dragEntered() }
        return operation
    }

    func dragExited() {
        model?.dragExited()
    }

    func performDrop(_ info: any NSDraggingInfo, at contentPoint: CGPoint) -> Bool {
        guard let model, let module = model.module, info.draggingSource == nil else { return false }
        let accepted = module.performDrop(info, at: bodyPoint(contentPoint, layout: model.layout))
        logger.info("Drop on notch accepted=\(accepted)")
        return accepted
    }

    func dragConcluded() {
        model?.dragConcluded()
    }
}
