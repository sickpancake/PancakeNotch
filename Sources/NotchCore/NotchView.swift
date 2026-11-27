import SwiftUI

/// Root view of the notch window: the black notch outline, anchored to the top center,
/// morphing between states and revealing its content.
struct NotchView: View {
    let model: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The bar's selection capsule glides between its buttons.
    @Namespace private var barHighlight

    var body: some View {
        let state = model.state
        ZStack(alignment: .top) {
            if reduceMotion {
                // Reduce Motion: cross-fade between states instead of morphing the outline. A peek
                // strip coming or going under the ears cross-fades too, rather than the outline growing.
                notch(state: state)
                    .id(OutlineID(state: state, isPeeking: state == .compact && model.layout.isPeeking))
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
        var statuses = model.rankedModules.compactMap(\.accessibilityStatus)
        if let overflow = model.earOverflow, model.state == .compact {
            statuses.append(overflow.count == 1
                ? String(localized: "1 more active module", comment: "Ear overflow chip")
                : String(localized: "\(overflow.count) more active modules", comment: "Ear overflow chip"))
        }
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
                CompactEarsView(left: ears.left, right: ears.right,
                                overflow: model.earOverflow,
                                isAsleep: model.earsAsleep,
                                layout: layout, state: state, reduceMotion: reduceMotion)
            }
            if state == .compact, let peek = model.peekView {
                peek
                    .frame(width: layout.bodySize(for: .compact).width, height: NotchLayout.peekStripHeight)
                    .frame(width: size.width)
                    .onHover { _ in model.updatePeekHover() }
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
            let fit = NotchModuleBar.fit(for: model)
            let visiting = model.visitingModule
            let body = layout.bodySize(for: .expanded)
            let notch = layout.geometry.notchRect
            ZStack(alignment: .topLeading) {
                Group {
                    if !model.showsModule {
                        NotchHubPager(model: model, layout: layout)
                            .transition(reduceMotion ? .opacity : .entrance(model.entrance))
                    } else if let module = model.selectedModule {
                        module.expandedView(layout: layout)
                            .id(module.moduleID)
                            .transition(reduceMotion ? .opacity : .entrance(model.entrance))
                    } else {
                        ExpandedPlaceholderView(layout: layout)
                    }
                }
                .environment(\.notchModuleBarWidth, barWidth)
                .environment(\.notchVisitingTabWidth, visiting == nil ? 0 : NotchModuleBar.visitingTabRoom(fit))
                if model.showsModuleBar {
                    NotchModuleBar(model: model, highlight: barHighlight)
                        .frame(height: notch.height)
                        .padding(.leading, NotchModuleBar.leadingInset)
                        .transition(.opacity)
                }
                if let visiting {
                    NotchVisitingTab(model: model, module: visiting, highlight: barHighlight, width: fit.buttonWidth)
                        .frame(height: notch.height)
                        .padding(.leading, (body.width + notch.width) / 2 + NotchModuleBar.visitingGap)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .frame(width: layout.bodySize(for: .expanded).width, height: layout.bodySize(for: .expanded).height, alignment: .topLeading)
            .transition(reduceMotion ? .opacity : .blurReveal)
        }
    }
}

/// Home and the Library side by side, sliding as one: between them a swipe moves the pages with the fingers,
/// and the buttons glide them (ADR-0045). At rest only the current one is drawn.
private struct NotchHubPager: View {
    let model: NotchViewModel
    let layout: NotchLayout

    var body: some View {
        let pages = model.hubPages
        let width = layout.bodySize(for: .expanded).width
        let current = model.currentPlace.isHub ? model.currentPlace : .home
        let position = model.hubPosition ?? CGFloat(pages.firstIndex(of: current) ?? 0)
        let shown = model.hubPosition == nil ? [current] : pages
        // A page that comes in starts beside the one the move started from.
        let origin = CGFloat(model.hubOrigin ?? Int(position.rounded()))
        ZStack(alignment: .topLeading) {
            ForEach(shown, id: \.self) { place in
                let index = CGFloat(pages.firstIndex(of: place) ?? 0)
                page(place)
                    .offset(x: (index - position) * width)
                    .transition(.asymmetric(insertion: .offset(x: (position - origin) * width), removal: .identity))
                    // Only the page in front takes clicks and VoiceOver.
                    .allowsHitTesting(place == current)
                    .accessibilityHidden(place != current)
            }
        }
        .frame(width: width, height: layout.bodySize(for: .expanded).height, alignment: .topLeading)
    }

    @ViewBuilder
    private func page(_ place: NotchPlace) -> some View {
        switch place {
        case .library: NotchLibraryView(model: model, layout: layout)
        default: NotchHomeView(model: model, layout: layout)
        }
    }
}

/// The module showing has no tab in the bar: its icon sits just right of the camera, lit like a selected
/// tab (ADR-0045). A click or right-click shows its menu, where it can be made a favorite.
private struct NotchVisitingTab: View {
    let model: NotchViewModel
    let module: any NotchModule
    let highlight: Namespace.ID
    let width: CGFloat

    var body: some View {
        NotchBarButton(symbol: module.symbol, isSelected: true, highlight: highlight, width: width, glides: false) {}
            .moduleMenu(model: model, moduleID: module.moduleID, onClick: true)
            .help(Text(help))
            .accessibilityLabel(Text(module.title))
            .accessibilityAddTraits(.isSelected)
            .accessibilityHint(Text("Showing now. It has no tab in the bar."))
            .moduleMenuAccessibilityActions(model: model, moduleID: module.moduleID)
    }

    private var help: String {
        guard model.editsFavorites else { return module.title }
        return model.canAddFavorite
            ? String(localized: "\(module.title) · Click to add it to Favorites", comment: "Tooltip of the icon beside the camera")
            : String(localized: "\(module.title) · \(LibraryText.noRoom)", comment: "Tooltip of the icon beside the camera with a full bar")
    }
}

/// What the Reduce Motion cross-fade swaps on: the state, and whether Compact shows a peek strip.
private struct OutlineID: Hashable {
    let state: NotchState
    let isPeeking: Bool
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

    /// A page arriving in the open notch comes from where the person looked: from its side of the bar for a
    /// swipe, an arrow key or a tab; grown a little from the bar's corner for Home or the Library from their
    /// buttons; grown out of the tile clicked in the Library. The page leaving always blurs away where it is,
    /// so a change of direction never slides it the wrong way.
    static func entrance(_ entrance: NotchEntrance) -> AnyTransition {
        let insertion: AnyTransition = switch entrance {
        case .slide(let forward):
            .modifier(active: SlideBlurModifier(offset: forward ? 34 : -34, blur: 6, opacity: 0, scale: 1),
                      identity: SlideBlurModifier(offset: 0, blur: 0, opacity: 1, scale: 1))
        case .reveal:
            .modifier(active: SlideBlurModifier(offset: 0, blur: 5, opacity: 0, scale: 0.96),
                      identity: SlideBlurModifier(offset: 0, blur: 0, opacity: 1, scale: 1))
        case .grow(let anchor):
            .modifier(active: SlideBlurModifier(offset: 0, blur: 4, opacity: 0, scale: 0.4, anchor: anchor),
                      identity: SlideBlurModifier(offset: 0, blur: 0, opacity: 1, scale: 1, anchor: anchor))
        }
        return .asymmetric(
            insertion: insertion,
            removal: .modifier(
                active: SlideBlurModifier(offset: 0, blur: 6, opacity: 0, scale: 0.97),
                identity: SlideBlurModifier(offset: 0, blur: 0, opacity: 1, scale: 1)
            )
        )
    }
}

private struct SlideBlurModifier: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat
    var anchor: UnitPoint = .topLeading

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .scaleEffect(scale, anchor: anchor)
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
    /// Active modules that didn't fit: counted ("+2") at the outer edge of the ear on `overflow.side`.
    let overflow: NotchViewModel.EarOverflow?
    /// Settled in Closed: the frames stay (so waking slides the ears out as before) but hold nothing,
    /// and waking isn't a change of ears to animate.
    let isAsleep: Bool
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
            ear(left, count: count(in: left, side: .left), outerEdge: .leading,
                width: width, height: height)
                .offset(x: tuck)
            Spacer(minLength: 0)
            ear(right, count: count(in: right, side: .right), outerEdge: .trailing,
                width: width, height: height)
                .offset(x: -tuck)
        }
        .frame(width: layout.bodySize(for: .compact).width, height: height)
        // Fading out to Closed waits until the content is under the notch, so the slide stays visible.
        .animation(fade(isShown: isShown)) { $0.opacity(isShown ? 1 : 0) }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85), value: [left?.id, right?.id])
        // The count fades in or out and the ear's content makes room for it; a new number rolls.
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.25), value: overflow)
        .allowsHitTesting(false)
        .accessibilityHidden(!isShown)
    }

    /// The "+n" shown in an ear: the overflow count on its side, plus what the ear's module folded into it
    /// (the Timer's other timers). Only in an ear that shows a module, never alone in an empty one.
    private func count(in slot: NotchViewModel.EarSlot?, side: NotchViewModel.EarOverflow.Side) -> Int? {
        guard let slot, let overflow, overflow.side == side else { return nil }
        return overflow.count + slot.mergedCount
    }

    /// One ear: the module's content, and with `count` the "+n" overflow count at the ear's outer edge
    /// (inside the outline, never under the camera). The content keeps the rest of the ear: its module was
    /// laid out at `NotchLayout.compactEarContentWidth` for it.
    private func ear(_ slot: NotchViewModel.EarSlot?, count: Int?, outerEdge: HorizontalEdge,
                     width: CGFloat, height: CGFloat) -> some View {
        let shown = isAsleep ? nil : count
        let reserve = shown == nil ? 0 : NotchLayout.earCountWidth
        return HStack(spacing: 0) {
            if outerEdge == .leading { countView(shown, hugging: .trailing, height: height) }
            ZStack {
                if let slot, !isAsleep {
                    slot.view
                        .id(slot.id)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .frame(width: width - reserve, height: height)
            if outerEdge == .trailing { countView(shown, hugging: .leading, height: height) }
        }
        .frame(width: width, height: height, alignment: outerEdge == .leading ? .trailing : .leading)
    }

    /// "+2": the same quiet style as the Timer's count of other timers, so every "+n" in the ears reads alike.
    /// It leans toward the module's content (`hugging`), clear of the outline's rounded outer edge.
    @ViewBuilder
    private func countView(_ count: Int?, hugging edge: Alignment, height: CGFloat) -> some View {
        if let count {
            Text(verbatim: "+\(count)")
                .font(.system(size: 7.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize()
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(count)))
                .frame(width: NotchLayout.earCountWidth, height: height, alignment: edge)
                .transition(.opacity)
        }
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
