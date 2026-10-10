import ModuleShelf
import SwiftUI

/// The pages of the app window, in sidebar order.
enum AppSection: String, CaseIterable, Identifiable {
    case home, modules, general, notch, keyboard, about

    var id: Self { self }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .modules: String(localized: "Modules")
        case .general: String(localized: "General")
        case .notch: String(localized: "Notch")
        case .keyboard: String(localized: "Keyboard")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .modules: "square.grid.2x2"
        case .general: "gearshape"
        case .notch: "rectangle.topthird.inset.filled"
        case .keyboard: "command"
        case .about: "info.circle"
        }
    }

    /// ⌘1, ⌘2, … in sidebar order.
    var shortcutKey: KeyEquivalent {
        KeyEquivalent(Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1)))
    }
}

/// The app window: a dark sidebar and the page it points at. It opens on Home, a small dashboard
/// with the notch's on/off switch; settings are one section of it (ADR-0017).
struct AppWindowView: View {
    @Bindable var preferences: Preferences
    let shortcuts: ShortcutController
    let stats: UsageStats
    let shelfSettings: ShelfSettings
    let shelfStore: ShelfStore
    @State private var section: AppSection

    static let defaultSize = CGSize(width: 1000, height: 780)
    static let minimumSize = CGSize(width: 860, height: 600)

    init(
        preferences: Preferences,
        shortcuts: ShortcutController,
        stats: UsageStats,
        shelfSettings: ShelfSettings,
        shelfStore: ShelfStore,
        section: AppSection = .home
    ) {
        self.preferences = preferences
        self.shortcuts = shortcuts
        self.stats = stats
        self.shelfSettings = shelfSettings
        self.shelfStore = shelfStore
        _section = State(initialValue: section)
    }

    var body: some View {
        HStack(spacing: 0) {
            AppSidebar(selection: $section)
                .frame(width: 232)
                .background(AppPalette.sidebar)

            AppPalette.hairline
                .frame(width: 1)

            Group {
                switch section {
                case .home:
                    HomeView(
                        preferences: preferences,
                        shortcuts: shortcuts,
                        stats: stats,
                        shelfSettings: shelfSettings,
                        shelfStore: shelfStore,
                        section: $section
                    )
                case .modules: ModulesView(shelfSettings: shelfSettings, shelfStore: shelfStore)
                case .general: GeneralSettingsView(preferences: preferences)
                case .notch: NotchSettingsView(preferences: preferences, shelfSettings: shelfSettings)
                case .keyboard: KeyboardSettingsView(shortcuts: shortcuts)
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppPalette.background)
        }
        .toggleStyle(MonochromeSwitchStyle())
        .buttonStyle(PillButtonStyle())
        .tint(.white)
        .foregroundStyle(AppPalette.primaryText)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }
}

private struct AppSidebar: View {
    @Binding var selection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Same columns as the rows below: the logo centred over their icons, the name
            // starting where their titles start.
            HStack(spacing: SidebarRow.iconSpacing) {
                NotchGlyph(size: 22)
                    .frame(width: SidebarRow.iconWidth)
                Text("PancakeNotch")
                    .font(.app(size: 15, weight: .bold))
                    .kerning(-0.2)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 28)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 2) {
                row(.home)
                row(.modules)
            }

            SectionLabel(title: String(localized: "Settings"))
                .padding(.horizontal, 10)
                .padding(.top, 26)
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 2) {
                row(.general)
                row(.notch)
                row(.keyboard)
            }

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 2) {
                row(.about)
                QuitRow()
            }
            Text(AppInfo.version)
                .font(.app(size: 11))
                .foregroundStyle(AppPalette.tertiaryText)
                .padding(.horizontal, 10)
                .padding(.top, 12)
        }
        .padding(.horizontal, 12)
        .padding(.top, 54)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func row(_ section: AppSection) -> some View {
        SidebarRow(title: section.title, symbol: section.symbol, isSelected: section == selection) {
            selection = section
        }
        .keyboardShortcut(section.shortcutKey, modifiers: .command)
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    var isSelected = false
    let action: () -> Void
    @State private var isHovered = false

    static let iconWidth: CGFloat = 18
    static let iconSpacing: CGFloat = 11

    var body: some View {
        Button(action: action) {
            HStack(spacing: Self.iconSpacing) {
                Image(systemName: symbol)
                    .font(.app(size: 13, weight: .medium))
                    .frame(width: Self.iconWidth)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.app(size: 13.5, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected || isHovered ? AppPalette.primaryText : AppPalette.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? AppPalette.selection : isHovered ? AppPalette.hover : .clear)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(AppPalette.hairline)
                        }
                    }
            }
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Quits the whole app, notch included. Turning only the notch off is on Home.
private struct QuitRow: View {
    var body: some View {
        SidebarRow(title: String(localized: "Quit PancakeNotch"), symbol: "power") {
            NSApp.terminate(nil)
        }
        .help(Text("Quits the app. The notch goes away until you open PancakeNotch again."))
        .accessibilityHint(Text("Quits the app. To only hide the notch, use the switch on Home."))
    }
}
