import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, notch, keyboard, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .notch: String(localized: "Notch")
        case .keyboard: String(localized: "Keyboard")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .notch: "rectangle.topthird.inset.filled"
        case .keyboard: "command"
        case .about: "info.circle"
        }
    }

    /// The sidebar groups, in order.
    static let groups: [(title: String, sections: [SettingsSection])] = [
        (String(localized: "Settings"), [.general, .notch, .keyboard]),
        (String(localized: "App"), [.about]),
    ]
}

/// The companion app window: a sidebar of sections and their settings (ADR-0017).
struct SettingsView: View {
    @Bindable var preferences: Preferences
    let shortcuts: ShortcutController
    @State private var section: SettingsSection

    static let minimumSize = CGSize(width: 760, height: 520)

    init(preferences: Preferences, shortcuts: ShortcutController, section: SettingsSection = .general) {
        self.preferences = preferences
        self.shortcuts = shortcuts
        _section = State(initialValue: section)
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $section)
                .frame(width: 210)
                .background(SettingsPalette.sidebarBackground)

            SettingsPalette.hairline
                .frame(width: 1)

            Group {
                switch section {
                case .general: GeneralSettingsView(preferences: preferences)
                case .notch: NotchSettingsView(preferences: preferences)
                case .keyboard: KeyboardSettingsView(shortcuts: shortcuts)
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SettingsPalette.windowBackground)
        }
        .toggleStyle(MonochromeSwitchStyle())
        .buttonStyle(PillButtonStyle())
        .tint(.primary)
        .ignoresSafeArea()
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                NotchGlyph()
                Text("PancakeNotch")
                    .font(.headline)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 24)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(SettingsSection.groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title.uppercased())
                            .font(.caption.weight(.semibold))
                            .kerning(0.6)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 4)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.sections) { section in
                            SidebarRow(section: section, isSelected: section == selection) {
                                selection = section
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 16)
            Text(AppInfo.version)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 50)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct SidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.body.weight(.medium))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(section.title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(background, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var background: Color {
        if isSelected { return SettingsPalette.selection }
        return isHovered ? SettingsPalette.hover : .clear
    }
}

private struct GeneralSettingsView: View {
    @Bindable var preferences: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var needsApproval = LaunchAtLogin.needsApproval
    @State private var launchError: String?

    var body: some View {
        SettingsPage(
            title: String(localized: "General"),
            subtitle: String(localized: "How PancakeNotch starts and where you find it.")
        ) {
            SettingsCard(footer: footer) {
                SettingsRow(
                    title: String(localized: "Launch at login"),
                    subtitle: String(localized: "Start PancakeNotch automatically when you log in.")
                ) {
                    Toggle(String(localized: "Launch at login"), isOn: $launchAtLogin)
                        .labelsHidden()
                }
                if needsApproval {
                    SettingsRow(
                        title: String(localized: "Waiting for your approval"),
                        subtitle: String(localized: "Allow PancakeNotch in Login Items to finish turning this on.")
                    ) {
                        Button(String(localized: "Open Login Items")) { LaunchAtLogin.openSystemSettings() }
                    }
                }
                SettingsRow(
                    title: String(localized: "Show menu bar icon"),
                    subtitle: String(localized: "Quick access to Settings and Quit.")
                ) {
                    Toggle(String(localized: "Show menu bar icon"), isOn: $preferences.showMenuBarIcon)
                        .labelsHidden()
                }
            }
            .onChange(of: launchAtLogin) { _, enabled in
                guard enabled != LaunchAtLogin.isEnabled else { return }
                do {
                    try LaunchAtLogin.set(enabled)
                    launchError = nil
                } catch {
                    launchError = error.localizedDescription
                }
                launchAtLogin = LaunchAtLogin.isEnabled
                needsApproval = LaunchAtLogin.needsApproval
            }
        }
    }

    /// A launch-at-login problem, or how to get back here without the menu bar icon.
    private var footer: String? {
        if let launchError { return launchError }
        if !preferences.showMenuBarIcon {
            return String(localized: "To come back here, open PancakeNotch again from your Applications folder.")
        }
        return nil
    }
}

private struct NotchSettingsView: View {
    @Bindable var preferences: Preferences

    var body: some View {
        SettingsPage(
            title: String(localized: "Notch"),
            subtitle: String(localized: "How the notch reacts to your pointer.")
        ) {
            SettingsCard(header: String(localized: "Hover")) {
                DelayRow(
                    title: String(localized: "Open after hovering for"),
                    subtitle: String(localized: "How long the pointer rests on the notch before it opens."),
                    value: $preferences.openDelayMilliseconds,
                    range: 0...1000
                )
                DelayRow(
                    title: String(localized: "Close after leaving for"),
                    subtitle: String(localized: "How long the notch stays open after the pointer leaves."),
                    value: $preferences.closeDelayMilliseconds,
                    range: 100...1500
                )
            }

            SettingsCard(header: String(localized: "Feedback")) {
                SettingsRow(
                    title: String(localized: "Tap the trackpad when the notch opens"),
                    subtitle: String(localized: "A light click you feel on Force Touch trackpads.")
                ) {
                    Toggle(String(localized: "Tap the trackpad when the notch opens"), isOn: $preferences.hapticOnOpen)
                        .labelsHidden()
                }
            }
        }
    }
}

private struct DelayRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                SettingsRowLabel(title: title, subtitle: subtitle)
                Text(label)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
            MonochromeSlider(
                value: $value,
                range: range,
                accessibilityLabel: title,
                accessibilityValue: label
            )
        }
        .settingsRowPadding()
    }

    private var label: String {
        String(localized: "\(Int(value)) ms")
    }
}

private struct KeyboardSettingsView: View {
    let shortcuts: ShortcutController
    @State private var hint: String?

    var body: some View {
        SettingsPage(
            title: String(localized: "Keyboard"),
            subtitle: String(localized: "Shortcuts that work from any app.")
        ) {
            SettingsCard(
                header: String(localized: "Shortcuts"),
                footer: String(localized: "Click the box, then press the keys you want. Esc cancels, Delete clears.")
            ) {
                SettingsRow(
                    title: String(localized: "Open and close the notch"),
                    subtitle: hint ?? shortcuts.errorMessage ?? String(localized: "Shows or hides the notch, wherever you are.")
                ) {
                    ShortcutRecorder(controller: shortcuts, hint: $hint)
                }
            }
        }
    }
}

private struct AboutView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsPage(
            title: String(localized: "About"),
            subtitle: String(localized: "A free, open-source app that puts your MacBook's notch to work.")
        ) {
            NotchBanner()

            SettingsCard {
                SettingsRow(
                    title: String(localized: "Source code"),
                    subtitle: String(localized: "Follow along, report a bug or help out on GitHub.")
                ) {
                    Button { openURL(AppInfo.sourceCode) } label: {
                        Label(String(localized: "View on GitHub"), systemImage: "arrow.up.right")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                }
                SettingsRow(
                    title: String(localized: "License"),
                    subtitle: String(localized: "Free and open source under the GPL-3.0 license.")
                ) {
                    Button { openURL(AppInfo.license) } label: {
                        Label(String(localized: "Read License"), systemImage: "arrow.up.right")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                }
            }
        }
    }
}

/// Text first, then a small icon, as on links that leave the app.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
