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
        case .keyboard: "keyboard"
        case .about: "info.circle"
        }
    }
}

/// The companion app window: a sidebar of sections and their settings (ADR-0017).
struct SettingsView: View {
    @Bindable var preferences: Preferences
    let shortcuts: ShortcutController
    @State private var section: SettingsSection

    init(preferences: Preferences, shortcuts: ShortcutController, section: SettingsSection = .general) {
        self.preferences = preferences
        self.shortcuts = shortcuts
        _section = State(initialValue: section)
    }

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $section) { section in
                Label {
                    Text(section.title)
                } icon: {
                    Image(systemName: section.symbol)
                        .foregroundStyle(.primary)
                }
                .tag(section)
            }
            .listStyle(.sidebar)
            .tint(.primary)
            .frame(width: 180)

            Divider()

            Group {
                switch section {
                case .general: GeneralSettingsView(preferences: preferences)
                case .notch: NotchSettingsView(preferences: preferences)
                case .keyboard: KeyboardSettingsView(shortcuts: shortcuts)
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tint(.gray)
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var preferences: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var needsApproval = LaunchAtLogin.needsApproval
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
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
                if needsApproval {
                    HStack {
                        Text("Allow PancakeNotch in Login Items to finish turning this on.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { LaunchAtLogin.openSystemSettings() }
                    }
                }
                if let launchError {
                    Text(launchError).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Show menu bar icon", isOn: $preferences.showMenuBarIcon)
            } footer: {
                if !preferences.showMenuBarIcon {
                    Text("To come back here, open PancakeNotch again from your Applications folder.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct NotchSettingsView: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section {
                DelaySlider(
                    title: String(localized: "Open after hovering for"),
                    value: $preferences.openDelayMilliseconds,
                    range: 0...1000
                )
                DelaySlider(
                    title: String(localized: "Close after leaving for"),
                    value: $preferences.closeDelayMilliseconds,
                    range: 100...1500
                )
            } header: {
                Text("Hover")
            }

            Section {
                Toggle("Tap the trackpad when the notch opens", isOn: $preferences.hapticOnOpen)
            } footer: {
                Text("A light click you feel on Force Touch trackpads.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DelaySlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent {
            Slider(value: rounded, in: range)
                .frame(width: 200)
                .accessibilityValue(Text(label))
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(label)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Snaps to 10 ms without drawing tick marks.
    private var rounded: Binding<Double> {
        Binding(get: { value }, set: { value = ($0 / 10).rounded() * 10 })
    }

    private var label: String {
        String(localized: "\(Int(value)) ms")
    }
}

private struct KeyboardSettingsView: View {
    let shortcuts: ShortcutController

    var body: some View {
        Form {
            Section {
                LabeledContent("Open and close the notch") {
                    ShortcutRecorder(controller: shortcuts)
                }
            } footer: {
                Text("Works from any app. Click the box, then press the keys you want.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return String(localized: "Version \(short) (\(build))")
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "capsule.portrait.tophalf.filled")
                .font(.system(size: 40))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            Text("PancakeNotch")
                .font(.title2.weight(.semibold))
            Text(version)
                .foregroundStyle(.secondary)
            Text("Free and open source under the GPL-3.0 license.")
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Link(destination: URL(string: "https://github.com/sickpancake/PancakeNotch")!) {
                Text("View on GitHub").underline()
            }
            .foregroundStyle(.primary)
            .padding(.top, 4)
        }
        .padding(32)
    }
}
