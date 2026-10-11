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
        didSet {
            model?.module = module
            updateDragWatcher()
        }
    }

    /// When true, taking keyboard focus also activates the app (fallback if a non-activating
    /// panel doesn't receive keys while another app stays active).
    public var activatesForKeyFocus = false

    private var appToRestore: NSRunningApplication?
    private let dragWatcher = NotchDragWatcher()
    /// Hands drags over the notch to the module.
    private let dropRouter = NotchDropRouter()
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
        var layout = NotchLayout(geometry: geometry)

        if let panel, let model {
            layout.isTall = model.layout.isTall
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
        updateDragWatcher()
    }

    /// Watches for file drags heading to the notch while it's showing and a module takes drops.
    private func updateDragWatcher() {
        guard let model, module != nil, !model.isPinned, hasGeometry, !isSuppressed, isEnabled else {
            dragWatcher.stop()
            return
        }
        guard !dragWatcher.isRunning else { return }
        dragWatcher.zone = { [weak model] in
            guard let model else { return .zero }
            // The area the normal open panel covers, so the drop lands inside it.
            return NotchLayout(geometry: model.layout.geometry).outlineFrame(for: .expanded)
        }
        dragWatcher.accepts = { [weak model] pasteboard in
            model?.module?.canAcceptDrag(pasteboard) ?? false
        }
        dragWatcher.onApproach = { [weak self, weak model] in
            self?.logger.info("File drag approaching the notch: opening early")
            model?.dragApproached()
        }
        dragWatcher.onMove = { [weak self, weak model] pasteboard, location in
            guard let self, let model, model.state == .expanded else { return }
            model.module?.dragApproaching(pasteboard, at: self.bodyPoint(screen: location, layout: model.layout))
        }
        dragWatcher.onLeave = { [weak model] in model?.approachingDragEnded() }
        dragWatcher.start()
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
        dropRouter.model = model
        container.dropDelegate = dropRouter
        panel.contentView = container
        panel.keyHandler = { [weak model] event in model?.handleKey(event) ?? false }
        model.fitWindow = { [weak panel, weak model] state in
            guard let panel, let model else { return }
            panel.setFrame(model.layout.windowFrame(for: state), display: true)
        }
        self.model = model
        self.panel = panel
        self.container = container
        updateDragWatcher()
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

extension NotchWindowController {
    /// Converts a screen point (y up) to the expanded notch body: the body is centered on the notch
    /// and hangs from the top of the screen.
    private func bodyPoint(screen point: CGPoint, layout: NotchLayout) -> CGPoint {
        let bodyWidth = layout.bodySize(for: .expanded).width
        return CGPoint(
            x: point.x - (layout.geometry.notchRect.midX - bodyWidth / 2),
            y: layout.geometry.screenFrame.maxY - point.y
        )
    }
}
