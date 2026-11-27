import AppKit
import SwiftUI

/// The top-left corner of the open notch: how you move between places (ADR-0010, ADR-0042, ADR-0045). It
/// reads as a map: the Library and Home, then a tab per favorite module (or every module, with tabs only),
/// and swipes and ←/→ walk it in that order. With the "Home" navigation choice it shows the current module's
/// name, which opens Home, beside the Library button.
struct NotchModuleBar: View {
    let model: NotchViewModel
    /// The selection capsule glides between the bar's buttons and the tab beside the camera.
    let highlight: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isMenuHovered = false

    /// From the notch body's left edge to the first button.
    static let leadingInset: CGFloat = 16
    static let buttonSize = CGSize(width: 28, height: 22)
    static let spacing: CGFloat = 2
    /// The hairline between the places (Library, Home) and the tabs, with its margins.
    static let dividerWidth: CGFloat = 9
    /// Room left after the bar before a module's own header content.
    static let trailingGap: CGFloat = 10
    static let titleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    static let minButtonWidth: CGFloat = 22
    /// From the camera's right edge to the tab beside it, and after it to the module's own controls.
    static let visitingGap: CGFloat = 10
    static let visitingTrailingGap: CGFloat = 8

    /// The room the tab beside the camera takes on the band's right side.
    static func visitingTabRoom(_ fit: Fit) -> CGFloat { visitingGap + fit.buttonWidth + visitingTrailingGap }

    /// How far the bar reaches from the body's left edge, so modules can start their header after it.
    static func width(for model: NotchViewModel) -> CGFloat {
        leadingInset + fit(for: model).contentWidth + trailingGap
    }

    /// Fits the bar beside the camera cutout. Tabs never shrink below `minButtonWidth`: favorites past the
    /// room drop off from the lowest ranked, and adding a favorite is refused once the bar is full, so that
    /// only happens to favorites saved before (or a smaller screen). Those, and every module without a tab,
    /// live in the Library.
    struct Fit {
        let available: CGFloat
        let buttonWidth: CGFloat
        /// The "Home" navigation choice: the current module's name instead of Home and the tabs.
        let usesNameButton: Bool
        let contentWidth: CGFloat
        /// The tab modules shown, in order.
        let tabModuleIDs: [String]
        /// How many tabs the bar has room for beside its place buttons.
        let capacity: Int
    }

    static func fit(for model: NotchViewModel) -> Fit {
        let layout = model.layout
        let sideWidth = (layout.bodySize(for: .expanded).width - layout.geometry.notchRect.width) / 2
        let available = max(0, sideWidth - leadingInset - trailingGap)
        if model.arrangement.navigation == .menu {
            let width = menuButtonWidth(title: menuTitle(for: model)) + spacing + buttonSize.width
            return Fit(available: available, buttonWidth: buttonSize.width, usesNameButton: true,
                       contentWidth: min(width, available), tabModuleIDs: [], capacity: 0)
        }
        let places = model.homeIsAvailable ? 2 : 1
        var capacity = 0
        while barWidth(places: places, tabs: capacity + 1, buttonWidth: minButtonWidth) <= available { capacity += 1 }
        let tabs = Array(model.tabModules.map(\.moduleID).prefix(capacity))
        let buttons = CGFloat(places + tabs.count)
        let gaps = barWidth(places: places, tabs: tabs.count, buttonWidth: 0)
        let buttonWidth = min(buttonSize.width, max(minButtonWidth, floor((available - gaps) / buttons)))
        let width = barWidth(places: places, tabs: tabs.count, buttonWidth: buttonWidth)
        return Fit(available: available, buttonWidth: buttonWidth, usesNameButton: false,
                   contentWidth: min(width, available), tabModuleIDs: tabs, capacity: capacity)
    }

    /// Place buttons side by side, then the divider and the tabs.
    private static func barWidth(places: Int, tabs: Int, buttonWidth: CGFloat) -> CGFloat {
        let placesWidth = CGFloat(places) * buttonWidth + CGFloat(max(0, places - 1)) * spacing
        guard tabs > 0 else { return placesWidth }
        return placesWidth + dividerWidth + CGFloat(tabs) * buttonWidth + CGFloat(tabs - 1) * spacing
    }

    /// Icon, name and chevron of the "Home" choice's name button.
    private static func menuButtonWidth(title: String) -> CGFloat {
        let text = (title as NSString).size(withAttributes: [.font: titleFont]).width
        return 8 + 14 + 6 + ceil(text) + 2 + 6 + 10 + 8
    }

    static func menuTitle(for model: NotchViewModel) -> String {
        model.showsHome ? String(localized: "Home", comment: "The notch's Home, its title in the bar") : model.selectedModule?.title ?? ""
    }

    var body: some View {
        let fit = Self.fit(for: model)
        let libraryFirst = model.arrangement.librarySide == .left
        HStack(spacing: Self.spacing) {
            if fit.usesNameButton {
                if libraryFirst { libraryButton(fit) }
                menuNameButton
                if !libraryFirst { libraryButton(fit) }
            } else if model.homeIsAvailable {
                if libraryFirst { libraryButton(fit) }
                homeButton(fit)
                if !libraryFirst { libraryButton(fit) }
                if !fit.tabModuleIDs.isEmpty { divider }
                tabs(fit)
            } else if libraryFirst {
                libraryButton(fit)
                if !fit.tabModuleIDs.isEmpty { divider }
                tabs(fit)
            } else {
                tabs(fit)
                if !fit.tabModuleIDs.isEmpty { divider }
                libraryButton(fit)
            }
        }
        .frame(width: fit.contentWidth, alignment: .leading)
        .clipped()
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.85), value: model.currentPlace)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.85), value: fit.tabModuleIDs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Modules"))
    }

    private var divider: some View {
        Capsule()
            .fill(.white.opacity(0.16))
            .frame(width: 1, height: 12)
            .frame(width: Self.dividerWidth - Self.spacing * 2)
            .accessibilityHidden(true)
    }

    private func tabs(_ fit: Fit) -> some View {
        ForEach(fit.tabModuleIDs, id: \.self) { id in
            if let module = model.modules.first(where: { $0.moduleID == id }) {
                let isSelected = model.showsModule && id == model.selectedModule?.moduleID
                NotchBarButton(symbol: module.symbol, isSelected: isSelected, highlight: highlight,
                               width: fit.buttonWidth) {
                    model.select(id)
                }
                .moduleMenu(model: model, moduleID: id)
                .help(Text(module.title))
                .accessibilityLabel(Text(module.title))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityHint(Text("Shows \(module.title) in the notch."))
                .moduleMenuAccessibilityActions(model: model, moduleID: id)
                .transition(.opacity)
            }
        }
    }

    private func homeButton(_ fit: Fit) -> some View {
        NotchBarButton(symbol: HomeSymbol.name, isSelected: model.showsHome, highlight: highlight,
                       width: fit.buttonWidth) {
            model.toggleHome()
        }
        .help(Text("Home"))
        .accessibilityLabel(Text("Home"))
        .accessibilityAddTraits(model.showsHome ? [.isSelected] : [])
        .accessibilityHint(Text("Shows your widgets."))
    }

    private func libraryButton(_ fit: Fit) -> some View {
        let swipe = model.arrangement.librarySide == .left
            ? String(localized: "Library (or swipe right on Home)", comment: "Library button's tooltip: fingers move right")
            : String(localized: "Library (or swipe left on Home)", comment: "Library button's tooltip: fingers move left")
        return NotchBarButton(symbol: LibrarySymbol.name, isSelected: model.showsLibrary, highlight: highlight,
                              width: fit.buttonWidth) {
            model.toggleLibrary()
        }
        .help(Text(model.homeIsAvailable ? swipe : String(localized: "Library")))
        .accessibilityLabel(Text("Library"))
        .accessibilityAddTraits(model.showsLibrary ? [.isSelected] : [])
        .accessibilityHint(Text("Shows every module, with a search."))
    }

    /// "Home" navigation: the current module's icon and name; click for Home.
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
        .accessibilityHint(Text("Shows your widgets."))
    }
}

/// The Library's symbol, in the bar and the Notch settings.
public enum LibrarySymbol {
    public static let name = "square.grid.2x2"
}

/// One icon button in the bar (and the tab beside the camera). The selected one sits on a soft capsule that
/// slides between buttons (with Reduce Motion it fades from one to the next instead).
struct NotchBarButton: View {
    let symbol: String
    let isSelected: Bool
    let highlight: Namespace.ID
    let width: CGFloat
    /// The selection capsule glides here from the button before (off for the tab beside the camera, which
    /// would carry it across under the camera).
    var glides = true
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
                            .modifier(SelectionSlide(namespace: highlight, slides: glides && !reduceMotion))
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
