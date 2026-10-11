import AppKit
import SwiftUI

/// A working miniature of the notch for the app window: hover or click it to try the current behavior
/// settings, drop files on it, click and right-click what's inside. It runs its own model, separate
/// from the real notch, hosted the same way as the real one (AppKit drops, keys while focused).
public struct NotchPreview: View {
    private let behavior: NotchBehavior
    private let module: (any NotchModule)?
    private let onStateChange: ((NotchState, _ byClick: Bool) -> Void)?
    private let startState: NotchState?
    @State private var host: NotchPreviewHost

    /// - Parameters:
    ///   - behavior: hover delays and haptics, normally the user's current settings.
    ///   - screenWidth: width of the pretend screen; the expanded panel is clamped to it.
    ///   - module: what the preview shows inside (e.g. a practice Shelf); `nil` shows the placeholder.
    ///   - acceptsDragSource: which drags may drop in, by their source (`nil` for other apps). By
    ///     default every drag, so files dragged from inside the app window land too.
    ///   - onStateChange: called when the preview opens, shrinks or closes (lessons), and whether a
    ///     click (or Esc) did it.
    ///   - startState: a state to go to on appearing (off-screen snapshots).
    public init(
        behavior: NotchBehavior,
        screenWidth: CGFloat = 640,
        module: (any NotchModule)? = nil,
        acceptsDragSource: @escaping @MainActor (Any?) -> Bool = { _ in true },
        onStateChange: ((NotchState, _ byClick: Bool) -> Void)? = nil,
        startState: NotchState? = nil
    ) {
        self.behavior = behavior
        self.module = module
        self.onStateChange = onStateChange
        self.startState = startState
        _host = State(initialValue: NotchPreviewHost(
            behavior: behavior,
            screenWidth: screenWidth,
            acceptsDragSource: acceptsDragSource
        ))
    }

    /// Size the preview takes while resting: room for the open panel and its shadow. It grows while a
    /// module shows its taller panel (e.g. a Shelf item opened), and shrinks back after.
    public static func restingSize(screenWidth: CGFloat) -> CGSize {
        NotchPreviewHost.layout(screenWidth: screenWidth).windowFrame(for: .expanded).size
    }

    public var body: some View {
        let model = host.model
        NotchPreviewRepresentable(host: host)
            .frame(width: host.width, height: host.height, alignment: .top)
            .onChange(of: behavior, initial: true) { model.behavior = behavior }
            .onChange(of: module.map(ObjectIdentifier.init), initial: true) { model.module = module }
            .onChange(of: model.state) { onStateChange?(model.state, model.lastChangeWasClick) }
            .onAppear { if let startState { model.transition(to: startState) } }
            // Gone from the page: let go of the module (closes its menus) and settle.
            .onDisappear {
                model.reset()
                model.module = nil
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Notch preview"))
    }
}

/// Owns the preview's model and its AppKit view, and maps the real pointer onto the pretend screen.
@MainActor
@Observable
final class NotchPreviewHost {
    let model: NotchViewModel
    let width: CGFloat
    /// Height of the preview on the page: the open panel's, or the tall panel's while it shows.
    private(set) var height: CGFloat
    @ObservationIgnored let router: NotchDropRouter
    @ObservationIgnored weak var view: NotchContainerView?
    @ObservationIgnored private var mouseMonitor: Any?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private let restingHeight: CGFloat

    static func layout(screenWidth: CGFloat) -> NotchLayout {
        NotchLayout(geometry: NotchGeometry.simulated(in: CGRect(x: 0, y: 0, width: screenWidth, height: 400)))
    }

    init(behavior: NotchBehavior, screenWidth: CGFloat, acceptsDragSource: @escaping @MainActor (Any?) -> Bool) {
        let layout = Self.layout(screenWidth: screenWidth)
        router = NotchDropRouter(acceptsSource: acceptsDragSource)
        restingHeight = layout.windowFrame(for: .expanded).height
        height = restingHeight
        width = layout.largestWindowSize.width
        // The model needs the pointer before `self` exists: it asks through a reference filled in below.
        let reference = HostReference()
        model = NotchViewModel(
            layout: layout,
            behavior: behavior,
            pointerLocation: { reference.host?.pointerOnPretendScreen() ?? .zero },
            isMissionControlActive: { false }
        )
        reference.host = self
        router.model = model
        model.fitWindow = { [weak self] state in self?.fit(state) }
        model.requestKeyFocus = { [weak self] in self?.takeKeyFocus() }
        model.releaseKeyFocus = { [weak self] in self?.releaseKeyFocus() }
    }

    /// Grows the preview with the tall panel, and shrinks it back once the panel has.
    private func fit(_ state: NotchState) {
        let needed = max(restingHeight, model.layout.windowFrame(for: state).height)
        guard needed != height else { return }
        withAnimation(NotchViewModel.tallAnimation) { height = needed }
    }

    /// The real pointer in the pretend screen's coordinates (y up), so "is the pointer still on the
    /// notch?" checks see where it really is. The notch hangs from the top centre of the view.
    private func pointerOnPretendScreen() -> CGPoint {
        guard let view, let window = view.window else { return CGPoint(x: -10_000, y: -10_000) }
        let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let screen = model.layout.geometry.screenFrame
        let top = view.isFlipped ? view.bounds.minY : view.bounds.maxY
        let below = view.isFlipped ? point.y - top : top - point.y
        return CGPoint(x: screen.midX + point.x - view.bounds.midX, y: screen.maxY - below)
    }

    // MARK: Keys and clicks in the host window

    private func takeKeyFocus() {
        guard let view, let window = view.window else { return }
        if !(window.firstResponder.map { ($0 as? NSView)?.isDescendant(of: view) ?? false } ?? false) {
            window.makeFirstResponder(view)
        }
    }

    private func releaseKeyFocus() {
        guard let view, let window = view.window, isFocused(in: window, view: view) else { return }
        window.makeFirstResponder(nil)
    }

    private func isFocused(in window: NSWindow, view: NSView) -> Bool {
        (window.firstResponder as? NSView)?.isDescendant(of: view) ?? false
    }

    /// Watches the preview's window while it's in one: keys go to the notch first while it has focus
    /// (like the real notch panel), and a click elsewhere in the window counts as clicking away.
    /// Event monitors only; nothing runs between events.
    func windowChanged() {
        removeMonitors()
        guard let view, view.window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, let view = self.view, let window = view.window, event.window === window,
                      self.isFocused(in: window, view: view), self.model.state == .expanded else { return false }
                return self.model.handleKey(event)
            }
            return handled ? nil : event
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let view = self.view, let window = view.window, event.window === window else { return }
                let point = view.convert(event.locationInWindow, from: nil)
                if !view.bounds.contains(point) {
                    self.model.module?.clickedOutsidePreview()
                    self.releaseKeyFocus()
                }
            }
            return event
        }
    }

    func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        mouseMonitor = nil
    }
}

@MainActor
private final class HostReference {
    weak var host: NotchPreviewHost?
}

/// The preview's AppKit side: the same drop-target container the real notch uses, hosting `NotchView`.
private struct NotchPreviewRepresentable: NSViewRepresentable {
    let host: NotchPreviewHost

    func makeNSView(context: Context) -> NotchContainerView {
        let hosting = NSHostingView(rootView: NotchView(model: host.model))
        hosting.sizingOptions = []
        let container = NotchContainerView(content: hosting, contentSize: host.model.layout.largestWindowSize)
        container.dropDelegate = host.router
        container.acceptsKeyFocus = true
        // Draws only inside the preview, like the real notch window clips to its frame.
        container.clipsToBounds = true
        container.onWindowChange = { [weak host, weak container] in
            host?.view = container
            host?.windowChanged()
        }
        host.view = container
        return container
    }

    func makeCoordinator() -> NotchPreviewHost { host }

    func updateNSView(_ view: NotchContainerView, context: Context) {}

    static func dismantleNSView(_ view: NotchContainerView, coordinator: NotchPreviewHost) {
        view.onWindowChange = nil
        coordinator.removeMonitors()
    }
}
