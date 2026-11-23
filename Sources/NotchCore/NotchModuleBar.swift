import AppKit
import SwiftUI

/// The top-left corner of the open notch: how you move between modules (ADR-0010, ADR-0042). Depending on the
/// Notch setting it shows a Home button and tabs for the favorite modules, tabs for every module, or
/// just the current module's name, which opens Home.
struct NotchModuleBar: View {
    let model: NotchViewModel
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isMenuHovered = false

    /// From the notch body's left edge to the first button.
    static let leadingInset: CGFloat = 16
    static let buttonSize = CGSize(width: 28, height: 22)
    static let spacing: CGFloat = 2
    /// The hairline between the Home button and the tabs, with its margins.
    static let dividerWidth: CGFloat = 9
    /// Room left after the bar before a module's own header content.
    static let trailingGap: CGFloat = 10
    static let titleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)

    /// How far the bar reaches from the body's left edge, so modules can start their header after it.
    static func width(for model: NotchViewModel) -> CGFloat {
        leadingInset + fit(for: model).contentWidth + trailingGap
    }

    /// Fit every button beside the camera cutout. Compact spacing keeps six modules visible. With Home and
    /// tabs, favorites that still don't fit drop off from the lowest ranked (the current module always stays),
    /// since Home reaches every module. Only Tabs falls back to the current module's name button, and only
    /// when even that can't fit; the name button is otherwise just the "Home" choice in Notch settings.
    struct Fit {
        let available: CGFloat
        let buttonWidth: CGFloat
        let usesMenu: Bool
        let contentWidth: CGFloat
        /// The tab modules shown, in order.
        let tabModuleIDs: [String]
    }

    static func fit(for model: NotchViewModel) -> Fit {
        let layout = model.layout
        let sideWidth = (layout.bodySize(for: .expanded).width - layout.geometry.notchRect.width) / 2
        let available = max(0, sideWidth - leadingInset - trailingGap)
        let navigation = model.arrangement.navigation
        let hasMenu = navigation == .tabsAndMenu
        var tabs = model.tabModules.map(\.moduleID)
        if hasMenu {
            let current = model.selectedModule?.moduleID
            while tabs.count > 1, tabsWidth(count: tabs.count, hasMenu: true, buttonWidth: minButtonWidth) > available,
                  let drop = tabs.lastIndex(where: { $0 != current }) {
                tabs.remove(at: drop)
            }
        }
        let count = tabs.count
        let buttons = count + (hasMenu ? 1 : 0)
        let gaps = CGFloat(max(0, count - 1)) * spacing + (hasMenu ? dividerWidth : 0)
        let buttonWidth = min(buttonSize.width, max(minButtonWidth, floor((available - gaps) / CGFloat(max(1, buttons)))))
        let width = tabsWidth(count: count, hasMenu: hasMenu, buttonWidth: buttonWidth)
        let usesMenu = navigation == .menu || width > available
        let content = usesMenu ? menuButtonWidth(title: menuTitle(for: model)) : width
        return Fit(available: available, buttonWidth: buttonWidth, usesMenu: usesMenu,
                   contentWidth: min(content, available), tabModuleIDs: usesMenu ? [] : tabs)
    }

    static let minButtonWidth: CGFloat = 22

    private static func tabsWidth(count: Int, hasMenu: Bool, buttonWidth: CGFloat) -> CGFloat {
        let buttons = count + (hasMenu ? 1 : 0)
        let gaps = CGFloat(max(0, count - 1)) * spacing + (hasMenu ? dividerWidth : 0)
        return CGFloat(buttons) * buttonWidth + gaps
    }

    /// Icon, name and chevron of the "Home only" button.
    private static func menuButtonWidth(title: String) -> CGFloat {
        let text = (title as NSString).size(withAttributes: [.font: titleFont]).width
        return 8 + 14 + 6 + ceil(text) + 2 + 6 + 10 + 8
    }

    static func menuTitle(for model: NotchViewModel) -> String {
        model.showsHome ? String(localized: "Home", comment: "The notch's Home, its title in the bar") : model.selectedModule?.title ?? ""
    }

    var body: some View {
        let fit = Self.fit(for: model)
        HStack(spacing: Self.spacing) {
            if fit.usesMenu {
                menuNameButton
            } else {
                if model.arrangement.navigation == .tabsAndMenu {
                    menuButton(fit)
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(width: 1, height: 12)
                        .frame(width: Self.dividerWidth - Self.spacing * 2)
                        .accessibilityHidden(true)
                }
                tabs(fit)
            }
        }
        .frame(width: fit.contentWidth, alignment: .leading)
        .clipped()
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.85), value: model.selectedModule?.moduleID)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.85), value: model.showsHome)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Modules"))
    }

    private func tabs(_ fit: Fit) -> some View {
        let shown = Set(fit.tabModuleIDs)
        return ForEach(model.tabModules.filter { shown.contains($0.moduleID) }, id: \.moduleID) { module in
            let isSelected = !model.showsHome && module.moduleID == model.selectedModule?.moduleID
            BarButton(symbol: module.symbol, isSelected: isSelected, highlight: highlight,
                      width: fit.buttonWidth) {
                model.select(module.moduleID)
            }
            .help(Text(module.title))
            .accessibilityLabel(Text(module.title))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityHint(Text("Shows \(module.title) in the notch."))
        }
    }

    private func menuButton(_ fit: Fit) -> some View {
        BarButton(symbol: HomeSymbol.name, isSelected: model.showsHome, highlight: highlight,
                  width: fit.buttonWidth) {
            model.toggleHome()
        }
        .help(Text("Home"))
        .accessibilityLabel(Text("Home"))
        .accessibilityAddTraits(model.showsHome ? [.isSelected] : [])
        .accessibilityHint(Text("Shows your widgets and every module."))
    }

    /// "Home only": the current module's icon and name; click for Home.
    private var menuNameButton: some View {
        Button {
            model.toggleHome()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.showsHome ? HomeSymbol.name : model.selectedModule?.symbol ?? "square")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                Text(Self.menuTitle(for: model))
                    .font(Font(Self.titleFont))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .rotationEffect(.degrees(model.showsHome ? 180 : 0))
            }
            .padding(.horizontal, 8)
            .frame(height: Self.buttonSize.height)
            .background(.white.opacity(model.showsHome ? 0.16 : isMenuHovered ? 0.13 : 0.08), in: Capsule())
            .foregroundStyle(.white)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isMenuHovered = $0 }
        // On Home with no module to go back to, there is nowhere else to go.
        .disabled(model.showsHome && model.selectedModule == nil)
        .accessibilityLabel(Text(model.showsHome ? String(localized: "Close Home") : String(localized: "\(Self.menuTitle(for: model)), opens Home")))
        .accessibilityHint(Text("Shows your widgets and every module."))
    }
}

/// One icon button in the bar. The selected one sits on a soft capsule that slides between buttons
/// (with Reduce Motion it fades from one to the next instead).
private struct BarButton: View {
    let symbol: String
    let isSelected: Bool
    let highlight: Namespace.ID
    let width: CGFloat
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(isSelected ? 1 : isHovered ? 0.85 : 0.5))
                .frame(width: width, height: NotchModuleBar.buttonSize.height)
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
