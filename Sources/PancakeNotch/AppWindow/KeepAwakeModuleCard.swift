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
                title: String(localized: "Low battery level"),
                subtitle: String(localized: "On battery, at or below this level Keep Awake stops or keeps going, as you choose below. Never: it doesn't look at the battery.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "Low battery level"),
                    options: KeepAwakeSettings.cutoffChoices.map { (Optional($0), "\($0)%") } + [(nil, String(localized: "Never"))],
                    selection: $settings.batteryCutoff
                )
            }
            // Only while a level is set: with Never there's nothing to choose.
            if let cutoff = settings.batteryCutoff {
                SettingsRow(
                    title: String(localized: "At the low battery level"),
                    subtitle: settings.lowBattery == .stop
                        ? String(localized: "At \(cutoff)% Keep Awake stops, with a strip under the notch, so it can't run your battery flat. It can't start again on battery until you plug in.")
                        : String(localized: "At \(cutoff)% Keep Awake keeps going and tells you once with a strip under the notch. macOS still puts your Mac to sleep when the battery is nearly empty.")
                ) {
                    MonochromeSegmented(
                        title: String(localized: "At the low battery level"),
                        options: [
                            (KeepAwakeLowBattery.stop, String(localized: "Stop")),
                            (.keepGoing, String(localized: "Keep going")),
                        ],
                        selection: $settings.lowBattery
                    )
                }
                if settings.lowBattery == .stop {
                    SettingsRow(
                        title: String(localized: "When you plug in"),
                        subtitle: settings.plugIn == .turnBackOn
                            ? String(localized: "After the battery stopped it, Keep Awake comes back on when you plug in: the rest of your session and automatic keep-awake. A strip under the notch tells you.")
                            : String(localized: "After the battery stopped it, Keep Awake stays off when you plug in, until you turn it on or the agent or conversion that runs now ends.")
                    ) {
                        MonochromeSegmented(
                            title: String(localized: "When you plug in"),
                            options: [
                                (KeepAwakePlugIn.turnBackOn, String(localized: "Turn back on")),
                                (.stayOff, String(localized: "Stay off")),
                            ],
                            selection: $settings.plugIn
                        )
                    }
                }
            }
            SettingsRow(
                title: String(localized: "If PancakeNotch quits"),
                subtitle: String(localized: "Whether a Keep Awake you turned on comes back when PancakeNotch opens again, after an update or if you quit it. Turn back on skips a restart of your Mac, so it's never left on from yesterday.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "If PancakeNotch quits"),
                    options: [
                        (KeepAwakeReopen.carryOn, String(localized: "Turn back on")),
                        (.carryOnAfterRestart, String(localized: "Even after a restart")),
                        (.startOff, String(localized: "Stay off")),
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
