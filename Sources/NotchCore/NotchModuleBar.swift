import AppKit
import SwiftUI

/// The top-left corner of the open notch: how you move between modules (ADR-0010). Depending on the
/// Notch setting it shows a Menu button and tabs for the favorite modules, tabs for every module, or
/// just the current module's name, which opens the Menu.
struct NotchModuleBar: View {
    let model: NotchViewModel
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isMenuHovered = false

    /// From the notch body's left edge to the first button.
    static let leadingInset: CGFloat = 16
    static let buttonSize = CGSize(width: 28, height: 22)
    static let spacing: CGFloat = 2
    /// The hairline between the Menu button and the tabs, with its margins.
    static let dividerWidth: CGFloat = 9
    /// Room left after the bar before a module's own header content.
    static let trailingGap: CGFloat = 10
    static let titleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)

    /// How far the bar reaches from the body's left edge, so modules can start their header after it.
    static func width(for model: NotchViewModel) -> CGFloat {
        let content: CGFloat
        switch model.arrangement.navigation {
        case .menu:
            content = menuButtonWidth(title: menuTitle(for: model))
        case .tabs:
            content = tabsWidth(count: model.tabModules.count)
        case .tabsAndMenu:
            content = buttonSize.width + dividerWidth + tabsWidth(count: model.tabModules.count)
        }
        return leadingInset + content + trailingGap
    }

    private static func tabsWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * buttonSize.width + CGFloat(count - 1) * spacing
    }

    /// Icon, name and chevron of the "Menu only" button.
    private static func menuButtonWidth(title: String) -> CGFloat {
        let text = (title as NSString).size(withAttributes: [.font: titleFont]).width
        return 8 + 14 + 6 + ceil(text) + 5 + 8 + 9
    }

    static func menuTitle(for model: NotchViewModel) -> String {
        model.showsMenu ? String(localized: "Modules", comment: "Notch Menu title") : model.selectedModule?.title ?? ""
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            switch model.arrangement.navigation {
            case .menu:
                menuNameButton
            case .tabs:
                tabs
            case .tabsAndMenu:
                menuButton
                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(width: 1, height: 12)
                    .frame(width: Self.dividerWidth - Self.spacing * 2)
                    .accessibilityHidden(true)
                tabs
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.85), value: model.selectedModule?.moduleID)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.85), value: model.showsMenu)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Modules"))
    }

    private var tabs: some View {
        ForEach(model.tabModules, id: \.moduleID) { module in
            let isSelected = !model.showsMenu && module.moduleID == model.selectedModule?.moduleID
            BarButton(symbol: module.symbol, isSelected: isSelected, highlight: highlight) {
                model.select(module.moduleID)
            }
            .help(Text(module.title))
            .accessibilityLabel(Text(module.title))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityHint(Text("Shows \(module.title) in the notch."))
        }
    }

    private var menuButton: some View {
        BarButton(symbol: "square.grid.2x2", isSelected: model.showsMenu, highlight: highlight) {
            model.toggleMenu()
        }
        .help(Text("Module Menu"))
        .accessibilityLabel(Text("Module Menu"))
        .accessibilityAddTraits(model.showsMenu ? [.isSelected] : [])
        .accessibilityHint(Text("Shows every module, your favorites and a way to the settings."))
    }

    /// "Menu only": the current module's icon and name; click for the Menu.
    private var menuNameButton: some View {
        Button {
            model.toggleMenu()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.showsMenu ? "square.grid.2x2" : model.selectedModule?.symbol ?? "square")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                Text(Self.menuTitle(for: model))
                    .font(Font(Self.titleFont))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .rotationEffect(.degrees(model.showsMenu ? 180 : 0))
            }
            .padding(.horizontal, 8)
            .frame(height: Self.buttonSize.height)
            .background(.white.opacity(model.showsMenu ? 0.16 : isMenuHovered ? 0.13 : 0.08), in: Capsule())
            .foregroundStyle(.white)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isMenuHovered = $0 }
        .accessibilityLabel(Text(model.showsMenu ? String(localized: "Close the Module Menu") : String(localized: "\(Self.menuTitle(for: model)), Module Menu")))
        .accessibilityHint(Text("Shows every module, your favorites and a way to the settings."))
    }
}

/// One icon button in the bar. The selected one sits on a soft capsule that slides between buttons
/// (with Reduce Motion it fades from one to the next instead).
private struct BarButton: View {
    let symbol: String
    let isSelected: Bool
    let highlight: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(isSelected ? 1 : isHovered ? 0.85 : 0.5))
                .frame(width: NotchModuleBar.buttonSize.width, height: NotchModuleBar.buttonSize.height)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.white.opacity(0.16))
                            .modifier(SelectionSlide(namespace: highlight, slides: !reduceMotion))
                            .transition(.opacity)
                    } else if isHovered {
                        Capsule().fill(.white.opacity(0.07))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// The Module Menu in the open notch (ADR-0010): favorites as big tiles on the left, every module in a
/// list on the right (the panel is wide and short, so side by side instead of stacked), and a gear for
/// the app window.
struct NotchMenuView: View {
    let model: NotchViewModel
    let layout: NotchLayout

    private static let sidePadding: CGFloat = 18
    private static let tileSize = CGSize(width: 74, height: 58)

    var body: some View {
        let size = layout.bodySize(for: .expanded)
        let notch = layout.geometry.notchRect.size
        VStack(spacing: 0) {
            // The band beside the hardware notch: the bar sits on the left (drawn by NotchView), the gear right.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Color.clear.frame(width: notch.width)
                HStack {
                    Spacer(minLength: 0)
                    if let openSettings = model.openSettings {
                        GearButton(action: openSettings)
                    }
                }
                .frame(maxWidth: (size.width - notch.width) / 2 - Self.sidePadding)
            }
            .frame(height: notch.height)
            .padding(.horizontal, Self.sidePadding)

            HStack(alignment: .top, spacing: 16) {
                favorites
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1)
                    .padding(.vertical, 2)
                    .accessibilityHidden(true)
                allModules
            }
            .padding(.horizontal, Self.sidePadding)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .foregroundStyle(.white)
        // Clicks on empty space shrink the notch, like everywhere else in it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Module Menu"))
    }

    private var favoriteModules: [any NotchModule] {
        model.rankedModules.filter { model.arrangement.isFavorite($0.moduleID) }
    }

    private var favorites: some View {
        VStack(alignment: .leading, spacing: 7) {
            MenuLabel(title: String(localized: "Favorites"))
            if favoriteModules.isEmpty {
                Text("Make a module a favorite (★) to keep it here and in the tabs.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: Self.tileSize.width * 2 + 8, alignment: .leading)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.tileSize.width), spacing: 8), count: min(3, max(2, favoriteModules.count))), alignment: .leading, spacing: 8) {
                    ForEach(favoriteModules, id: \.moduleID) { module in
                        FavoriteTile(module: module, isCurrent: module.moduleID == model.selectedModule?.moduleID, size: Self.tileSize) {
                            model.select(module.moduleID)
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var allModules: some View {
        VStack(alignment: .leading, spacing: 5) {
            MenuLabel(title: String(localized: "All modules"))
            let rows = VStack(spacing: 2) {
                ForEach(model.rankedModules, id: \.moduleID) { module in
                    ModuleRow(
                        module: module,
                        isCurrent: module.moduleID == model.selectedModule?.moduleID,
                        isFavorite: model.arrangement.isFavorite(module.moduleID),
                        toggleFavorite: { model.arrangement.toggleFavorite(module.moduleID) },
                        open: { model.select(module.moduleID) }
                    )
                }
            }
            // A scroll view only when the rows don't fit: off-screen snapshots can't draw one.
            ViewThatFits(in: .vertical) {
                rows
                ScrollView(.vertical) { rows }
                    .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MenuLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .kerning(0.7)
            .foregroundStyle(.white.opacity(0.45))
            .accessibilityAddTraits(.isHeader)
    }
}

private struct FavoriteTile: View {
    let module: any NotchModule
    let isCurrent: Bool
    let size: CGSize
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: module.symbol)
                    .font(.system(size: 17, weight: .medium))
                Text(module.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white.opacity(isCurrent || isHovered ? 1 : 0.8))
            .frame(width: size.width, height: size.height)
            .background(.white.opacity(isCurrent ? 0.15 : isHovered ? 0.1 : 0.06), in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(isCurrent ? 0.22 : 0.06))
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(module.title))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .accessibilityHint(Text("Shows \(module.title) in the notch."))
    }
}

private struct ModuleRow: View {
    let module: any NotchModule
    let isCurrent: Bool
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            Button(action: open) {
                HStack(spacing: 9) {
                    Image(systemName: module.symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.09), in: .rect(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(module.title)
                            .font(.system(size: 12, weight: .semibold))
                        if let status = module.menuStatus {
                            Text(status)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    if isCurrent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            .accessibilityHint(Text("Shows \(module.title) in the notch."))

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(isFavorite ? 0.9 : 0.4))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(Text(isFavorite ? String(localized: "Remove from favorites") : String(localized: "Add to favorites")))
            .accessibilityLabel(Text(isFavorite
                ? String(localized: "Remove \(module.title) from favorites")
                : String(localized: "Add \(module.title) to favorites")))
        }
        // The star's 24 pt target has room around the glyph: the right side needs less.
        .padding(.leading, 7)
        .padding(.trailing, 2)
        .frame(height: 36)
        .background(.white.opacity(isHovered ? 0.07 : 0), in: .rect(cornerRadius: 9, style: .continuous))
        .onHover { isHovered = $0 }
    }
}

private struct GearButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
                Text("Settings")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(isHovered ? 1 : 0.75))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(.white.opacity(isHovered ? 0.16 : 0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityHint(Text("Opens the PancakeNotch window."))
    }
}

/// The selection capsule glides between bar buttons, unless Reduce Motion is on.
private struct SelectionSlide: ViewModifier {
    let namespace: Namespace.ID
    let slides: Bool

    func body(content: Content) -> some View {
        if slides {
            content.matchedGeometryEffect(id: "selection", in: namespace)
        } else {
            content
        }
    }
}
