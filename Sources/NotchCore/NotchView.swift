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
        guard model.state != .expanded else { return "PancakeNotch" }
        let statuses = model.rankedModules.compactMap(\.accessibilityStatus)
        return (["PancakeNotch"] + statuses).joined(separator: ", ")
    }

    private func notch(state: NotchState) -> some View {
        let layout = model.layout
        let shape = NotchShape(layout.radii(for: state))
        let size = layout.shapeSize(for: state)
        let ears = model.ears(layout: layout)
        return ZStack(alignment: .top) {
            Color.black
            content(layout: layout, state: state)
            if ears.left != nil || ears.right != nil {
                CompactEarsView(left: ears.left, right: ears.right, layout: layout, state: state, reduceMotion: reduceMotion)
            }
            if state == .compact, let peek = model.peekView {
                peek
                    .frame(width: layout.bodySize(for: .compact).width, height: NotchLayout.peekStripHeight)
                    .padding(.top, layout.geometry.compactHeight)
                    .transition(.opacity)
            }
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
            // A module's ears are drawn by `CompactEarsView` in every state.
            if model.modules.isEmpty, model.isPinned {
                CompactPlaceholderView(layout: layout)
                    .frame(width: layout.bodySize(for: .compact).width, height: layout.bodySize(for: .compact).height)
                    .transition(.opacity)
            }
        case .closed:
            EmptyView()
        case .expanded:
            let barWidth = model.showsModuleBar ? NotchModuleBar.width(for: model) : 0
            ZStack(alignment: .topLeading) {
                Group {
                    if model.showsMenu {
                        NotchMenuView(model: model, layout: layout)
                            .transition(reduceMotion ? .opacity : .menuReveal)
                    } else if let module = model.selectedModule {
                        module.expandedView(layout: layout)
                            .id(module.moduleID)
                            .transition(reduceMotion ? .opacity : .moduleSwitch(forward: model.switchedForward))
                    } else {
                        ExpandedPlaceholderView(layout: layout)
                    }
                }
                .environment(\.notchModuleBarWidth, barWidth)
                if model.showsModuleBar {
                    NotchModuleBar(model: model)
                        .frame(height: layout.geometry.notchRect.height)
                        .padding(.leading, NotchModuleBar.leadingInset)
                        .transition(.opacity)
                }
            }
            .frame(width: layout.bodySize(for: .expanded).width, height: layout.bodySize(for: .expanded).height, alignment: .topLeading)
            .transition(reduceMotion ? .opacity : .blurReveal)
        }
    }
}

/// Expanded panel shown while every module is switched off.
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
                Text("No modules on")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Turn on Now Playing or the Shelf on the Modules page.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 12)
        }
    }
}

/// Sample compact ears, shown only via `PANCAKENOTCH_DEBUG_STATE=compact` while no module is on.
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

    /// Switching modules: the new one slides in from the side it lives on, the old one blurs away
    /// where it is (so a change of direction never slides it the wrong way).
    static func moduleSwitch(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SlideBlurModifier(offset: forward ? 34 : -34, blur: 6, opacity: 0, scale: 1),
                identity: SlideBlurModifier(offset: 0, blur: 0, opacity: 1, scale: 1)
            ),
            removal: .modifier(
                active: SlideBlurModifier(offset: 0, blur: 6, opacity: 0, scale: 0.97),
                identity: SlideBlurModifier(offset: 0, blur: 0, opacity: 1, scale: 1)
            )
        )
    }

    /// The Module Menu grows a little from the top-left corner, where its button is.
    static var menuReveal: AnyTransition {
        .modifier(
            active: SlideBlurModifier(offset: 0, blur: 5, opacity: 0, scale: 0.96),
            identity: SlideBlurModifier(offset: 0, blur: 0, opacity: 1, scale: 1)
        )
    }
}

private struct SlideBlurModifier: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .scaleEffect(scale, anchor: .topLeading)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

/// The ears' content, kept in every state so it can move: it slides out from under the notch as the ears
/// grow, and back under it as they shrink, where the hardware cutout hides it. That reads even on a black
/// app, where the black ears themselves can't be seen. Hidden (and not clickable) unless Compact. When an
/// ear changes hands (another module becomes active), the old content shrinks away and the new one grows in.
private struct CompactEarsView: View {
    let left: NotchViewModel.EarSlot?
    let right: NotchViewModel.EarSlot?
    let layout: NotchLayout
    let state: NotchState
    let reduceMotion: Bool

    var body: some View {
        let width = layout.compactEarWidth
        // The ears are as tall as the menu bar even while a peek strip hangs below them.
        let height = layout.geometry.compactHeight
        let isShown = state == .compact
        // Closed: tucked in toward the middle, under the notch. Reduce Motion only fades.
        let tuck = state == .closed && !reduceMotion ? width + 8 : 0
        HStack(spacing: 0) {
            ear(left, width: width, height: height)
                .offset(x: tuck)
            Spacer(minLength: 0)
            ear(right, width: width, height: height)
                .offset(x: -tuck)
        }
        .frame(width: layout.bodySize(for: .compact).width, height: height)
        // Fading out to Closed waits until the content is under the notch, so the slide stays visible.
        .animation(fade(isShown: isShown)) { $0.opacity(isShown ? 1 : 0) }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85), value: [left?.id, right?.id])
        .allowsHitTesting(false)
        .accessibilityHidden(!isShown)
    }

    private func ear(_ slot: NotchViewModel.EarSlot?, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if let slot {
                slot.view
                    .id(slot.id)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(width: width, height: height)
    }

    private func fade(isShown: Bool) -> Animation {
        if isShown { return .easeOut(duration: 0.18) }
        return state == .closed && !reduceMotion ? .easeIn(duration: 0.12).delay(0.3) : .easeOut(duration: 0.12)
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
