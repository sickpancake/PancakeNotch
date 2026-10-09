import SwiftUI

/// A working miniature of the notch for the app window: hover or click it to try the
/// current behavior settings. It runs its own model, separate from the real notch.
public struct NotchPreview: View {
    private let behavior: NotchBehavior
    @State private var model: NotchViewModel

    /// - Parameters:
    ///   - behavior: hover delays and haptics, normally the user's current settings.
    ///   - screenWidth: width of the pretend screen; the expanded panel is clamped to it.
    public init(behavior: NotchBehavior, screenWidth: CGFloat = 640) {
        self.behavior = behavior
        let geometry = NotchGeometry.simulated(in: CGRect(x: 0, y: 0, width: screenWidth, height: 400))
        // The pretend screen has no real pointer position, so a click-shrunk panel just lingers, then closes.
        _model = State(initialValue: NotchViewModel(
            layout: NotchLayout(geometry: geometry),
            behavior: behavior,
            pointerLocation: { .zero }
        ))
    }

    /// Size the preview needs: room for the expanded panel and its shadow.
    public var size: CGSize { model.layout.largestWindowSize }

    public var body: some View {
        NotchView(model: model)
            .frame(width: size.width, height: size.height, alignment: .top)
            .onChange(of: behavior, initial: true) { model.behavior = behavior }
            .accessibilityLabel(Text("Notch preview"))
    }
}
