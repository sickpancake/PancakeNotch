import SwiftUI

/// Root view of the notch window: the black notch outline, anchored to the top center,
/// morphing between states and revealing its content.
struct NotchView: View {
    let model: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = model.layout
        let state = model.state
        let shape = NotchShape(layout.radii(for: state))
        let size = layout.shapeSize(for: state)

        ZStack(alignment: .top) {
            Color.black
            content(layout: layout, state: state)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        .shadow(color: .black.opacity(state == .expanded ? 0.5 : 0), radius: 14, y: 6)
        .onHover { model.hoverChanged($0) }
        .onTapGesture { model.open() }
        .accessibilityElement(children: state == .expanded ? .contain : .ignore)
        .accessibilityLabel(Text("PancakeNotch"))
        .accessibilityHint(state == .expanded ? Text("") : Text("Opens the notch"))
        .accessibilityAddTraits(state == .expanded ? [] : .isButton)
        .accessibilityAction { model.open() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Content is laid out at its final size and revealed by the morphing outline,
    /// so nothing reflows mid-animation.
    @ViewBuilder
    private func content(layout: NotchLayout, state: NotchState) -> some View {
        switch state {
        case .closed:
            EmptyView()
        case .compact:
            CompactPlaceholderView(layout: layout)
                .frame(width: layout.bodySize(for: .compact).width, height: layout.bodySize(for: .compact).height)
                .transition(.opacity)
        case .expanded:
            ExpandedPlaceholderView(layout: layout)
                .frame(width: layout.bodySize(for: .expanded).width, height: layout.bodySize(for: .expanded).height)
                .transition(reduceMotion ? .opacity : .blurReveal)
        }
    }
}

/// Expanded panel shown until modules exist (Shelf arrives in M2, Now Playing in M3).
private struct ExpandedPlaceholderView: View {
    let layout: NotchLayout

    var body: some View {
        let notch = layout.geometry.notchRect.size
        VStack(spacing: 0) {
            // Top band beside the hardware notch; nothing may sit under the cutout itself.
            HStack(spacing: 0) {
                Text("PancakeNotch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: notch.width)
                Color.clear.frame(maxWidth: .infinity)
            }
            .frame(height: notch.height)
            .padding(.horizontal, 20)

            VStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white.opacity(0.4))
                    .accessibilityHidden(true)
                Text("No modules yet")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Now Playing and the Shelf are on the way.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 12)
        }
    }
}

/// Compact ears shown only via `PANCAKENOTCH_DEBUG_STATE=compact` until a module supplies real ones.
private struct CompactPlaceholderView: View {
    let layout: NotchLayout

    var body: some View {
        let ear = layout.compactEarWidth
        let height = layout.geometry.notchRect.height
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.18))
                .overlay(Image(systemName: "music.note").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)))
                .frame(width: height - 12, height: height - 12)
                .frame(width: ear)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach([0.45, 0.8, 0.6, 0.35], id: \.self) { level in
                    Capsule().fill(.white.opacity(0.7)).frame(width: 2.5, height: (height - 16) * level)
                }
            }
            .frame(width: ear)
        }
        .accessibilityHidden(true)
    }
}

private extension AnyTransition {
    /// Content fades in from a soft blur while growing down from the notch.
    static var blurReveal: AnyTransition {
        .modifier(
            active: BlurRevealModifier(progress: 0),
            identity: BlurRevealModifier(progress: 1)
        )
    }
}

private struct BlurRevealModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: (1 - progress) * 10)
            .scaleEffect(x: 1, y: 0.6 + 0.4 * progress, anchor: .top)
            .opacity(progress)
    }
}
