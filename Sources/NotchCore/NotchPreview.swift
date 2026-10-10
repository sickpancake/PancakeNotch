import SwiftUI

/// A working miniature of the notch for the app window: hover or click it to try the
/// current behavior settings. It runs its own model, separate from the real notch.
public struct NotchPreview: View {
    private let behavior: NotchBehavior
    private let module: (any NotchModule)?
    @State private var model: NotchViewModel

    /// - Parameters:
    ///   - behavior: hover delays and haptics, normally the user's current settings.
    ///   - screenWidth: width of the pretend screen; the expanded panel is clamped to it.
    ///   - module: what the preview shows inside (e.g. a sample Shelf); `nil` shows the placeholder.
    public init(behavior: NotchBehavior, screenWidth: CGFloat = 640, module: (any NotchModule)? = nil) {
        self.behavior = behavior
        self.module = module
        let geometry = NotchGeometry.simulated(in: CGRect(x: 0, y: 0, width: screenWidth, height: 400))
        // The pretend screen has no real pointer position; hover events drive it.
        _model = State(initialValue: NotchViewModel(
            layout: NotchLayout(geometry: geometry),
            behavior: behavior,
            pointerLocation: { .zero }
        ))
    }

    /// Size the preview needs: room for the expanded panel and its shadow (the preview never grows tall).
    public var size: CGSize { model.layout.windowFrame(for: .expanded).size }

    public var body: some View {
        NotchView(model: model)
            .frame(width: size.width, height: size.height, alignment: .top)
            .onChange(of: behavior, initial: true) { model.behavior = behavior }
            .onChange(of: module.map(ObjectIdentifier.init), initial: true) { model.module = module }
            .accessibilityLabel(Text("Notch preview"))
    }
}
