import SwiftUI

// Controls shared by the modules' open views, so they all press and look the same.

/// Buttons shrink a touch while pressed (dim instead with Reduce Motion).
public struct PressableStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Pressable(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct Pressable: View {
        let label: Configuration.Label
        let isPressed: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .scaleEffect(isPressed && !reduceMotion ? 0.9 : 1)
                .opacity(isPressed && reduceMotion ? 0.6 : 1)
                .animation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        }
    }
}

/// A capsule button for the notch: white with black text when it's the main action.
public struct NotchPill: View {
    let title: String
    var symbol: String?
    var prominent = false
    let action: () -> Void
    @State private var isHovered = false

    public init(title: String, symbol: String? = nil, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.prominent = prominent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9.5, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(prominent ? .black : .white)
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background(prominent ? .white.opacity(isHovered ? 0.88 : 1) : .white.opacity(isHovered ? 0.2 : 0.13), in: Capsule())
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
    }
}
