import SwiftUI

/// All saved widget identities stay mounted during a drag, including across page turns.
struct NotchHomeEditingGrid: View {
    let model: NotchViewModel
    let area: CGSize
    @State private var history = HomeHistory()
    @State private var dragged: HomeWidgetKind?
    @State private var pointer = CGPoint.zero
    @State private var anchor = CGPoint.zero
    @State private var landing: HomeSlot?
    @State private var note: String?
    @State private var noteTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var page: Int { model.homePages[safe: model.homePage] ?? 0 }
    private var resolver: HomeWidgetResolver {
        HomeWidgetResolver(modules: model.modules, arrangement: model.arrangement, extras: model.homeExtras)
    }
    private var shown: HomeLayout {
        guard let dragged, let landing else { return model.homeLayout }
        return model.homeLayout.previewMoving(dragged, to: landing) ?? model.homeLayout
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.showsHomePicker {
                HomeWidgetPicker(kinds: HomeWidgetKind.allCases.filter {
                    !model.home.layout.contains($0) && !resolver.isTurnedOff($0)
                }, resolver: resolver, area: area, add: add, close: { model.showsHomePicker = false })
            } else {
                canvas
            }
            if let note {
                Text(note).font(.system(size: 10.5, weight: .medium))
                    .padding(6).background(.black, in: Capsule())
                    .frame(width: area.width, height: area.height, alignment: .bottom)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onDisappear { noteTask?.cancel(); dragged = nil }
        .onChange(of: area) { _, _ in dragged = nil; landing = nil }
    }

    private var canvas: some View {
        let cell = HomeWidgetMetrics.cellSize(in: area)
        return ZStack(alignment: .topLeading) {
            if model.homeLayout.placements.isEmpty {
                HomeWidgetEmptyLine(String(localized: "Click Add to put widgets on Home."))
                    .frame(width: area.width, height: area.height)
            }
            ForEach(model.homeLayout.placements) { original in
                let placement = shown.placement(of: original.kind) ?? original
                let frame = HomeWidgetMetrics.frame(column: placement.slot.column, row: placement.slot.row,
                                                    size: placement.size, cell: cell)
                let lifted = dragged == original.kind
                tile(original, frame: frame)
                    .modifier(HomeWiggle(isOn: model.isEditingHome && model.state == .expanded && model.showsHome
                                         && dragged == nil && model.isOnScreen && model.snapshotClock == nil,
                                         seed: WiggleMotion.seed(for: original.kind)))
                    .frame(width: frame.width, height: frame.height)
                    .scaleEffect(lifted && !reduceMotion ? 1.04 : 1)
                    .offset(x: lifted ? pointer.x - anchor.x : frame.minX,
                            y: lifted ? pointer.y - anchor.y : frame.minY)
                    .opacity(lifted || placement.slot.page == page ? 1 : 0)
                    .allowsHitTesting(lifted || placement.slot.page == page)
                    .zIndex(lifted ? 2 : 0)
                    .gesture(dragGesture(original, frame: frame))
                    .animation(lifted || reduceMotion ? nil : .snappy(duration: 0.25), value: placement)
                    .transaction { if lifted { $0.animation = nil } }
            }
            if let dragged, let placement = shown.placement(of: dragged), placement.slot.page == page {
                let frame = HomeWidgetMetrics.frame(column: placement.slot.column, row: placement.slot.row,
                                                    size: placement.size, cell: cell)
                RoundedRectangle(cornerRadius: HomeWidgetMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .frame(width: area.width, height: area.height, alignment: .topLeading)
        .coordinateSpace(name: "notchHomeEdit")
    }

    private func tile(_ placement: HomePlacement, frame: CGRect) -> some View {
        face(placement, size: frame.size)
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) {
                Button { edit { .success($0.removing(placement.kind)) } } label: {
                    Image(systemName: "minus").font(.system(size: 9, weight: .heavy))
                        .frame(width: 18, height: 18)
                        .background(Color(white: 0.32), in: Circle())
                        .overlay { Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1) }
                }
                .buttonStyle(.plain).offset(x: -6, y: -6)
                .accessibilityLabel(Text("Remove \(placement.kind.title)"))
                .help(Text("Remove from Home"))
            }
            .overlay(alignment: .bottomTrailing) {
                if placement.kind.sizes.count > 1 {
                    Button {
                        let sizes = placement.kind.sizes
                        let index = sizes.firstIndex(of: placement.size) ?? 0
                        edit { $0.resizing(placement.kind, to: sizes[(index + 1) % sizes.count]) }
                    } label: {
                        Text(shortTitle(placement.size)).font(.system(size: 9.5, weight: .bold))
                            .frame(width: 20, height: 16).background(Color(white: 0.24), in: Capsule())
                    }
                    .buttonStyle(.plain).offset(x: 6, y: 6)
                    .accessibilityLabel(Text("Change size of \(placement.kind.title)"))
                    .help(Text("Size"))
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(placement.kind.title))
            .accessibilityActions {
                Button(String(localized: "Remove")) { edit { .success($0.removing(placement.kind)) } }
                Button(String(localized: "Move Left")) { nudge(placement.kind, .left) }
                Button(String(localized: "Move Right")) { nudge(placement.kind, .right) }
                Button(String(localized: "Move Up")) { nudge(placement.kind, .up) }
                Button(String(localized: "Move Down")) { nudge(placement.kind, .down) }
                ForEach(placement.kind.sizes, id: \.self) { size in
                    Button(String(localized: "Make \(sizeTitle(size))")) { edit { $0.resizing(placement.kind, to: size) } }
                }
                ForEach(0..<HomeLayout.pageCount, id: \.self) { page in
                    Button(String(localized: "Move to Page \(page + 1)")) {
                        edit { $0.movingToPage(placement.kind, page: page) }
                        turnToWidget(placement.kind)
                    }
                }
            }
    }

    @ViewBuilder private func face(_ placement: HomePlacement, size: CGSize) -> some View {
        if resolver.isTurnedOff(placement.kind) {
            HomeGhost(kind: placement.kind, size: size, open: nil)
        } else {
            HomeWidgetCard(kind: placement.kind, size: size, opens: false) {
                resolver.content(placement.kind, size: placement.size,
                                 context: HomeWidgetContext(size: size, isLive: false,
                                                            isSnapshot: model.snapshotClock != nil, fixedNow: model.snapshotClock))
            } open: {}
        }
    }

    private func dragGesture(_ placement: HomePlacement, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("notchHomeEdit"))
            .onChanged { value in
                if dragged == nil {
                    dragged = placement.kind
                    anchor = CGPoint(x: value.startLocation.x - frame.minX, y: value.startLocation.y - frame.minY)
                }
                pointer = value.location
                // The dots occupy the side gutter, vertically centred like HomePageDots.
                if pointer.x > area.width, pointer.x < area.width + HomeWidgetMetrics.sidePadding {
                    let count = model.homePages.count
                    let top = (area.height - CGFloat(count * 16 - 5)) / 2
                    let index = Int((pointer.y - top) / 16)
                    if index >= 0, index < count { model.showHomePage(index) }
                }
                let cell = HomeWidgetMetrics.cellSize(in: area)
                landing = HomeSlot(page: page,
                    column: min(max(0, Int((pointer.x - anchor.x + cell.width / 2) / (cell.width + HomeWidgetMetrics.gap))), HomeLayout.columns - placement.size.columns),
                    row: min(max(0, Int((pointer.y - anchor.y + cell.height / 2) / (cell.height + HomeWidgetMetrics.gap))), HomeLayout.rows - placement.size.rows))
            }
            .onEnded { _ in
                if let landing { edit { $0.moving(placement.kind, to: landing) } }
                dragged = nil; landing = nil
                turnToWidget(placement.kind)
            }
    }

    private func edit(_ change: (HomeLayout) -> Result<HomeLayout, HomeEditRefusal>) {
        if let refusal = model.home.edit(&history, change) {
            noteTask?.cancel()
            withAnimation(.easeInOut(duration: 0.15)) { note = refusal.message }
            noteTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.15)) { note = nil }
            }
        }
    }
    private func add(_ kind: HomeWidgetKind) {
        edit { $0.adding(kind) }
        model.showsHomePicker = false
        turnToWidget(kind)
    }
    private func turnToWidget(_ kind: HomeWidgetKind) {
        if let page = model.home.layout.placement(of: kind)?.slot.page,
           let index = model.homePages.firstIndex(of: page) { model.showHomePage(index) }
    }
    private func nudge(_ kind: HomeWidgetKind, _ direction: HomeNudge) {
        edit { $0.nudging(kind, by: direction) }; turnToWidget(kind)
    }
    private func shortTitle(_ size: HomeWidgetSize) -> String {
        switch size { case .small: String(localized: "S"); case .medium: String(localized: "M"); case .large: String(localized: "L") }
    }
    private func sizeTitle(_ size: HomeWidgetSize) -> String {
        switch size { case .small: String(localized: "Small"); case .medium: String(localized: "Medium"); case .large: String(localized: "Large") }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
