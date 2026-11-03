import KeepAwakeCore
import SwiftUI

/// Keep Awake on the Modules page: a practice notch that holds nothing, what it does with its switch, and its
/// settings while it's on (ADR-0041).
struct KeepAwakeModuleCard: View {
    let context: AppContext
    @Binding var showsSettings: Bool
    let learn: () -> Void

    private let points = [
        String(localized: "Keeps your Mac awake for 30 minutes to 4 hours, or until you stop it"),
        String(localized: "Turns on by itself while an AI agent works or a file converts"),
        String(localized: "A coffee cup beside the notch while it's on, and in the menu bar"),
        String(localized: "Stops by itself when the battery runs low"),
    ]

    var body: some View {
        ModuleCard(
            context: context,
            moduleID: "keepAwake",
            practice: .keepAwake,
            summary: String(localized: "Stop your Mac falling asleep while something runs: a long download, a video call, or agents at work. Closing a MacBook's lid still puts it to sleep."),
            points: points,
            inactiveHint: String(localized: "Turn on Keep Awake to try it here."),
            activeHint: String(localized: "A practice copy: it doesn't keep your Mac awake. Hover the notch and turn it on."),
            learnHint: String(localized: "Opens a hands-on Keep Awake lesson on the Learn page."),
            showsSettings: $showsSettings,
            learn: learn
        ) {
            KeepAwakeSettingsRows(context: context, settings: context.keepAwakeSettings)
        }
    }
}

/// Keep Awake's settings, as rows with hairlines between them.
struct KeepAwakeSettingsRows: View {
    let context: AppContext
    @Bindable var settings: KeepAwakeSettings

    var body: some View {
        HairlineRows {
            SettingsRow(
                title: String(localized: "Screen"),
                subtitle: String(localized: "Stays on: you can watch what's running, but the screen won't lock by itself (press Control-Command-Q to lock it when you walk away). Can sleep: the screen dims, sleeps and locks as usual while your Mac keeps working.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "Screen"),
                    options: [
                        (KeepAwakeScreen.staysOn, String(localized: "Stays on")),
                        (.canTurnOff, String(localized: "Can sleep")),
                    ],
                    selection: $settings.screen
                )
            }
            SettingsRow(
                title: String(localized: "While AI agents work"),
                subtitle: agentsSubtitle
            ) {
                HStack(spacing: 10) {
                    if !context.agentsSettings.agentsEnabled {
                        Button(String(localized: "Turn On Agents")) { context.agentsSettings.agentsEnabled = true }
                            .buttonStyle(PillButtonStyle())
                    }
                    Toggle(String(localized: "While AI agents work"), isOn: $settings.whileAgentsWork)
                        .labelsHidden()
                }
            }
            SettingsRow(
                title: String(localized: "While a file converts"),
                subtitle: convertSubtitle
            ) {
                HStack(spacing: 10) {
                    if !context.shelfSettings.isEnabled || !context.shelfSettings.convertEnabled {
                        Button(String(localized: "Turn On Convert")) {
                            context.shelfSettings.isEnabled = true
                            context.shelfSettings.convertEnabled = true
                        }
                        .buttonStyle(PillButtonStyle())
                    }
                    Toggle(String(localized: "While a file converts"), isOn: $settings.whileConverting)
                        .labelsHidden()
                }
            }
            SettingsRow(
                title: String(localized: "Stop when the battery is low"),
                subtitle: String(localized: "On battery, Keep Awake stops at this level and shows a strip under the notch. It can't start again on battery until you plug in.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "Stop when the battery is low"),
                    options: KeepAwakeSettings.cutoffChoices.map { (Optional($0), "\($0)%") } + [(nil, String(localized: "Never"))],
                    selection: $settings.batteryCutoff
                )
            }
            SettingsRow(
                title: String(localized: "When PancakeNotch opens again"),
                subtitle: String(localized: "What happens to a Keep Awake you turned on, after an update or if you quit the app. Carry on doesn't carry it over a restart of your Mac, so it's never left on from yesterday.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "When PancakeNotch opens again"),
                    options: [
                        (KeepAwakeReopen.carryOn, String(localized: "Carry on")),
                        (.carryOnAfterRestart, String(localized: "Even after a restart")),
                        (.startOff, String(localized: "Start off")),
                    ],
                    selection: $settings.reopen
                )
            }
        }
    }

    private var agentsSubtitle: String {
        let base = String(localized: "While an AI agent (like Claude Code or Codex) works or waits for you, and for 2 minutes after.")
        return context.agentsSettings.agentsEnabled ? base : base + " " + String(localized: "Needs the Agents module, which is off.")
    }

    private var convertSubtitle: String {
        let base = String(localized: "While the Shelf converts a file, and for 2 minutes after.")
        return context.shelfSettings.isEnabled && context.shelfSettings.convertEnabled
            ? base : base + " " + String(localized: "Needs the Shelf's Convert, which is off.")
    }
}
