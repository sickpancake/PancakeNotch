import AppKit
import ModuleShelf
import NotchCore
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var preferences: Preferences
    let updates: Updates
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var needsApproval = LaunchAtLogin.needsApproval
    @State private var launchError: String?

    var body: some View {
        AppPage(
            title: String(localized: "General"),
            subtitle: String(localized: "How PancakeNotch starts, where you find it and how it updates.")
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
            // Approved or turned off in System Settings meanwhile: show what's true now.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                launchAtLogin = LaunchAtLogin.isEnabled
                needsApproval = LaunchAtLogin.needsApproval
            }

            UpdatesCard(updates: updates)
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

/// Sparkle's switch and "Check Now" in released builds; builds made on a Mac say they don't update.
struct UpdatesCard: View {
    @Bindable var updates: Updates
    @Environment(\.openURL) private var openURL

    var body: some View {
        if updates.isAvailable {
            SettingsCard(
                header: String(localized: "Updates"),
                footer: String(localized: "Checking asks GitHub whether there's a newer version. Nothing about you or this Mac is sent.")
            ) {
                SettingsRow(
                    title: String(localized: "Check for updates automatically"),
                    subtitle: String(localized: "Once a day. It asks you before installing anything.")
                ) {
                    Toggle(String(localized: "Check for updates automatically"), isOn: $updates.automaticallyChecks)
                        .labelsHidden()
                }
                if let version = updates.pendingVersion {
                    SettingsRow(
                        title: String(localized: "Version \(version) is ready"),
                        subtitle: String(localized: "See what's new, then choose whether to install it.")
                    ) {
                        Button(String(localized: "Take a Look")) { updates.checkNow() }
                            .buttonStyle(ProminentPillButtonStyle())
                    }
                } else {
                    SettingsRow(
                        title: String(localized: "Check for updates now"),
                        subtitle: UpdatesText.lastCheck(updates.lastCheck, automatic: updates.automaticallyChecks)
                    ) {
                        Button(String(localized: "Check Now")) { updates.checkNow() }
                            .disabled(!updates.canCheck)
                    }
                }
            }
        } else {
            SettingsCard(header: String(localized: "Updates")) {
                SettingsRow(
                    title: String(localized: "This copy can't check for updates"),
                    subtitle: String(localized: "It was built on this Mac. Released versions from the website check for updates and ask before installing.")
                ) {
                    Button { openURL(HelpLinks.website) } label: {
                        Label(String(localized: "Open Website"), systemImage: "arrow.up.right")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                }
            }
        }
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
        if context.agentsSettings.agentsEnabled { kinds.insert(.agents) }
        if context.agentsSettings.usageEnabled { kinds.insert(.aiUsage) }
        if context.timerSettings.isEnabled { kinds.insert(.timer) }
        return kinds
    }

    var body: some View {
        @Bindable var preferences = context.preferences
        @Bindable var arrangement = context.arrangement
        AppPage(
            title: String(localized: "Notch"),
            subtitle: String(localized: "How the notch reacts to your pointer. Try your changes right here.")
        ) {
            NotchStage(behavior: preferences.notchBehavior, arrangement: context.arrangement, practice: practice, badge: .practice)
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
                    range: 0...1000,
                    recommended: Preferences.defaultOpenDelay
                )
                DelayRow(
                    title: String(localized: "Close after leaving for"),
                    subtitle: String(localized: "How long the notch stays open after the pointer leaves."),
                    value: $preferences.closeDelayMilliseconds,
                    range: 100...1500,
                    recommended: Preferences.defaultCloseDelay
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
                HiddenAppsRows()
            }

            SettingsCard(header: String(localized: "Feedback")) {
                SettingsRow(
                    title: String(localized: "Feel a light tap when the notch opens"),
                    subtitle: String(localized: "On Force Touch trackpads, like a soft click under your finger.")
                ) {
                    Toggle(String(localized: "Feel a light tap when the notch opens"), isOn: $preferences.hapticOnOpen)
                        .labelsHidden()
                }
            }
        }
    }
}

/// Apps (games, say) that hide the notch completely while they're full screen, shortcut included
/// (ADR-0030). Picked from the Applications folder.
private struct HiddenAppsRows: View {
    @State private var bundleIDs = NotchSettings.appsHiddenInFullScreen.sorted()

    var body: some View {
        SettingsRow(
            title: String(localized: "Always hide for these apps"),
            subtitle: String(localized: "While one of them is full screen, the notch is fully hidden, even from your shortcut. Handy for games.")
        ) {
            Button(String(localized: "Add App…"), action: addApp)
        }
        ForEach(bundleIDs, id: \.self) { bundleID in
            HiddenAppRow(bundleID: bundleID) { remove(bundleID) }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        panel.message = String(localized: "Choose apps that should hide the notch completely while they're full screen.")
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        save(Set(bundleIDs).union(added))
    }

    private func remove(_ bundleID: String) {
        save(Set(bundleIDs).subtracting([bundleID]))
    }

    private func save(_ apps: Set<String>) {
        NotchSettings.appsHiddenInFullScreen = apps
        bundleIDs = apps.sorted()
    }
}

/// One app on the hide list: its icon and name, and a way to take it off.
private struct HiddenAppRow: View {
    let bundleID: String
    let remove: () -> Void

    private var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    private var name: String {
        guard let appURL else { return bundleID }
        return FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let appURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                        .resizable()
                        .grayscale(1) // Monochrome: album art is the only colour (ADR-0029).
                } else {
                    Image(systemName: "app.dashed")
                        .font(.app(size: 16))
                        .foregroundStyle(AppPalette.secondaryText)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
            Text(name)
                .font(.app(size: 13.5, weight: .medium))
            Spacer(minLength: 8)
            Button(String(localized: "Remove"), action: remove)
                .accessibilityLabel(Text("Remove \(name)"))
        }
        .settingsRowPadding()
    }
}

extension NotchSettingsView {
    /// While it's hidden, the keyboard shortcut is the way in, except over the apps on the hide list.
    private var fullScreenFooter: String? {
        guard preferences.fullScreenHiding != .never else { return nil }
        return context.shortcuts.shortcut == nil
            ? String(localized: "Set a shortcut on the Keyboard page to open the notch while it's hidden.")
            : String(localized: "Your keyboard shortcut still opens the notch while it's hidden, except while one of the apps above is full screen.")
    }
}

private func fullScreenHint(_ hiding: FullScreenHiding) -> String {
    switch hiding {
    case .whileWatching:
        String(localized: "Hidden while a full-screen video plays and you're not moving the pointer. Move it and the notch is back.")
    case .always:
        String(localized: "Hidden whenever an app fills the screen, like a video or a game.")
    case .never:
        String(localized: "Works as usual in full-screen apps.")
    }
}

private func navigationHint(_ navigation: NotchNavigation) -> String {
    switch navigation {
    case .tabsAndMenu:
        String(localized: "A Module Menu button, then a tab for each favorite.")
    case .tabs:
        String(localized: "A tab for every module, one click apart.")
    case .menu:
        String(localized: "Just the module's name: click it for the Module Menu. The simplest look.")
    }
}

private struct DelayRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// The default; a way back to it shows once the value moves away.
    let recommended: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                SettingsRowLabel(title: title, subtitle: subtitle)
                HStack(spacing: 8) {
                    if value != recommended {
                        Button(String(localized: "Reset")) {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { value = recommended }
                        }
                        .buttonStyle(.plain)
                        .font(.app(size: 12.5, weight: .medium))
                        .foregroundStyle(AppPalette.secondaryText)
                        .help(Text("Back to the recommended \(Int(recommended)) ms"))
                        .accessibilityLabel(Text("Reset \(title)"))
                        .accessibilityHint(Text("Goes back to the recommended \(Int(recommended)) milliseconds."))
                        .transition(.opacity)
                    }
                    valuePill
                }
                .animation(.easeInOut(duration: 0.15), value: value == recommended)
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

    private var valuePill: some View {
        Text(label)
            .font(.app(size: 13, weight: .semibold))
            .monospacedDigit()
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(AppPalette.hover, in: Capsule())
            .overlay(PillOutline(color: AppPalette.hairline))
            .accessibilityHidden(true)
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
                footer: String(localized: "Click the button on the right, then press the keys you want. Esc cancels, Delete clears.")
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
                    subtitle: String(localized: "Home, Modules, Learn, Statistics, General, Notch, Keyboard, Help, About, in sidebar order.")
                ) {
                    KeyCombo(keys: ["⌘", "1 – \(AppSection.allCases.count)"])
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
