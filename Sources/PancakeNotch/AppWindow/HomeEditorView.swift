import NotchCore
import SwiftUI

/// The app window's Home page: the editor for the notch's Home (ADR-0042). It's always in edit mode,
/// phone style: widgets wiggle, carry a remove badge and a size control, and move by dragging (or by
/// keyboard and VoiceOver). Every change goes straight to the real notch; Undo and Redo walk it back.
///
/// The editable grid is its own view drawing the same widget views as the notch, with practice data,
/// and dragging is a plain gesture inside this page: nothing goes on the pasteboard, so a widget can
/// never land in the Shelf or anywhere outside the editor.
struct HomeEditorView: View {
    let context: AppContext
    @State private var practice = PracticeSet()
    @State private var history = HomeHistory()
    @State private var page = 0
    @State private var drag: HomeEditorDrag?
    /// Where a cancelled drag started: the rest of that same gesture is ignored, so it can't come back or land.
    @State private var cancelledDragStart: CGPoint?
    @State private var gridFrame: CGRect = .zero
    @State private var tabFrames: [Int: CGRect] = [:]
    @State private var note: String?
    @State private var noteTask: Task<Void, Never>?
    @State private var confirmsReset = false
    /// The widget that has the keyboard (outlined); a click anywhere else on the page, or Esc, lets go.
    @FocusState private var focusedWidget: HomeWidgetKind?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive

    nonisolated static let space = "homeEditor"

    private var home: HomeSettings { context.home }

    /// The layout as it would be if the dragged widget landed where it is now.
    private var shownLayout: HomeLayout { drag?.preview ?? home.layout }

    var body: some View {
        AppPage(
            title: String(localized: "Home"),
            subtitle: String(localized: "Arrange the widgets Home shows in the open notch. Drag them around, or add more from below. Changes show in the notch right away.")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                toolbar
                canvas
                noteLine
            }
            gallery
        }
        // A click on anything that isn't a widget or a control ends editing the selected widget.
        .contentShape(Rectangle())
        .onTapGesture { focusedWidget = nil }
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .topLeading) { floatingWidget }
        .onAppear {
            practice.update(Self.practiceKinds(for: context))
            home.hasSeenIntro = true // the notch's "Home is new" hint has done its job
        }
        .onDisappear {
            cancelDrag()
            practice.close()
            noteTask?.cancel()
        }
        // Escape, or the window going to the background, drops a drag without changing anything.
        .onExitCommand {
            if drag != nil { cancelDrag() } else { focusedWidget = nil }
        }
        .onChange(of: appearsActive) { _, active in if !active { cancelDrag() } }
        .onChange(of: Self.practiceKinds(for: context)) { _, kinds in practice.update(kinds) }
        .confirmationDialog(
            String(localized: "Reset Home to the default layout?"),
            isPresented: $confirmsReset
        ) {
            Button(String(localized: "Reset"), role: .destructive) { replace(with: .default) }
        } message: {
            Text("Your widgets go back to where they started. You can undo this.")
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            pageTabs
            Spacer(minLength: 8)
            Button { undo() } label: {
                Label(String(localized: "Undo"), systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!history.canUndo)
            .help(Text("Undo (⌘Z)"))
            Button { redo() } label: {
                Label(String(localized: "Redo"), systemImage: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!history.canRedo)
            .help(Text("Redo (⇧⌘Z)"))
            Menu {
                Section(String(localized: "Start from a layout")) {
                    ForEach(HomePreset.allCases, id: \.self) { preset in
                        Button(preset.title) { replace(with: home.layout.applying(preset)) }
                    }
                }
                Divider()
                Button(String(localized: "Reset to Default…")) { confirmsReset = true }
            } label: {
                Text("Layouts")
            }
            .menuStyle(.button)
            .buttonStyle(PillButtonStyle())
            .fixedSize()
            .accessibilityLabel(Text("Layouts"))
            .accessibilityHint(Text("Fills Home with a ready-made layout, or resets it. You can undo either."))
        }
        .labelStyle(.iconOnly)
    }

    private var pageTabs: some View {
        HStack(spacing: 2) {
            ForEach(0..<HomeLayout.pageCount, id: \.self) { index in
                let isSelected = index == page
                let isEmpty = shownLayout.isPageEmpty(index)
                Button { page = index } label: {
                    Text("Page \(index + 1)")
                        .font(.app(size: 12.5, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.black : AppPalette.primaryText.opacity(isEmpty ? 0.5 : 0.85))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background {
                            if isSelected { Capsule().fill(AppPalette.ink) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { tabFrames[index] = $0 }
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityValue(Text(isEmpty ? String(localized: "Empty") : ""))
            }
        }
        .padding(2)
        .background(AppPalette.rail.opacity(0.5), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Pages"))
    }

    // MARK: Canvas

    /// A black panel like the open notch, with the grid of the page being edited.
    private var canvas: some View {
        GeometryReader { proxy in
            // As wide as the open notch gets (never wider), in the middle of the page.
            let width = min(proxy.size.width, NotchLayout.maxExpandedBodySize.width)
            let metrics = HomeEditorMetrics(width: width)
            ZStack(alignment: .topLeading) {
                grid(metrics: metrics)
                    .frame(width: metrics.grid.width, height: metrics.grid.height, alignment: .topLeading)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { gridFrame = $0 }
                    .padding(.horizontal, HomeWidgetMetrics.sidePadding)
                    .padding(.top, metrics.band)
                    .padding(.bottom, HomeWidgetMetrics.bottomPadding)
            }
            .frame(width: width, alignment: .topLeading)
            .background(.black, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AppPalette.hairline)
            }
            .frame(width: proxy.size.width)
        }
        .frame(height: HomeEditorMetrics.height)
    }

    private func grid(metrics: HomeEditorMetrics) -> some View {
        let cell = HomeWidgetMetrics.cellSize(in: metrics.grid)
        let resolver = HomeWidgetResolver(modules: practice.modules, arrangement: context.arrangement,
                                          extras: HomeExtras.practice(home: home))
        let layout = shownLayout
        let placements = layout.placements(onPage: page).filter { $0.kind != drag?.kind || drag?.landing != nil }
        // Only the free cells: the widgets' cards are see-through, so a cell under one would show.
        let taken = placements.reduce(into: Set<HomeCell>()) { $0.formUnion($1.cells) }
        let free = (0..<(HomeLayout.columns * HomeLayout.rows)).filter { index in
            !taken.contains(HomeCell(page: page, column: index / HomeLayout.rows, row: index % HomeLayout.rows))
        }
        return ZStack(alignment: .topLeading) {
            // The empty cells, faintly, so there's something to aim at.
            ForEach(free, id: \.self) { index in
                let frame = HomeWidgetMetrics.frame(column: index / HomeLayout.rows, row: index % HomeLayout.rows,
                                                    size: .small, cell: cell)
                RoundedRectangle(cornerRadius: HomeWidgetMetrics.cornerRadius, style: .continuous)
                    .fill(.white.opacity(0.03))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .accessibilityHidden(true)
            }
            ForEach(placements) { placement in
                let frame = HomeWidgetMetrics.frame(column: placement.slot.column, row: placement.slot.row,
                                                    size: placement.size, cell: cell)
                if placement.kind == drag?.kind {
                    // Where the dragged widget will land.
                    RoundedRectangle(cornerRadius: HomeWidgetMetrics.cornerRadius, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: HomeWidgetMetrics.cornerRadius, style: .continuous)
                                .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                } else {
                    EditableWidget(
                        placement: placement, frame: frame, resolver: resolver,
                        isOff: placement.kind.moduleID.map { !context.isEnabled($0) } ?? false,
                        isDimmed: drag != nil,
                        isLive: appearsActive && drag == nil,
                        wiggles: !reduceMotion && appearsActive && drag == nil,
                        actions: actions(for: placement),
                        focus: $focusedWidget
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .gesture(dragGesture(kind: placement.kind, size: placement.size, origin: frame, fromGallery: false))
                    .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25), value: layout)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: page)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Page \(page + 1) of Home"))
    }

    /// The widget under the pointer while dragging: lifted a little, slightly bigger, with a shadow.
    @ViewBuilder private var floatingWidget: some View {
        if let drag {
            let resolver = HomeWidgetResolver(modules: practice.modules, arrangement: context.arrangement,
                                              extras: HomeExtras.practice(home: home))
            let size = HomeWidgetMetrics.frame(column: 0, row: 0, size: drag.size,
                                               cell: HomeWidgetMetrics.cellSize(in: HomeEditorMetrics(width: gridFrame.width + 2 * HomeWidgetMetrics.sidePadding).grid)).size
            Group {
                if drag.kind.moduleID.map({ !context.isEnabled($0) }) ?? false {
                    HomeGhost(kind: drag.kind, size: size, open: nil)
                } else {
                    HomeWidgetCard(kind: drag.kind, size: size, opens: false) {
                        resolver.content(drag.kind, size: drag.size,
                                         context: HomeWidgetContext(size: size, isLive: false, isPractice: true))
                    } open: {}
                }
            }
            .background(.black, in: .rect(cornerRadius: HomeWidgetMetrics.cornerRadius, style: .continuous))
            .scaleEffect(reduceMotion ? 1 : 1.06)
            .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
            .opacity(reduceMotion ? 0.85 : 1)
            .offset(x: drag.location.x - drag.grab.x, y: drag.location.y - drag.grab.y)
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var noteLine: some View {
        if let note {
            Label(note, systemImage: "info.circle")
                .font(.app(size: 12.5, weight: .medium))
                .foregroundStyle(AppPalette.secondaryText)
                .transition(.opacity)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: Gallery

    private var gallery: some View {
        let kinds = HomeWidgetKind.allCases.filter { kind in kind.moduleID.map(context.isEnabled) ?? true }
        let resolver = HomeWidgetResolver(modules: practice.modules, arrangement: context.arrangement,
                                              extras: HomeExtras.practice(home: home))
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: String(localized: "Widgets"))
                .padding(.horizontal, 20)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(kinds) { kind in
                    GalleryItem(kind: kind, resolver: resolver, isPlaced: home.layout.contains(kind)) {
                        add(kind)
                    }
                    .gesture(dragGesture(kind: kind, size: kind.defaultSize, origin: nil, fromGallery: true),
                             including: home.layout.contains(kind) ? .none : .all)
                }
            }
            Text("Click a widget to put it in the first free spot, or drag it onto Home. Each widget can be on Home once. Widgets of modules that are off show up here once you turn them on.")
                .font(.app(size: 12.5))
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
    }

    // MARK: Dragging

    private func dragGesture(kind: HomeWidgetKind, size: HomeWidgetSize, origin: CGRect?, fromGallery: Bool) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if value.startLocation == cancelledDragStart { return }
                if drag == nil {
                    let cell = HomeWidgetMetrics.cellSize(in: gridFrame.size)
                    let widget = HomeWidgetMetrics.frame(column: 0, row: 0, size: size, cell: cell).size
                    // Hold it where it was grabbed; from the gallery, by its middle.
                    let grab = origin.map { CGPoint(x: value.startLocation.x - gridFrame.minX - $0.minX,
                                                    y: value.startLocation.y - gridFrame.minY - $0.minY) }
                        ?? CGPoint(x: widget.width / 2, y: widget.height / 2)
                    drag = HomeEditorDrag(kind: kind, size: size, fromGallery: fromGallery, start: value.startLocation,
                                          grab: grab, location: value.location)
                }
                dragMoved(to: value.location)
            }
            .onEnded { value in
                if value.startLocation == cancelledDragStart {
                    cancelledDragStart = nil
                    return
                }
                dragEnded()
            }
    }

    /// Drops the widget being dragged back where it was: nothing is saved and Undo gains nothing.
    private func cancelDrag() {
        guard let current = drag else { return }
        cancelledDragStart = current.start
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)) { drag = nil }
    }

    private func dragMoved(to location: CGPoint) {
        guard var current = drag else { return }
        current.location = location
        // Hovering a page tab turns to that page.
        if let tab = tabFrames.first(where: { $0.value.contains(location) })?.key, tab != page { page = tab }
        let topLeft = CGPoint(x: location.x - current.grab.x - gridFrame.minX, y: location.y - current.grab.y - gridFrame.minY)
        let cell = HomeWidgetMetrics.cellSize(in: gridFrame.size)
        let center = CGPoint(x: topLeft.x + cell.width / 2, y: topLeft.y + cell.height / 2)
        let overGrid = gridFrame.insetBy(dx: -cell.width / 2, dy: -cell.height / 2).contains(location)
        if overGrid {
            let slot = HomeSlot(
                page: page,
                column: Int((center.x / (cell.width + HomeWidgetMetrics.gap)).rounded(.down)),
                row: Int((center.y / (cell.height + HomeWidgetMetrics.gap)).rounded(.down))
            )
            current.landing = slot
            current.preview = current.fromGallery
                ? home.layout.previewInserting(current.kind, size: current.size, at: slot)
                : home.layout.previewMoving(current.kind, to: slot)
        } else {
            current.landing = nil
            current.preview = nil
        }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { drag = current }
    }

    private func dragEnded() {
        guard let current = drag else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)) {
            drag = nil
            if let slot = current.landing {
                let refusal = home.edit(&history) { layout in
                    current.fromGallery ? layout.inserting(current.kind, size: current.size, at: slot) : layout.moving(current.kind, to: slot)
                }
                if let refusal { show(refusal.message) }
            }
        }
    }

    // MARK: Changes

    private func actions(for placement: HomePlacement) -> HomeWidgetActions {
        HomeWidgetActions(
            remove: { change { .success($0.removing(placement.kind)) } },
            resize: { size in change { $0.resizing(placement.kind, to: size) } },
            nudge: { direction in change { $0.nudging(placement.kind, by: direction) } },
            moveToPage: { target in
                change { $0.movingToPage(placement.kind, page: target) }
                page = target
            },
            metric: HomeStatisticsMetric(saved: home.layout.statisticsMetric),
            setMetric: { metric in
                change { layout in
                    var next = layout
                    next.statisticsMetric = metric.rawValue
                    return .success(next)
                }
            }
        )
    }

    private func add(_ kind: HomeWidgetKind) {
        change { $0.adding(kind) }
        if let placed = home.layout.placement(of: kind) { page = placed.slot.page }
    }

    private func change(_ edit: (HomeLayout) -> Result<HomeLayout, HomeEditRefusal>) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)) {
            if let refusal = home.edit(&history, edit) { show(refusal.message) }
        }
    }

    private func replace(with layout: HomeLayout) {
        change { _ in .success(layout) }
        page = 0
    }

    private func undo() {
        guard let previous = history.undo(current: home.layout) else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { home.layout = previous }
    }

    private func redo() {
        guard let next = history.redo(current: home.layout) else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { home.layout = next }
    }

    /// Says why something didn't happen, for a few seconds (longer with VoiceOver).
    private func show(_ message: String) {
        noteTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { note = message }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        noteTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(NSWorkspace.shared.isVoiceOverEnabled ? 10 : 5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { note = nil }
        }
    }

    /// The practice modules the previews need: those whose module is switched on.
    static func practiceKinds(for context: AppContext) -> Set<PracticeKind> {
        let all: [(String, PracticeKind)] = [("nowPlaying", .nowPlaying), ("shelf", .shelf), ("agents", .agents),
                                             ("aiUsage", .aiUsage), ("timer", .timer), ("keepAwake", .keepAwake)]
        return Set(all.filter { context.isEnabled($0.0) }.map(\.1))
    }
}

/// A widget being dragged in the editor.
private struct HomeEditorDrag {
    let kind: HomeWidgetKind
    let size: HomeWidgetSize
    let fromGallery: Bool
    /// Where the gesture began, which tells it apart from the next one.
    let start: CGPoint
    /// Where the pointer holds the widget, from its top-left corner.
    let grab: CGPoint
    var location: CGPoint
    /// The cell its top-left corner would land on, or `nil` while it's away from the grid.
    var landing: HomeSlot?
    /// Home with the widget landed there and its neighbours moved aside; `nil` when it can't land.
    var preview: HomeLayout?
}

/// The editor's panel: as wide as the page allows (up to a real notch's 600), with a real notch's height.
private struct HomeEditorMetrics {
    static let band: CGFloat = 26
    static var height: CGFloat {
        band + HomeWidgetMetrics.gridArea(in: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))).height
            + HomeWidgetMetrics.bottomPadding
    }

    let band = Self.band
    let grid: CGSize

    init(width: CGFloat) {
        grid = CGSize(width: max(0, min(width, NotchLayout.maxExpandedBodySize.width) - 2 * HomeWidgetMetrics.sidePadding),
                      height: Self.height - Self.band - HomeWidgetMetrics.bottomPadding)
    }
}

/// What can be done to a placed widget, from its badge, its size control, its menu, the keyboard and
/// VoiceOver.
private struct HomeWidgetActions {
    let remove: @MainActor () -> Void
    let resize: @MainActor (HomeWidgetSize) -> Void
    let nudge: @MainActor (HomeNudge) -> Void
    let moveToPage: @MainActor (Int) -> Void
    /// The Statistics widget's number, and choosing another.
    let metric: HomeStatisticsMetric
    let setMetric: @MainActor (HomeStatisticsMetric) -> Void
}

/// A widget on the editor's grid: the real widget drawn with practice data, wiggling gently, with a
/// remove badge and a size control. Click it to give it the keyboard: arrows move it, Delete removes it.
private struct EditableWidget: View {
    let placement: HomePlacement
    let frame: CGRect
    let resolver: HomeWidgetResolver
    let isOff: Bool
    let isDimmed: Bool
    /// The previews tick (a running timer, the clock) only while the window is active and nothing is dragged.
    let isLive: Bool
    let wiggles: Bool
    let actions: HomeWidgetActions
    /// The page's choice of widget with the keyboard.
    var focus: FocusState<HomeWidgetKind?>.Binding
    @State private var isHovered = false
    /// The size list is open: the size button stays while the pointer is over the list.
    @State private var choosingSize = false

    private var isFocused: Bool { focus.wrappedValue == placement.kind }

    var body: some View {
        let kind = placement.kind
        face
            .allowsHitTesting(false)
            // The outline first, so the remove badge and the size button sit on top of it.
            .overlay {
                RoundedRectangle(cornerRadius: HomeWidgetMetrics.cornerRadius + 3, style: .continuous)
                    .strokeBorder(.white.opacity(isFocused ? 0.9 : 0), lineWidth: 1.5)
                    .padding(-3)
                    .animation(.easeOut(duration: 0.15), value: isFocused)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomTrailing) {
                // Only while pointed at or focused, so it doesn't cover the widget's words.
                if kind.sizes.count > 1, isHovered || isFocused || choosingSize {
                    sizeControl.padding(5).transition(.opacity)
                }
            }
            .overlay(alignment: .topLeading) { removeBadge.offset(x: -6, y: -6) }
            .modifier(Wiggle(isOn: wiggles, seed: kind.hashValue))
            .contentShape(.rect(cornerRadius: HomeWidgetMetrics.cornerRadius))
            .onHover { hovering in withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering } }
            .focusable()
            .focused(focus, equals: kind)
            .focusEffectDisabled()
            .onTapGesture { focus.wrappedValue = kind }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .delete, .deleteForward]) { press in
                switch press.key {
                case .leftArrow: actions.nudge(.left)
                case .rightArrow: actions.nudge(.right)
                case .upArrow: actions.nudge(.up)
                case .downArrow: actions.nudge(.down)
                default: actions.remove()
                }
                return .handled
            }
            .contextMenu { menu }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(isOff ? String(localized: "\(kind.moduleTitle) is turned off") : kind.title))
            .accessibilityValue(Text("\(placement.size.title), page \(placement.slot.page + 1), column \(placement.slot.column + 1), row \(placement.slot.row + 1)"))
            .accessibilityHint(Text("Arrow keys move it, Delete removes it. More in the actions."))
            .accessibilityAction(named: Text("Remove")) { actions.remove() }
            .accessibilityAction(named: Text("Move Left")) { actions.nudge(.left) }
            .accessibilityAction(named: Text("Move Right")) { actions.nudge(.right) }
            .accessibilityAction(named: Text("Move Up")) { actions.nudge(.up) }
            .accessibilityAction(named: Text("Move Down")) { actions.nudge(.down) }
            .modifier(SizeActions(kind: kind, current: placement.size, resize: actions.resize))
            .modifier(PageActions(current: placement.slot.page, move: actions.moveToPage))
            .modifier(MetricActions(isOn: kind == .statistics, current: actions.metric, choose: actions.setMetric))
    }

    @ViewBuilder private var face: some View {
        let context = HomeWidgetContext(size: frame.size, isLive: isLive, isPractice: true)
        if isOff {
            HomeGhost(kind: placement.kind, size: frame.size, open: nil)
        } else {
            HomeWidgetCard(kind: placement.kind, size: frame.size, opens: false) {
                resolver.content(placement.kind, size: placement.size, context: context)
            } open: {}
        }
    }

    private var removeBadge: some View {
        Button(action: actions.remove) {
            Image(systemName: "minus")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color(white: 0.32), in: Circle())
                .overlay { Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text("Remove from Home"))
        .accessibilityHidden(true)
    }

    /// S, M or L: opens the app's own drop-down list of the sizes this widget comes in.
    private var sizeControl: some View {
        Button { choosingSize.toggle() } label: {
            Text(placement.size.shortTitle)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 20, height: 16)
                .background(Color(white: choosingSize ? 0.36 : 0.24), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $choosingSize, arrowEdge: .bottom) {
            DropdownList(
                sections: [placement.kind.sizes.map { DropdownOption(value: $0, label: $0.title) }],
                selection: placement.size,
                width: 120
            ) { size in
                choosingSize = false
                if size != placement.size { actions.resize(size) }
            }
        }
        .help(Text("Size"))
        .accessibilityHidden(true) // VoiceOver has the size actions on the widget itself.
    }

    @ViewBuilder private var menu: some View {
        if placement.kind.sizes.count > 1 {
            Section(String(localized: "Size")) {
                ForEach(placement.kind.sizes, id: \.self) { size in
                    Toggle(size.title, isOn: Binding(get: { size == placement.size }, set: { if $0 { actions.resize(size) } }))
                }
            }
        }
        if placement.kind == .statistics {
            Section(String(localized: "Show", comment: "Home editor: which number the Statistics widget shows")) {
                ForEach(HomeStatisticsMetric.allCases) { metric in
                    Toggle(metric.title, isOn: Binding(get: { metric == actions.metric }, set: { if $0 { actions.setMetric(metric) } }))
                }
            }
        }
        Section(String(localized: "Move to")) {
            ForEach(0..<HomeLayout.pageCount, id: \.self) { index in
                Button(String(localized: "Page \(index + 1)")) { actions.moveToPage(index) }
                    .disabled(index == placement.slot.page)
            }
        }
        Divider()
        Button(String(localized: "Remove from Home")) { actions.remove() }
    }
}

/// VoiceOver actions for the Statistics widget's other numbers.
private struct MetricActions: ViewModifier {
    let isOn: Bool
    let current: HomeStatisticsMetric
    let choose: (HomeStatisticsMetric) -> Void

    func body(content: Content) -> some View {
        guard isOn else { return AnyView(content) }
        return HomeStatisticsMetric.allCases.filter { $0 != current }.reduce(AnyView(content)) { view, metric in
            AnyView(view.accessibilityAction(named: Text("Show \(metric.title)")) { choose(metric) })
        }
    }
}

/// VoiceOver actions for each size the widget offers.
private struct SizeActions: ViewModifier {
    let kind: HomeWidgetKind
    let current: HomeWidgetSize
    let resize: (HomeWidgetSize) -> Void

    func body(content: Content) -> some View {
        kind.sizes.filter { $0 != current }.reduce(AnyView(content)) { view, size in
            AnyView(view.accessibilityAction(named: Text("Make \(size.title)")) { resize(size) })
        }
    }
}

/// VoiceOver actions to move the widget to another page.
private struct PageActions: ViewModifier {
    let current: Int
    let move: (Int) -> Void

    func body(content: Content) -> some View {
        (0..<HomeLayout.pageCount).filter { $0 != current }.reduce(AnyView(content)) { view, index in
            AnyView(view.accessibilityAction(named: Text("Move to Page \(index + 1)")) { move(index) })
        }
    }
}

/// The gentle phone-style wiggle while editing: a small tilt back and forth, each widget slightly out of
/// step. It runs only while the editor shows and the window is in front, and never with Reduce Motion.
private struct Wiggle: ViewModifier {
    let isOn: Bool
    let seed: Int

    func body(content: Content) -> some View {
        if isOn {
            let duration = 0.13 + Double(abs(seed) % 4) * 0.012
            content.phaseAnimator([-1.0, 1.0]) { view, phase in
                view.rotationEffect(.degrees(phase * 0.9))
            } animation: { _ in .easeInOut(duration: duration) }
        } else {
            content
        }
    }
}

/// One widget in the gallery: a small realistic preview, its name and the sizes it comes in. Click to
/// add it in the first free spot; drag it onto Home to put it somewhere.
private struct GalleryItem: View {
    let kind: HomeWidgetKind
    let resolver: HomeWidgetResolver
    let isPlaced: Bool
    let add: () -> Void
    @State private var isHovered = false

    var body: some View {
        let previewSize = kind.defaultSize == .small ? CGSize(width: 72, height: 58) : CGSize(width: 140, height: kind.defaultSize == .large ? 110 : 58)
        Button(action: add) {
            VStack(alignment: .leading, spacing: 10) {
                HomeWidgetCard(kind: kind, size: previewSize, opens: false) {
                    resolver.content(kind, size: kind.defaultSize,
                                     context: HomeWidgetContext(size: previewSize, isLive: false, isPractice: true))
                } open: {}
                .background(.black, in: .rect(cornerRadius: HomeWidgetMetrics.cornerRadius, style: .continuous))
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
                .background(.black, in: .rect(cornerRadius: 10, style: .continuous))
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                            .font(.app(size: 13.5, weight: .semibold))
                        Text(kind.sizes.map(\.title).formatted(.list(type: .and)))
                            .font(.app(size: 11.5))
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                    Spacer(minLength: 0)
                    if isPlaced {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppPalette.secondaryText)
                            .help(Text("Already on Home"))
                    }
                }
            }
            .padding(10)
            .background(isHovered && !isPlaced ? AppPalette.hover : .clear, in: .rect(cornerRadius: 14, style: .continuous))
            .glassPanel(cornerRadius: 14)
            .opacity(isPlaced ? 0.55 : 1)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isPlaced)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(kind.title))
        .accessibilityValue(Text(isPlaced ? String(localized: "On Home") : kind.sizes.map(\.title).formatted(.list(type: .or))))
        .accessibilityHint(Text(isPlaced ? "" : String(localized: "Adds it to the first free spot on Home.")))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !isPlaced { add() } }
    }
}

extension HomeWidgetSize {
    var title: String {
        switch self {
        case .small: String(localized: "Small", comment: "Home widget size")
        case .medium: String(localized: "Medium", comment: "Home widget size")
        case .large: String(localized: "Large", comment: "Home widget size")
        }
    }

    /// One letter for the size control on each widget.
    var shortTitle: String {
        switch self {
        case .small: String(localized: "S", comment: "Short for Small, a Home widget size")
        case .medium: String(localized: "M", comment: "Short for Medium, a Home widget size")
        case .large: String(localized: "L", comment: "Short for Large, a Home widget size")
        }
    }
}
