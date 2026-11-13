import SwiftUI

/// Home's symbol, in the bar and the app window's sidebar.
public enum HomeSymbol {
    public static let name = "house"
}

/// Battery and Statistics widgets come from the app, which has the battery reading and the statistics.
public typealias HomeExtraWidgets = @MainActor (HomeWidgetKind, HomeWidgetSize, HomeWidgetContext) -> AnyView?

/// Finds the view for each placed widget: the module's own, a switched-off module's ghost, or one of the
/// widgets that belong to no module. The notch's Home and the editor draw widgets through it, so both
/// look the same.
@MainActor
public struct HomeWidgetResolver {
    /// The modules that are switched on.
    public var modules: [any NotchModule]
    public var arrangement: ModuleArrangement
    /// The module the open notch would show, ticked in All Modules.
    public var currentModuleID: String?
    /// Shows a module (All Modules' rows); `nil` draws them without acting.
    public var select: ((String) -> Void)?
    public var extras: HomeExtraWidgets?

    public init(modules: [any NotchModule], arrangement: ModuleArrangement, currentModuleID: String? = nil,
                select: ((String) -> Void)? = nil, extras: HomeExtraWidgets? = nil) {
        self.modules = modules
        self.arrangement = arrangement
        self.currentModuleID = currentModuleID
        self.select = select
        self.extras = extras
    }

    /// The widget's module is switched off: it shows as a ghost and keeps its spot.
    public func isTurnedOff(_ kind: HomeWidgetKind) -> Bool {
        guard let moduleID = kind.moduleID else { return false }
        return !modules.contains { $0.moduleID == moduleID }
    }

    /// The widget's content (no card), or a plain tile if nobody draws it.
    public func content(_ kind: HomeWidgetKind, size: HomeWidgetSize, context: HomeWidgetContext) -> AnyView {
        let view: AnyView? = switch kind {
        case .clock: AnyView(HomeClockWidget(size: size, context: context))
        case .allModules: AnyView(HomeAllModulesWidget(resolver: self, context: context))
        case .battery, .statistics: extras?(kind, size, context)
        default: kind.moduleID.flatMap { id in modules.first { $0.moduleID == id } }?.homeWidget(kind, size: size, context: context)
        }
        return view ?? AnyView(HomeWidgetTile(kind: kind, line: nil))
    }
}

/// Home in the open notch (ADR-0042): the band with the gear, one page of widgets, and page dots when
/// more than one page holds something. Scrolling up or down turns the page (`NotchViewModel.handleScroll`).
struct NotchHomeView: View {
    let model: NotchViewModel
    let layout: NotchLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = layout.bodySize(for: .expanded)
        let notch = layout.geometry.notchRect.size
        let area = HomeWidgetMetrics.gridArea(in: layout)
        let pages = model.homePages
        let index = min(model.homePage, max(0, pages.count - 1))
        let showsIntro = !model.isEditingHome && !model.home.hasSeenIntro && !model.homeLayout.isEmpty && model.openAppPage != nil
        VStack(spacing: 0) {
            // The band beside the hardware notch: the bar sits on the left (drawn by NotchView), the gear right.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Color.clear.frame(width: notch.width)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if model.isEditingHome {
                        NotchPill(title: model.showsHomePicker ? String(localized: "Back") : String(localized: "Add"),
                                  symbol: model.showsHomePicker ? "chevron.left" : "plus") { model.showsHomePicker.toggle() }
                        NotchPill(title: String(localized: "Done"), symbol: "checkmark", prominent: true) { model.endHomeEditing() }
                    }
                    // Once, until it's used or dismissed: a pointer to the editor (the empty note has its own).
                    if showsIntro, let open = model.openAppPage {
                        HomeIntroHint {
                            model.home.hasSeenIntro = true
                            open(.homeEditor)
                        } dismiss: {
                            model.home.hasSeenIntro = true
                        }
                        .transition(.opacity)
                    }
                    if !model.isEditingHome, let open = model.openAppPage {
                        HomeGearButton(compact: showsIntro, symbol: "slider.horizontal.3", title: String(localized: "Edit")) {
                            model.home.hasSeenIntro = true
                            open(.homeEditor)
                        }
                    }
                    if !model.isEditingHome, let openSettings = model.openSettings {
                        HomeGearButton(compact: showsIntro, action: openSettings)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: model.home.hasSeenIntro)
                .frame(maxWidth: (size.width - notch.width) / 2 - HomeWidgetMetrics.sidePadding)
            }
            .frame(height: notch.height)
            .padding(.horizontal, HomeWidgetMetrics.sidePadding)

            ZStack {
                if model.isEditingHome {
                    NotchHomeEditingGrid(model: model, area: area)
                } else if pages.indices.contains(index) {
                    if reduceMotion {
                        HomePageGrid(model: model, page: pages[index], area: area)
                            .id(pages[index])
                            .transition(.opacity)
                    } else {
                        pageStack(pages: pages, area: area)
                    }
                } else {
                    HomeEmptyNote(customize: model.openAppPage.map { open in { open(.homeEditor) } })
                        .transition(.opacity)
                }
            }
            .frame(width: area.width, height: area.height, alignment: .topLeading)
            .contentShape(Rectangle())
            // Alongside, not before, the widgets' own clicks and buttons, so a quick click still works. Once
            // the hold starts editing, the editing grid replaces the widgets, so the release presses nothing.
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in model.beginHomeEditing() },
                                 including: model.isEditingHome ? .none : .all)
            .contextMenu {
                if let open = model.openAppPage {
                    Button(String(localized: "Edit Home…")) {
                        model.home.hasSeenIntro = true
                        open(.homeEditor)
                    }
                }
            }
            .padding(.top, HomeWidgetMetrics.topPadding)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .overlay(alignment: .trailing) {
            if pages.count > 1 {
                HomePageDots(count: pages.count, current: index, newPage: model.isEditingHome ? pages.firstIndex(where: { model.homeLayout.isPageEmpty($0) }) : nil) { model.showHomePage($0) }
                    .padding(.top, notch.height)
                    .frame(width: HomeWidgetMetrics.sidePadding)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pages.count > 1)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Home"))
        .accessibilityAction(named: Text("Edit Home")) { model.beginHomeEditing() }
        .accessibilityAction(named: Text("Next page")) { model.showHomePage(index + 1) }
        .accessibilityAction(named: Text("Previous page")) { model.showHomePage(index - 1) }
    }

    private func pageStack(pages: [Int], area: CGSize) -> some View {
        let position = model.homeScrollPosition ?? CGFloat(model.homePage)
        return ZStack(alignment: .topLeading) {
            ForEach(model.homeRenderedPages, id: \.self) { index in
                HomePageGrid(model: model, page: pages[index], area: area)
                    .offset(y: (CGFloat(index) - position) * area.height)
                    // A page first mounted by a wheel/key/dot turn starts beside the old page.
                    .transition(.offset(y: CGFloat(index - (model.homeAnimationOrigin ?? index)) * area.height))
                    .allowsHitTesting(index == model.homePage && model.homeScrollPosition == nil)
                    .accessibilityHidden(index != model.homePage)
            }
        }
        .frame(width: area.width, height: area.height, alignment: .topLeading)
        .clipped()
    }
}

/// One page of Home: each widget at its place in the 6 × 2 grid.
private struct HomePageGrid: View {
    let model: NotchViewModel
    let page: Int
    let area: CGSize

    var body: some View {
        let cell = HomeWidgetMetrics.cellSize(in: area)
        let resolver = HomeWidgetResolver(
            modules: model.modules, arrangement: model.arrangement,
            currentModuleID: model.selectedModule?.moduleID,
            select: { model.select($0) }, extras: model.homeExtras
        )
        let isLive = model.homeIsLive(onPage: page)
        ZStack(alignment: .topLeading) {
            ForEach(model.homeLayout.placements(onPage: page)) { placement in
                let frame = HomeWidgetMetrics.frame(column: placement.slot.column, row: placement.slot.row,
                                                    size: placement.size, cell: cell)
                let context = HomeWidgetContext(size: frame.size, isLive: isLive,
                                                isSnapshot: model.snapshotClock != nil, fixedNow: model.snapshotClock,
                                                visit: model.homeVisit)
                Group {
                    if resolver.isTurnedOff(placement.kind) {
                        HomeGhost(kind: placement.kind, size: frame.size,
                                  open: model.openAppPage.map { open in { open(.modules) } })
                    } else {
                        HomeWidgetCard(kind: placement.kind, size: frame.size,
                                       opens: placement.kind.opensFromHome) {
                            resolver.content(placement.kind, size: placement.size, context: context)
                        } open: {
                            model.openFromHome(placement.kind)
                        }
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: area.width, height: area.height, alignment: .topLeading)
    }
}

/// The card every widget sits on: a soft rounded square that brightens under the pointer when a click
/// opens something. A click anywhere away from the widget's own buttons opens it.
public struct HomeWidgetCard<Content: View>: View {
    let kind: HomeWidgetKind
    let size: CGSize
    let opens: Bool
    let content: Content
    let open: () -> Void
    @State private var isHovered = false

    public init(kind: HomeWidgetKind, size: CGSize, opens: Bool, @ViewBuilder content: () -> Content,
                open: @escaping () -> Void) {
        self.kind = kind
        self.size = size
        self.opens = opens
        self.content = content()
        self.open = open
    }

    public var body: some View {
        content
            .padding(HomeWidgetMetrics.padding)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(.white.opacity(opens && isHovered ? 0.1 : 0.06),
                        in: .rect(cornerRadius: HomeWidgetMetrics.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HomeWidgetMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.06))
            }
            .contentShape(.rect(cornerRadius: HomeWidgetMetrics.cornerRadius))
            // A widget with nothing to open still takes the click, so it doesn't shrink the panel.
            .onTapGesture { if opens { open() } }
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(kind.title))
            .accessibilityActions {
                // Only for cards that open something (not Clock, Battery or All Modules).
                if opens { Button(String(localized: "Open", comment: "VoiceOver action on a Home widget")) { open() } }
            }
    }
}

/// Where a switched-off module's widget was: a faint dashed outline that keeps its spot. A click opens
/// the Modules page to turn it back on.
public struct HomeGhost: View {
    let kind: HomeWidgetKind
    let size: CGSize
    let open: (() -> Void)?
    @State private var isHovered = false

    public init(kind: HomeWidgetKind, size: CGSize, open: (() -> Void)?) {
        self.kind = kind
        self.size = size
        self.open = open
    }

    public var body: some View {
        let label = String(localized: "\(kind.moduleTitle) is turned off", comment: "A switched-off module's place on Home")
        VStack(spacing: 4) {
            Image(systemName: kind.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(isHovered ? 0.6 : 0.4))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(8)
        .frame(width: size.width, height: size.height)
        .overlay {
            RoundedRectangle(cornerRadius: HomeWidgetMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(isHovered ? 0.3 : 0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .contentShape(.rect(cornerRadius: HomeWidgetMetrics.cornerRadius))
        .onTapGesture { open?() }
        .onHover { isHovered = $0 && open != nil }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityHint(open == nil ? Text("") : Text("Opens Modules, where you can turn it back on."))
        .accessibilityAddTraits(open == nil ? [] : .isButton)
        .accessibilityAction { open?() }
    }
}

/// A widget's simplest face: its symbol and name, plus one quiet line (the successor of the Module
/// Menu's favorite tile). Small widgets build on it.
public struct HomeWidgetTile: View {
    let symbol: String
    let title: String
    let line: String?

    public init(kind: HomeWidgetKind, line: String?) {
        self.init(symbol: kind.symbol, title: kind.title, line: line)
    }

    public init(symbol: String, title: String, line: String?) {
        self.symbol = symbol
        self.title = title
        self.line = line
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(height: 14, alignment: .leading)
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if let line {
                Text(line)
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: line)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// The title row of a Medium or Large widget: the symbol in a fixed 14 pt column and the name, so every
/// widget's name starts at the same place, with room on the right (the Shelf's count).
public struct HomeWidgetHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    let trailing: Trailing

    public init(symbol: String, title: String, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            trailing
        }
        .foregroundStyle(.white.opacity(0.85))
        .frame(height: 14)
    }
}

extension HomeWidgetHeader where Trailing == EmptyView {
    public init(symbol: String, title: String) {
        self.init(symbol: symbol, title: title) { EmptyView() }
    }
}

/// A widget's "nothing here" line, centred in the room under its title row (as the Shelf's drop zone is).
public struct HomeWidgetEmptyLine: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A Small widget with a reading: a symbol and a short caption on top, the value below in large type.
/// Two rows, so it fits the Small cell's height on every notch size.
public struct HomeSmallFace<Icon: View, Value: View>: View {
    let caption: String?
    let icon: Icon
    let value: Value

    public init(caption: String?, @ViewBuilder icon: () -> Icon, @ViewBuilder value: () -> Value) {
        self.caption = caption
        self.icon = icon()
        self.value = value()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                icon
                    .frame(height: 14, alignment: .leading)
                    .accessibilityHidden(true)
                if let caption {
                    // Every caption the same size: a long one is cut off, never shrunk.
                    Text(caption)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: caption)
                }
            }
            Spacer(minLength: 0)
            value
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Every page is empty: one line and a way to the editor.
private struct HomeEmptyNote: View {
    let customize: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Text("Customize the home page")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            if let customize {
                NotchPill(title: String(localized: "Customize"), symbol: "slider.horizontal.3", prominent: true, action: customize)
                    .accessibilityHint(Text("Opens the Home editor in the PancakeNotch window."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small dots down the right edge, one per page that holds something; the current one is white.
private struct HomePageDots: View {
    let count: Int
    let current: Int
    var newPage: Int? = nil
    let select: (Int) -> Void

    var body: some View {
        VStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Button { select(index) } label: {
                    Group {
                        if newPage == index {
                            Image(systemName: "plus").font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white.opacity(index == current ? 0.9 : 0.45))
                        } else {
                            Circle().fill(.white.opacity(index == current ? 0.9 : 0.3)).frame(width: 5, height: 5)
                        }
                    }
                        .frame(width: 14, height: 11)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(newPage == index ? Text("New page") : Text("Page \(index + 1) of \(count)"))
                .accessibilityAddTraits(index == current ? [.isSelected] : [])
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
        .frame(maxHeight: .infinity)
    }
}

/// The gear at the top right of Home: opens the app window.
/// "Home is new · Customize", shown until it's clicked, dismissed, or the editor has been opened.
struct HomeIntroHint: View {
    let customize: () -> Void
    let dismiss: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: customize) {
                ViewThatFits(in: .horizontal) {
                    Text("Home is new. Customize it").fixedSize()
                    Text("Customize").fixedSize()
                }
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(isHovered ? 1 : 0.85))
                    .padding(.leading, 10)
                    .padding(.trailing, 4)
                    .frame(height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityHint(Text("Opens the Home editor in the PancakeNotch window."))
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.trailing, 2)
        .background(.white.opacity(0.1), in: Capsule())
    }
}

struct HomeGearButton: View {
    /// Just the gear, to leave room for the intro hint.
    var compact = false
    var symbol = "gearshape"
    var title = String(localized: "Settings")
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                if !compact {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                }
            }
            .foregroundStyle(.white.opacity(isHovered ? 1 : 0.75))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(.white.opacity(isHovered ? 0.16 : 0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Text(title))
        .accessibilityLabel(Text(title))
        .fixedSize()
        .onHover { isHovered = $0 }
        .accessibilityHint(Text("Opens the PancakeNotch window."))
    }
}

/// The time, on the minute, and at Medium the weekday and date. It reads the clock only while live.
struct HomeClockWidget: View {
    let size: HomeWidgetSize
    let context: HomeWidgetContext

    var body: some View {
        if context.isLive {
            TimelineView(.everyMinute) { timeline in face(timeline.date) }
        } else {
            face(context.now)
        }
    }

    @ViewBuilder private func face(_ date: Date) -> some View {
        if size == .small {
            HomeSmallFace(caption: nil) {
                Image(systemName: HomeWidgetKind.clock.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            } value: {
                time(date, size: 17)
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                time(date, size: 19)
                Text(date, format: .dateTime.weekday(.wide).month().day())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func time(_ date: Date, size: CGFloat) -> some View {
        Text(date, format: .dateTime.hour().minute())
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.25), value: date)
    }
}

/// Every module as a button, as the Module Menu had: click one to show it.
struct HomeAllModulesWidget: View {
    let resolver: HomeWidgetResolver
    let context: HomeWidgetContext

    var body: some View {
        let modules = resolver.arrangement.sorted(resolver.modules) { $0.moduleID }
        if modules.isEmpty {
            Text("No modules are on.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Every module as a button, three to a row (four once there are more than six), so they all
            // fit the Large card without scrolling.
            let perRow = modules.count > 6 ? 4 : 3
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(Array(stride(from: 0, to: modules.count, by: perRow)), id: \.self) { start in
                    GridRow {
                        ForEach(modules[start..<min(start + perRow, modules.count)], id: \.moduleID) { module in
                            HomeModuleButton(module: module, isCurrent: module.moduleID == resolver.currentModuleID,
                                             open: resolver.select.map { select in { select(module.moduleID) } })
                        }
                    }
                }
            }
            // The buttons reach closer to the card's edges.
            .padding(-HomeWidgetMetrics.padding + 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct HomeModuleButton: View {
    let module: any NotchModule
    let isCurrent: Bool
    let open: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        Button { open?() } label: {
            VStack(spacing: 3) {
                Image(systemName: module.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(isCurrent ? 0.18 : 0.09), in: .rect(cornerRadius: 8, style: .continuous))
                Text(module.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(isCurrent ? 0.95 : 0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(isHovered ? 0.07 : 0), in: .rect(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(open == nil)
        .onHover { isHovered = $0 && open != nil }
        .help(Text([module.title, module.menuStatus].compactMap { $0 }.joined(separator: " · ")))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([module.title, module.menuStatus].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : [.isButton])
        .accessibilityHint(Text("Shows \(module.title) in the notch."))
    }
}

public extension HomeWidgetKind {
    /// A click on the card opens something: its module, or Statistics. Clock, Battery and All Modules
    /// (whose rows are the buttons) have nothing to open.
    var opensFromHome: Bool {
        switch self {
        case .clock, .battery, .allModules: false
        default: true
        }
    }

    /// The name of the module the widget belongs to, as on the Modules page (Stopwatch is the Timer's).
    var moduleTitle: String {
        self == .stopwatch ? HomeWidgetKind.timer.title : title
    }
}
