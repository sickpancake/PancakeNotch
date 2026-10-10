import SwiftUI

/// Root view of the notch window: the black notch outline, anchored to the top center,
/// morphing between states and revealing its content.
struct NotchView: View {
    let model: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = model.state
        ZStack(alignment: .top) {
            if reduceMotion {
                // Reduce Motion: cross-fade between states instead of morphing the outline.
                notch(state: state)
                    .id(state)
                    .transition(.opacity)
            } else {
                notch(state: state)
            }
        }
        .onHover { model.hoverChanged($0) }
        .onTapGesture { model.tap() }
        .accessibilityElement(children: state == .expanded ? .contain : .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(state == .expanded ? [] : .isButton)
        .accessibilityAction { model.open() }
        .accessibilityAction(named: Text("Close")) { model.close() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The window sits over the notch, which AppKit reports as unsafe area; draw into it anyway.
        .ignoresSafeArea()
    }

    private var accessibilityLabel: String {
        guard model.state != .expanded, let status = model.module?.accessibilityStatus else { return "PancakeNotch" }
        return "PancakeNotch, " + status
    }

    private func notch(state: NotchState) -> some View {
        let layout = model.layout
        let shape = NotchShape(layout.radii(for: state))
        let size = layout.shapeSize(for: state)
        return ZStack(alignment: .top) {
            Color.black
            content(layout: layout, state: state)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        .shadow(color: .black.opacity(state == .expanded ? 0.5 : 0), radius: 14, y: 6)
    }

    /// Content is laid out at its final size and revealed by the morphing outline,
    /// so nothing reflows mid-animation.
    @ViewBuilder
    private func content(layout: NotchLayout, state: NotchState) -> some View {
        switch state {
        case .compact:
            if let ears = model.module?.compactView(layout: layout) {
                ears
                    .frame(width: layout.bodySize(for: .compact).width, height: layout.bodySize(for: .compact).height)
                    .transition(reduceMotion ? .opacity : .earsTuck)
            } else if model.isPinned {
                CompactPlaceholderView(layout: layout)
                    .frame(width: layout.bodySize(for: .compact).width, height: layout.bodySize(for: .compact).height)
                    .transition(.opacity)
            }
        case .closed:
            EmptyView()
        case .expanded:
            Group {
                if let module = model.module {
                    module.expandedView(layout: layout)
                } else {
                    ExpandedPlaceholderView(layout: layout)
                }
            }
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
                Text("Turn on the Shelf on the Modules page. Now Playing is on the way.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 12)
        }
    }
}

/// Sample compact ears, shown only via `PANCAKENOTCH_DEBUG_STATE=compact` until a module supplies real ones.
private struct CompactPlaceholderView: View {
    let layout: NotchLayout

    var body: some View {
        let ear = layout.compactEarWidth
        let height = layout.bodySize(for: .compact).height
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

private extension AnyTransition {
    /// The ears' content slides in toward the notch and blurs away as they shrink (and back out as they
    /// grow), so closing reads even on a black background where the black ears themselves can't be seen.
    static var earsTuck: AnyTransition {
        .modifier(active: EarsTuckModifier(progress: 0), identity: EarsTuckModifier(progress: 1))
    }
}

private struct EarsTuckModifier: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 0.3 + 0.7 * progress, y: 0.5 + 0.5 * progress, anchor: .center)
            .blur(radius: (1 - progress) * 4)
            .opacity(progress)
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
