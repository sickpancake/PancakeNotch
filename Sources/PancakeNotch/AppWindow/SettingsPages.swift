import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var preferences: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var needsApproval = LaunchAtLogin.needsApproval
    @State private var launchError: String?

    var body: some View {
        AppPage(
            title: String(localized: "General"),
            subtitle: String(localized: "How PancakeNotch starts and where you find it.")
        ) {
            SettingsCard(header: String(localized: "Startup"), footer: footer) {
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
                    subtitle: String(localized: "Open this window, turn the notch on or off, or quit.")
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

struct NotchSettingsView: View {
    @Bindable var preferences: Preferences

    var body: some View {
        AppPage(
            title: String(localized: "Notch"),
            subtitle: String(localized: "How the notch reacts to your pointer. Try your changes right here.")
        ) {
            NotchStage(behavior: preferences.notchBehavior)
                .background(Color.black)
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(LinearGradient(
                            colors: [AppPalette.hairlineStrong, AppPalette.hairline],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                }

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
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                SettingsRowLabel(title: title, subtitle: subtitle)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(AppPalette.hover, in: Capsule())
                    .overlay(PillOutline(color: AppPalette.hairline))
                    .accessibilityHidden(true)
            }
            MonochromeSlider(
                value: $value,
                range: range,
                accessibilityLabel: title,
                accessibilityValue: label
            )
        }
        .padding(.bottom, 4)
        .settingsRowPadding()
    }

    private var label: String {
        String(localized: "\(Int(value)) ms")
    }
}

struct KeyboardSettingsView: View {
    let shortcuts: ShortcutController
    @State private var hint: String?

    var body: some View {
        AppPage(
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

            SettingsCard(header: String(localized: "In this window")) {
                SettingsRow(
                    title: String(localized: "Jump to a page"),
                    subtitle: String(localized: "Home, Modules, General, Notch, Keyboard, About, in sidebar order.")
                ) {
                    KeyCombo(keys: ["⌘", "1 – 6"])
                }
                SettingsRow(
                    title: String(localized: "Close the window"),
                    subtitle: String(localized: "PancakeNotch keeps running in the background.")
                ) {
                    KeyCombo(keys: ["⌘", "W"])
                }
            }
        }
    }
}

/// A row of key caps, e.g. ⌘ W.
struct KeyCombo: View {
    let keys: [String]
    var large = false

    var body: some View {
        HStack(spacing: large ? 6 : 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Keycap(label: key, large: large)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(keys.joined(separator: " ")))
    }
}

/// One key, drawn as a small glossy key cap.
struct Keycap: View {
    let label: String
    var large = false

    var body: some View {
        let radius: CGFloat = large ? 9 : 6
        Text(label)
            .font(.system(size: large ? 20 : 12.5, weight: .semibold))
            .foregroundStyle(AppPalette.primaryText)
            .padding(.horizontal, large ? 12 : 7)
            .frame(minWidth: large ? 44 : 24, minHeight: large ? 44 : 24)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
            }
            .shadow(color: .black.opacity(0.6), radius: 0, y: large ? 2 : 1)
    }
}
