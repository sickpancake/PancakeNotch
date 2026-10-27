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

    /// - Parameters:
    ///   - initialState: if set, start in this state and pin it (debug/screenshot aid).
    ///   - arrangement: the user's module ranking and navigation settings.
    public init(initialState: NotchState? = nil, arrangement: ModuleArrangement = ModuleArrangement()) {
        self.initialState = initialState
        self.arrangement = arrangement
        // Drops on any notch (this one or a preview) and drags out of a module end unseen by the watcher.
        dragSettledObserver = NotificationCenter.default.addObserver(
            forName: NotchViewModel.dragSettled, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragWatcher.dragSettled() }
        }
    }

    private static func same(_ lhs: [any NotchModule], _ rhs: [any NotchModule]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }

    /// Hides the notch completely, e.g. while a full-screen app on the user's hide list is in front.
    public var isSuppressed = false {
        didSet {
            guard isSuppressed != oldValue else { return }
            updateVisibility()
        }
    }

    /// Hides the notch while a full-screen app fills the display (the user's setting, ADR-0030). Unlike
    /// `isSuppressed`, the keyboard shortcut still opens it; it hides again once it has closed.
    public var isHiddenForFullScreen = false {
        didSet {
            guard isHiddenForFullScreen != oldValue else { return }
            // Open right now (the user is in it): it hides once it has closed.
            isRevealed = isHiddenForFullScreen && model?.state == .expanded
            updateVisibility()
        }
    }

    /// Shown while hidden for full screen (opened by the shortcut, or open when hiding began), until the
    /// notch closes.
    private var isRevealed = false

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

    /// The modules in the notch (any order: the arrangement ranks them). Empty shows the placeholder
    /// and refuses drops.
    public var modules: [any NotchModule] = [] {
        didSet {
            guard !Self.same(modules, oldValue) else { return }
            model?.modules = modules
            updateDragWatcher()
        }
    }

    /// Ranking, favorites, ear sides and navigation, shared with the app window.
    public let arrangement: ModuleArrangement

    /// The Module Menu's gear: opens the app window.
    public var openSettings: (() -> Void)? {
        didSet { model?.openSettings = openSettings }
    }

    /// A module's view appeared in the open notch (statistics).
    public var onModuleShown: ((String) -> Void)? {
        didSet { model?.onModuleShown = onModuleShown }
    }

    /// When true, taking keyboard focus also activates the app (fallback if a non-activating
    /// panel doesn't receive keys while another app stays active).
    public var activatesForKeyFocus = false

    private var appToRestore: NSRunningApplication?
    private var scrollMonitor: Any?
    private let dragWatcher = NotchDragWatcher()
    private var dragSettledObserver: Any?
    /// Hands drags over the notch to the module.
    private let dropRouter = NotchDropRouter()
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "notch")

    /// Opens or closes the notch (keyboard shortcut).
    public func toggle() {
        guard hasGeometry, !isSuppressed, isEnabled, let model else { return }
        let wasExpanded = model.state == .expanded
        if isHiddenForFullScreen, !isRevealed {
            isRevealed = true
            updateVisibility()
        }
        model.toggle()
        // Opened from the keyboard: keep using the keyboard inside it.
        if model.state == .expanded, !model.modules.isEmpty { takeKeyFocus() }
        // It couldn't open (e.g. Mission Control is up): hide again now. A close hides at its end.
        if !wasExpanded, model.state != .expanded { hideAfterReveal() }
    }

    /// Back to hidden once the notch the shortcut opened has finished closing (or shrinking: in full
    /// screen nothing stays around the notch).
    private func hideAfterReveal() {
        guard isRevealed, let model, model.state != .expanded else { return }
        isRevealed = false
        updateVisibility()
    }

    /// The window shows: there's a notch, the user wants it, and no full-screen app hides it.
    var isShowing: Bool {
        hasGeometry && !isSuppressed && isEnabled && (!isHiddenForFullScreen || isRevealed)
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
            layout.panelHeight = model.layout.panelHeight
            layout.isPeeking = model.layout.isPeeking
            model.layout = layout
            container?.contentSize = layout.largestWindowSize
            panel.setFrame(layout.windowFrame(for: model.state), display: true)
        } else {
            createPanel(layout: layout)
        }
        updateVisibility()
    }

    private func updateVisibility() {
        if isShowing {
            panel?.orderFrontRegardless()
        } else {
            model?.reset()
            panel?.orderOut(nil)
        }
        updateDragWatcher()
    }

    /// Watches for file drags heading to the notch while it's showing and a module takes drops.
    private func updateDragWatcher() {
        guard let model, !modules.isEmpty, !model.isPinned, isShowing else {
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
            model?.module(accepting: pasteboard) != nil
        }
        dragWatcher.floor = { [weak model] pasteboard in
            guard MissionControlDragGuard.isNeeded, let model,
                  model.module(accepting: pasteboard)?.keepsDragsBelowMenuBar == true else { return nil }
            let geometry = model.layout.geometry
            // The menu bar reaches the bottom of the notch; with the menu bar hidden, the notch's own height.
            let stripHeight = max(geometry.compactHeight, geometry.notchRect.height)
            return MissionControlDragGuard.floorY(screenFrame: geometry.screenFrame, stripHeight: stripHeight)
        }
        dragWatcher.isOpen = { [weak model] in model?.state == .expanded }
        dragWatcher.onApproach = { [weak self, weak model] pasteboard in
            self?.logger.info("File drag approaching the notch: opening early")
            model?.dragApproached(pasteboard)
        }
        dragWatcher.onMove = { [weak self, weak model] pasteboard, location in
            guard let self, let model, model.state == .expanded, !model.showsMenu else { return }
            model.selectedModule?.dragApproaching(pasteboard, at: self.bodyPoint(screen: location, layout: model.layout))
        }
        dragWatcher.onLeave = { [weak model] in model?.approachingDragEnded() }
        dragWatcher.start()
    }

    private func createPanel(layout: NotchLayout) {
        let model = NotchViewModel(layout: layout, state: initialState ?? .closed, behavior: behavior, arrangement: arrangement)
        model.isPinned = initialState != nil
        model.onOpen = onOpen
        model.onModuleShown = onModuleShown
        model.openSettings = openSettings
        model.modules = modules
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
        model.fitWindow = { [weak self, weak panel, weak model] state in
            guard let panel, let model else { return }
            let frame = model.layout.windowFrame(for: state)
            // Called before and after every transition: a frame that didn't change needs no redraw.
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            // A transition's end (the size asked for is the state it settled in) after the shortcut's reveal.
            if state == model.state { self?.hideAfterReveal() }
        }
        self.model = model
        self.panel = panel
        self.container = container
        watchScrolls()
        updateDragWatcher()
    }

    /// Two-finger swipes on the open notch switch modules. A local monitor sees only scrolls delivered
    /// to this app's windows, so it costs nothing while the pointer is elsewhere.
    private func watchScrolls() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                // Also while closed: `handleScroll` marks a swipe that starts before the notch opens
                // so its rest doesn't switch modules.
                guard let self, let panel = self.panel, event.window === panel, let model = self.model else { return }
                let point = self.bodyPoint(screen: NSEvent.mouseLocation, layout: model.layout)
                model.handleScroll(event, at: point)
            }
            return event
        }
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
