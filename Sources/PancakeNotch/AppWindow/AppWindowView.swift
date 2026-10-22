import Learn
import ModuleShelf
import NotchCore
import SwiftUI

/// The pages of the app window, in sidebar order.
enum AppSection: String, CaseIterable, Identifiable {
    case home, modules, learn, statistics, general, notch, keyboard, help, about

    var id: Self { self }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .modules: String(localized: "Modules")
        case .learn: String(localized: "Learn")
        case .statistics: String(localized: "Statistics")
        case .general: String(localized: "General")
        case .notch: String(localized: "Notch")
        case .keyboard: String(localized: "Keyboard")
        case .help: String(localized: "Help")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .modules: "square.grid.2x2"
        case .learn: "graduationcap"
        case .statistics: "chart.bar.xaxis"
        case .general: "gearshape"
        case .notch: "rectangle.topthird.inset.filled"
        case .keyboard: "command"
        case .help: "questionmark.circle"
        case .about: "info.circle"
        }
    }

    /// ⌘1, ⌘2, … in sidebar order.
    var shortcutKey: KeyEquivalent {
        KeyEquivalent(Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1)))
    }
}

/// The app window: a dark sidebar and the page it points at. It opens on Home, a small dashboard
/// with the notch's on/off switch; settings are one section of it (ADR-0017). Until the welcome has
/// been seen, the welcome fills the window instead (ADR-0020).
struct AppWindowView: View {
    let context: AppContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let defaultSize = CGSize(width: 1000, height: 780)
    static let minimumSize = CGSize(width: 860, height: 600)

    private var progress: LearnProgress { context.progress }
    private var preferences: Preferences { context.preferences }
    private var navigation: AppNavigation { context.navigation }

    var body: some View {
        ZStack {
            if progress.onboardingDone {
                main
                    .transition(.opacity)
            } else {
                OnboardingView(context: context)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.3), value: progress.onboardingDone)
        // The welcome ends on Home (also when it was replayed from About), or on Learn if asked.
        .onChange(of: progress.onboardingDone) { _, done in
            guard done else { return }
            navigation.section = navigation.sectionAfterWelcome
            navigation.sectionAfterWelcome = .home
        }
        .appWindowStyle()
    }

    private var main: some View {
        @Bindable var navigation = navigation
        return HStack(spacing: 0) {
            AppSidebar(selection: $navigation.section)
                .frame(width: 232)
                .background(AppPalette.sidebar)

            AppPalette.hairline
                .frame(width: 1)

            Group {
                switch navigation.section {
                case .home:
                    HomeView(context: context, section: $navigation.section, openLesson: navigation.open)
                case .modules:
                    ModulesView(context: context, openLesson: navigation.open)
                case .learn:
                    LearnView(context: context, lesson: $navigation.lesson)
                case .statistics:
                    StatsView(store: context.statsStore, usage: context.usage, agentsSettings: context.agentsSettings, helperPID: { [nowPlaying = context.nowPlaying] in nowPlaying.helperProcessID })
                case .general: GeneralSettingsView(preferences: preferences, updates: context.updates)
                case .notch: NotchSettingsView(context: context) { navigation.section = .modules }
                case .keyboard: KeyboardSettingsView(shortcuts: context.shortcuts)
                case .help: HelpView(context: context)
                case .about: AboutView(progress: progress)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppPalette.background)
        }
    }
}

extension View {
    /// The window's look: monochrome controls, white text, always dark, filling the window.
    func appWindowStyle() -> some View {
        toggleStyle(MonochromeSwitchStyle())
            .buttonStyle(PillButtonStyle())
            .tint(.white)
            .foregroundStyle(AppPalette.primaryText)
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea()
            .frame(minWidth: AppWindowView.minimumSize.width, minHeight: AppWindowView.minimumSize.height)
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
                row(.learn)
                row(.statistics)
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
                row(.help)
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
