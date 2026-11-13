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
    /// Where the pointer is while dragging. Kept apart from `drag` so a move only redraws the floating
    /// widget, not the whole page.
    @State private var pointer = DragPointer()
    /// Where a cancelled drag started: the rest of that same gesture is ignored, so it can't come back or land.
    @State private var cancelledDragStart: CGPoint?
    @State private var gridFrame: CGRect = .zero
    @State private var tabFrames: [PageTab: CGRect] = [:]
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
        // Built once per update and handed down, not rebuilt by each part of the page.
        let resolver = HomeWidgetResolver(modules: practice.modules, arrangement: context.arrangement,
                                          extras: HomeExtras.practice(home: home))
        // The tabs follow the saved layout, so they hold still while a widget is dragged around.
        let pages = HomePageList(layout: home.layout, editing: page)
        return AppPage(
            title: String(localized: "Home"),
            subtitle: String(localized: "Arrange the widgets Home shows in the open notch. Drag them around, or add more from below. Changes show in the notch right away.")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                toolbar(pages: pages)
                canvas(resolver: resolver, pages: pages)
                noteLine
            }
            gallery(resolver: resolver)
        }
        // A click on anything that isn't a widget or a control ends editing the selected widget.
        .contentShape(Rectangle())
        .onTapGesture { focusedWidget = nil }
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .topLeading) { floatingWidget(resolver: resolver) }
        .onAppear {
            // Coming back to this page never finds a widget still outlined.
            focusedWidget = nil
            if home.layout.isPageEmpty(page), let first = home.layout.nonEmptyPages.first { page = first }
            practice.update(Self.practiceKinds(for: context))
            home.hasSeenIntro = true // the notch's "Home is new" hint has done its job
        }
        .onDisappear {
            cancelDrag()
            focusedWidget = nil
            practice.close()
            noteTask?.cancel()
        }
        // Escape, or the window going to the background, drops a drag without changing anything.
        .onExitCommand {
            if drag != nil { cancelDrag() } else { focusedWidget = nil }
        }
        .onChange(of: appearsActive) { _, active in if !active { cancelDrag() } }
        .onChange(of: Self.practiceKinds(for: context)) { _, kinds in practice.update(kinds) }
        // An edit that empties the page being edited moves on to the nearest page with widgets, so an
        // empty page doesn't linger. A page made with "+" stays: it was empty before the edit too.
        .onChange(of: home.layout) { old, new in
            guard !new.isEmpty, new.isPageEmpty(page), !old.isPageEmpty(page),
                  let nearest = HomePageList.nearestNonEmptyPage(to: page, in: new) else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { page = nearest }
        }
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

    private func toolbar(pages: HomePageList) -> some View {
        HStack(spacing: 10) {
            pageTabs(pages)
            Spacer(minLength: 8)
            Button { focusedWidget = nil; undo() } label: {
                Label(String(localized: "Undo"), systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!history.canUndo)
            .help(Text("Undo (⌘Z)"))
            Button { focusedWidget = nil; redo() } label: {
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

    /// One tab for each page that holds widgets (named by its place in the row, not its saved number), the
    /// page being edited if it's blank, and a "+" for a new page while there's room.
    private func pageTabs(_ pages: HomePageList) -> some View {
        HStack(spacing: 2) {
            ForEach(pages.pages, id: \.self) { index in
                let isSelected = index == page
                let isEmpty = home.layout.isPageEmpty(index)
                Button { focusedWidget = nil; page = index } label: {
                    Text("Page \(pages.number(of: index) ?? 1)")
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
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { tabFrames[.page(index)] = $0 }
                .onDisappear { tabFrames[.page(index)] = nil }
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityValue(Text(isEmpty ? String(localized: "Empty") : ""))
                .transition(.opacity)
            }
            if pages.canAddPage {
                Button { focusedWidget = nil; turn(to: .new) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppPalette.primaryText.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { tabFrames[.new] = $0 }
                .onDisappear { tabFrames[.new] = nil }
                .help(Text("New Page"))
                .accessibilityLabel(Text("New Page"))
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: pages.pages)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: pages.canAddPage)
        .padding(2)
        .background(AppPalette.rail.opacity(0.5), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Pages"))
    }

    /// Shows a page: a tab's, or the first blank one ("+"), which becomes a tab while it's being edited.
    private func turn(to tab: PageTab) {
        switch tab {
        case .page(let index):
            if index != page { page = index }
        case .new:
            let pages = HomePageList(layout: home.layout, editing: page)
            if pages.canAddPage, let new = pages.newPage { page = new }
        }
    }

    // MARK: Canvas

    /// A black panel like the open notch, with the grid of the page being edited.
    private func canvas(resolver: HomeWidgetResolver, pages: HomePageList) -> some View {
        GeometryReader { proxy in
            // As wide as the open notch gets (never wider), in the middle of the page.
            let width = min(proxy.size.width, NotchLayout.maxExpandedBodySize.width)
            let metrics = HomeEditorMetrics(width: width)
            ZStack(alignment: .topLeading) {
                grid(metrics: metrics, resolver: resolver, pages: pages)
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

    private func grid(metrics: HomeEditorMetrics, resolver: HomeWidgetResolver, pages: HomePageList) -> some View {
        let cell = HomeWidgetMetrics.cellSize(in: metrics.grid)
        let layout = shownLayout
        // One host per widget for the whole drag. The dragged widget's host also stays while it's away
        // from this page (hidden): a drag gesture is cancelled the moment the view that owns it goes.
        var hosts = layout.placements(onPage: page)
        if let drag, !drag.fromGallery, !hosts.contains(where: { $0.kind == drag.kind }),
           let original = home.layout.placement(of: drag.kind) {
            hosts.append(original)
        }
        /// What a host shows: the widget, the dragged widget's dashed landing spot, or nothing.
        func face(of placement: HomePlacement) -> HostFace {
            guard placement.kind == drag?.kind else { return .widget }
            return drag?.landing != nil && placement.slot.page == page ? .landing : .hidden
        }
        // Only the free cells: the widgets' cards are see-through, so a cell under one would show. A hidden
        // widget leaves its cells free, so there's still something to aim at.
        let taken = hosts.filter { face(of: $0) != .hidden }.reduce(into: Set<HomeCell>()) { $0.formUnion($1.cells) }
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
            ForEach(hosts) { placement in
                let frame = HomeWidgetMetrics.frame(column: placement.slot.column, row: placement.slot.row,
                                                    size: placement.size, cell: cell)
                let face = face(of: placement)
                // The host is the same view whatever it shows, and owns the drag gesture. A widget dragged in
                // from the gallery has none of its own: the gallery item holds that gesture.
                ZStack {
                    switch face {
                    case .widget:
                        EditableWidget(
                            placement: placement, frame: frame, resolver: resolver, pages: pages,
                            isOff: placement.kind.moduleID.map { !context.isEnabled($0) } ?? false,
                            isDimmed: drag != nil,
                            isLive: appearsActive && drag == nil,
                            wiggles: !reduceMotion && appearsActive && drag == nil,
                            actions: actions(for: placement, pages: pages),
                            focus: $focusedWidget
                        )
                        .transition(.opacity)
                    case .landing:
                        // Where the dragged widget will land.
                        RoundedRectangle(cornerRadius: HomeWidgetMetrics.cornerRadius, style: .continuous)
                            .fill(.white.opacity(0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: HomeWidgetMetrics.cornerRadius, style: .continuous)
                                    .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            }
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    case .hidden:
                        Color.clear.accessibilityHidden(true)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .gesture(dragGesture(kind: placement.kind, size: placement.size, origin: frame, fromGallery: false),
                         including: drag?.fromGallery == true && face != .widget ? .none : .all)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25), value: layout)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: page)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Page \(pages.number(of: page) ?? 1) of Home"))
    }

    /// The widget under the pointer while dragging: lifted a little, slightly bigger, with a shadow.
    @ViewBuilder private func floatingWidget(resolver: HomeWidgetResolver) -> some View {
        if let drag {
            let size = HomeWidgetMetrics.frame(column: 0, row: 0, size: drag.size,
                                               cell: HomeWidgetMetrics.cellSize(in: HomeEditorMetrics(width: gridFrame.width + 2 * HomeWidgetMetrics.sidePadding).grid)).size
            // The widget is built here, when the drag changes; following the pointer only moves it.
            DragFollower(pointer: pointer, grab: drag.grab) {
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
            }
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

    private func gallery(resolver: HomeWidgetResolver) -> some View {
        let kinds = HomeWidgetKind.allCases.filter { kind in kind.moduleID.map(context.isEnabled) ?? true }
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
                    pointer.location = value.location
                    drag = HomeEditorDrag(kind: kind, size: size, fromGallery: fromGallery, start: value.startLocation,
                                          grab: grab)
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

    /// Follows the pointer at once; the page is redrawn only when the pointer moves to another landing spot.
    private func dragMoved(to location: CGPoint) {
        guard var current = drag else { return }
        pointer.location = location
        // Hovering a page tab turns to that page, and "+" to a new one.
        if let tab = tabFrames.first(where: { $0.value.contains(location) })?.key { turn(to: tab) }
        let slot = HomeDragLanding.slot(pointer: location, grab: current.grab, grid: gridFrame, page: page)
        guard slot != current.landing else { return }
        current.landing = slot
        current.preview = slot.flatMap { slot in
            current.fromGallery
                ? home.layout.previewInserting(current.kind, size: current.size, at: slot)
                : home.layout.previewMoving(current.kind, to: slot)
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

    private func actions(for placement: HomePlacement, pages: HomePageList) -> HomeWidgetActions {
        HomeWidgetActions(
            remove: { change { .success($0.removing(placement.kind)) } },
            resize: { size in change { $0.resizing(placement.kind, to: size) } },
            nudge: { direction in change { $0.nudging(placement.kind, by: direction) } },
            moveToPage: { target in
                // Follow the widget, unless the move was refused.
                if change({ $0.movingToPage(placement.kind, page: target) }) { page = target }
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
        focusedWidget = nil
        change { $0.adding(kind, preferring: page) }
        if let placed = home.layout.placement(of: kind) { page = placed.slot.page }
    }

    /// Applies an edit; returns whether it was accepted (a refusal says why, in the note).
    @discardableResult
    private func change(_ edit: (HomeLayout) -> Result<HomeLayout, HomeEditRefusal>) -> Bool {
        var accepted = true
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)) {
            if let refusal = home.edit(&history, edit) {
                show(refusal.message)
                accepted = false
            }
        }
        return accepted
    }

    private func replace(with layout: HomeLayout) {
        focusedWidget = nil
        change { _ in .success(layout) }
        page = home.layout.nonEmptyPages.first ?? 0
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
    /// The cell its top-left corner would land on, or `nil` while it's away from the grid.
    var landing: HomeSlot?
    /// Home with the widget landed there and its neighbours moved aside; `nil` when it can't land.
    var preview: HomeLayout?
}

/// Where the pointer is during a drag. Only the floating widget reads it, so a move redraws just that.
@MainActor @Observable private final class DragPointer {
    var location: CGPoint = .zero
}

/// Holds a view where the pointer holds the dragged widget. The view is built by the caller, so following the
/// pointer is only an offset, and it's never animated: the widget stays glued to the pointer.
private struct DragFollower<Content: View>: View {
    let pointer: DragPointer
    let grab: CGPoint
    let content: Content

    init(pointer: DragPointer, grab: CGPoint, @ViewBuilder content: () -> Content) {
        self.pointer = pointer
        self.grab = grab
        self.content = content()
    }

    var body: some View {
        let location = pointer.location
        content
            .offset(x: location.x - grab.x, y: location.y - grab.y)
            .animation(nil, value: location)
    }
}

/// A tab in the page row: a page, or "+" for a new one.
private enum PageTab: Hashable {
    case page(Int)
    case new
}

/// What a widget's host shows on the grid: the widget, the dragged widget's landing spot, or nothing
/// (the dragged widget while it's away from this page).
private enum HostFace {
    case widget, landing, hidden
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
    /// The page tabs, which name the pages in the "Move to" lists.
    let pages: HomePageList
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
            .modifier(HomeWiggle(isOn: wiggles, seed: WiggleMotion.seed(for: kind)))
            .contentShape(.rect(cornerRadius: HomeWidgetMetrics.cornerRadius))
            .onHover { hovering in withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering } }
            // Leaving the page (or the widget going) closes the size list and forgets the pointer.
            .onDisappear { choosingSize = false; isHovered = false }
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
            .accessibilityValue(Text("\(placement.size.title), page \(pages.number(of: placement.slot.page) ?? placement.slot.page + 1), column \(placement.slot.column + 1), row \(placement.slot.row + 1)"))
            .accessibilityHint(Text("Arrow keys move it, Delete removes it. More in the actions."))
            .accessibilityAction(named: Text("Remove")) { actions.remove() }
            .accessibilityAction(named: Text("Move Left")) { actions.nudge(.left) }
            .accessibilityAction(named: Text("Move Right")) { actions.nudge(.right) }
            .accessibilityAction(named: Text("Move Up")) { actions.nudge(.up) }
            .accessibilityAction(named: Text("Move Down")) { actions.nudge(.down) }
            .modifier(SizeActions(kind: kind, current: placement.size, resize: actions.resize))
            .modifier(PageActions(current: placement.slot.page, pages: pages, move: actions.moveToPage))
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
            ForEach(pages.others(than: placement.slot.page), id: \.self) { index in
                Button(String(localized: "Page \(pages.number(of: index) ?? 1)")) { actions.moveToPage(index) }
            }
            if let new = pages.newPage {
                Button(String(localized: "New Page")) { actions.moveToPage(new) }
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

/// VoiceOver actions to move the widget to another page, or to a new one.
private struct PageActions: ViewModifier {
    let current: Int
    let pages: HomePageList
    let move: (Int) -> Void

    func body(content: Content) -> some View {
        let others = pages.others(than: current).reduce(AnyView(content)) { view, index in
            AnyView(view.accessibilityAction(named: Text("Move to Page \(pages.number(of: index) ?? 1)")) { move(index) })
        }
        guard let new = pages.newPage else { return others }
        return AnyView(others.accessibilityAction(named: Text("Move to New Page")) { move(new) })
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
