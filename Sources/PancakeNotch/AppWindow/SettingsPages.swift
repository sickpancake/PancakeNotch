import ModuleShelf
import NotchCore
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
                launchError = LaunchAtLogin.apply(enabled)
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
    let context: AppContext
    /// Goes to the Modules page (order and favorites live there).
    let openModules: () -> Void

    private var preferences: Preferences { context.preferences }

    /// The practice modules matching the user's switches, so the stage shows their notch.
    private var practice: Set<PracticeKind> {
        var kinds: Set<PracticeKind> = []
        if context.nowPlayingSettings.isEnabled { kinds.insert(.nowPlaying) }
        if context.shelfSettings.isEnabled { kinds.insert(.shelf) }
        return kinds
    }

    var body: some View {
        @Bindable var preferences = context.preferences
        @Bindable var arrangement = context.arrangement
        AppPage(
            title: String(localized: "Notch"),
            subtitle: String(localized: "How the notch reacts to your pointer. Try your changes right here.")
        ) {
            NotchStage(behavior: preferences.notchBehavior, arrangement: context.arrangement, practice: practice)
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

            SettingsCard(
                header: String(localized: "Moving between modules"),
                footer: String(localized: "A two-finger swipe sideways on the open notch also moves to the next module.")
            ) {
                SettingsRow(
                    title: String(localized: "In the open notch, show"),
                    subtitle: navigationHint(arrangement.navigation)
                ) {
                    MonochromeSegmented(
                        title: String(localized: "In the open notch, show"),
                        options: [
                            (.tabsAndMenu, String(localized: "Menu and tabs")),
                            (.tabs, String(localized: "Tabs")),
                            (.menu, String(localized: "Menu")),
                        ],
                        selection: $arrangement.navigation
                    )
                }
                SettingsRow(
                    title: String(localized: "Order and favorites"),
                    subtitle: String(localized: "Which modules come first, which are tabs, and which are on.")
                ) {
                    Button(String(localized: "Open Modules"), action: openModules)
                }
            }

            SettingsCard(header: String(localized: "Full screen"), footer: fullScreenFooter) {
                SettingsRow(
                    title: String(localized: "Hide the notch in full screen"),
                    subtitle: fullScreenHint(preferences.fullScreenHiding)
                ) {
                    MonochromeSegmented(
                        title: String(localized: "Hide the notch in full screen"),
                        options: [
                            (.whileWatching, String(localized: "While watching")),
                            (.always, String(localized: "Always")),
                            (.never, String(localized: "Never")),
                        ],
                        selection: $preferences.fullScreenHiding
                    )
                }
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

extension NotchSettingsView {
    /// While it's hidden, the keyboard shortcut is the way in.
    private var fullScreenFooter: String? {
        guard preferences.fullScreenHiding != .never else { return nil }
        return context.shortcuts.shortcut == nil
            ? String(localized: "Set a shortcut on the Keyboard page to open the notch while it's hidden.")
            : String(localized: "Your keyboard shortcut still opens the notch while it's hidden.")
    }
}

private func fullScreenHint(_ hiding: FullScreenHiding) -> String {
    switch hiding {
    case .whileWatching:
        String(localized: "Hidden while the full-screen app plays and you sit still. Scroll or move the pointer and it's back.")
    case .always:
        String(localized: "Hidden whenever an app fills the screen, like a video or a game.")
    case .never:
        String(localized: "Works as usual in full-screen apps.")
    }
}

private func navigationHint(_ navigation: NotchNavigation) -> String {
    switch navigation {
    case .tabsAndMenu:
        String(localized: "A Menu button with every module, then a tab for each favorite.")
    case .tabs:
        String(localized: "A tab for every module, one click apart.")
    case .menu:
        String(localized: "Just the module's name: click it for the Menu. The tidiest.")
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
                    .font(.app(size: 13, weight: .semibold))
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
            subtitle: String(localized: "Your shortcut for the notch, and the keys in the Shelf and this window.")
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

            SettingsCard(
                header: String(localized: "In the Shelf"),
                footer: String(localized: "These work after you click inside the open notch.")
            ) {
                SettingsRow(
                    title: String(localized: "Open the selected item"),
                    subtitle: String(localized: "A big preview, or an editor for notes and links. Space works too.")
                ) {
                    KeyCombo(keys: [String(localized: "Return", comment: "Key name, as printed on the keyboard")])
                }
                SettingsRow(
                    title: String(localized: "Move the selection"),
                    subtitle: String(localized: "Hold Shift to select more than one.")
                ) {
                    KeyCombo(keys: ["←", "→"])
                }
                SettingsRow(
                    title: String(localized: "Select everything"),
                    subtitle: String(localized: "Then drag them out together, or remove them.")
                ) {
                    KeyCombo(keys: ["⌘", "A"])
                }
                SettingsRow(
                    title: String(localized: "Remove from the Shelf"),
                    subtitle: String(localized: "The files themselves stay where they are.")
                ) {
                    KeyCombo(keys: [String(localized: "Delete", comment: "Key name, as printed on the keyboard")])
                }
                SettingsRow(
                    title: String(localized: "Go back, then close"),
                    subtitle: String(localized: "Leaves an open item, then closes the notch.")
                ) {
                    KeyCombo(keys: [String(localized: "Esc", comment: "Key name, as printed on the keyboard")])
                }
            }

            SettingsCard(header: String(localized: "In this window")) {
                SettingsRow(
                    title: String(localized: "Jump to a page"),
                    subtitle: String(localized: "Home, Modules, Learn, Statistics, General, Notch, Keyboard, About, in sidebar order.")
                ) {
                    KeyCombo(keys: ["⌘", "1 – 8"])
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
            .font(.app(size: large ? 20 : 12.5, weight: .semibold))
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
