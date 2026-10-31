import SwiftUI
import TimerCore

/// The Timer on the Modules page: a practice notch with its own timer, what it does with its switch,
/// and its settings while it's on (ADR-0040).
struct TimerModuleCard: View {
    let context: AppContext
    @Binding var showsSettings: Bool
    let learn: () -> Void

    private let points = [
        String(localized: "A timer and a stopwatch with laps, like the ones on your phone"),
        String(localized: "The time left beside the notch, with a ring that drains"),
        String(localized: "A sound and the notch opens when the time is up"),
        String(localized: "Your own quick times, and wheels for any other"),
    ]

    var body: some View {
        ModuleCard(
            context: context,
            moduleID: "timer",
            practice: .timer,
            summary: String(localized: "Time a task without leaving your app: start a timer or the stopwatch from the notch and glance at it beside the notch."),
            points: points,
            inactiveHint: String(localized: "Turn on Timer to try it here."),
            activeHint: String(localized: "A practice timer. Hover the notch and try the 10-second one."),
            learnHint: String(localized: "Opens a hands-on Timer lesson on the Learn page."),
            showsSettings: $showsSettings,
            learn: learn
        ) {
            TimerSettingsRows(settings: context.timerSettings)
        }
    }
}

/// The Timer's settings, as rows with hairlines between them.
struct TimerSettingsRows: View {
    @Bindable var settings: TimerSettings
    @State private var sounds = TimerSound.available()

    var body: some View {
        HairlineRows {
            SettingsRow(
                title: String(localized: "Beside the notch"),
                subtitle: String(localized: "Where a running timer or stopwatch shows. The second spot keeps your first module where it is. A finished timer always shows Done there until you stop it.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "Beside the notch"),
                    options: [
                        (TimerEarPlacement.second, String(localized: "Second spot")),
                        (.ranking, String(localized: "By order")),
                        (.off, String(localized: "Don't show")),
                    ],
                    selection: $settings.earPlacement
                )
            }
            SettingsRow(
                title: String(localized: "What it shows"),
                subtitle: String(localized: "The ring drains as the time runs out. The end time changes only when you start or pause.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "What it shows"),
                    options: [
                        (TimerEarContent.ringAndTime, String(localized: "Ring and time")),
                        (.time, String(localized: "Time")),
                        (.ring, String(localized: "Ring")),
                        (.endTime, String(localized: "End time")),
                    ],
                    selection: $settings.earContent
                )
                .disabled(settings.earPlacement == .off)
            }
            SettingsRow(
                title: String(localized: "Numbers"),
                subtitle: String(localized: "How the digits change. With Reduce Motion on, Roll and Slide fade instead.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "Numbers"),
                    options: [
                        (TimerDigitAnimation.drum, String(localized: "Roll")),
                        (.slide, String(localized: "Slide")),
                        (.off, String(localized: "Just change")),
                    ],
                    selection: $settings.digitAnimation
                )
            }
            SettingsRow(
                title: String(localized: "Timer and Stopwatch side by side"),
                subtitle: String(localized: "Shows both at once in the open notch, instead of a switch between them. The Timer then has room for the first 6 quick times.")
            ) {
                Toggle(String(localized: "Timer and Stopwatch side by side"), isOn: $settings.sideBySide)
                    .labelsHidden()
            }
            SoundRow(settings: settings, sounds: sounds)
            SettingsRow(
                title: String(localized: "Tap the trackpad when a timer ends"),
                subtitle: String(localized: "You feel it if a finger is on the trackpad at that moment.")
            ) {
                Toggle(String(localized: "Tap the trackpad when a timer ends"), isOn: $settings.hapticOnDone)
                    .labelsHidden()
            }
            SettingsRow(
                title: String(localized: "When a timer ends in full screen"),
                subtitle: String(localized: "If the notch is hiding for a full-screen app (Notch settings), it can show itself with Done, then hide again.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "When a timer ends in full screen"),
                    options: [
                        (TimerFullScreenAlert.showNotch, String(localized: "Show the notch")),
                        (.soundOnly, String(localized: "Sound only")),
                    ],
                    selection: $settings.fullScreenAlert
                )
            }
            PresetsRow(settings: settings)
        }
    }
}

/// The sound a timer ends with: macOS's own alert sounds, or none, with a button to hear it.
private struct SoundRow: View {
    @Bindable var settings: TimerSettings
    let sounds: [String]

    var body: some View {
        SettingsRow(
            title: String(localized: "Sound when a timer ends"),
            subtitle: String(localized: "Plays once, at your Mac's alert volume (Sound settings).")
        ) {
            HStack(spacing: 8) {
                Picker(String(localized: "Sound when a timer ends"), selection: $settings.sound) {
                    Text("No sound").tag("")
                    Divider()
                    ForEach(choices, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
                Button {
                    TimerSound.play(settings.sound)
                } label: {
                    Label(String(localized: "Play"), systemImage: "play.fill")
                }
                .disabled(settings.sound.isEmpty)
                .accessibilityLabel(Text("Play the sound"))
            }
        }
    }

    /// The Mac's sounds, plus the saved one if it went missing (so the menu never shows a blank choice).
    private var choices: [String] {
        settings.sound.isEmpty || sounds.contains(settings.sound) ? sounds : sounds + [settings.sound]
    }
}

/// The quick-start times: add one (hours, minutes, seconds, an optional name), rename, reorder, remove,
/// or go back to the defaults.
private struct PresetsRow: View {
    @Bindable var settings: TimerSettings
    @State private var hours = 0
    @State private var minutes = 20
    @State private var seconds = 0
    @State private var name = ""
    @State private var confirmsReset = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var newLength: TimeInterval { TimeInterval(hours * 3600 + minutes * 60 + seconds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                SettingsRowLabel(
                    title: String(localized: "Quick times"),
                    subtitle: String(localized: "The buttons on the Timer page, in this order. Up to \(TimerSettings.mostPresets).")
                )
                Button(confirmsReset ? String(localized: "Click Again to Reset") : String(localized: "Reset to Defaults")) {
                    if confirmsReset {
                        settings.resetPresets()
                        confirmsReset = false
                    } else {
                        confirmsReset = true
                    }
                }
                .disabled(settings.hasDefaultPresets)
                .accessibilityHint(Text("Puts back 5, 10, 15, 30 and 60 minutes. Asks for a second click."))
                .fixedSize()
            }
            VStack(spacing: 6) {
                ForEach(Array(settings.presets.enumerated()), id: \.element.id) { index, preset in
                    PresetEditRow(settings: settings, preset: preset, index: index, count: settings.presets.count)
                }
                if settings.presets.isEmpty {
                    Text("No quick times: the Timer page shows only the wheels.")
                        .font(.app(size: 12.5))
                        .foregroundStyle(AppPalette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                }
            }
            addRow
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: settings.presets)
        .onChange(of: settings.presets) { confirmsReset = false }
        .settingsRowPadding()
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            NumberField(title: String(localized: "Hours"), unit: String(localized: "h"), value: $hours, range: 0...23)
            NumberField(title: String(localized: "Minutes"), unit: String(localized: "min"), value: $minutes, range: 0...59)
            NumberField(title: String(localized: "Seconds"), unit: String(localized: "s"), value: $seconds, range: 0...59)
            TextField(String(localized: "Name (optional)"), text: $name)
                .textFieldStyle(.plain)
                .font(.app(size: 13))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(AppPalette.hover, in: .rect(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppPalette.hairline))
                .onSubmit(add)
                .accessibilityLabel(Text("Name for the new quick time"))
            Button(String(localized: "Add"), action: add)
                .buttonStyle(ProminentPillButtonStyle())
                .disabled(!settings.canAddPreset || newLength < 1)
                .help(Text(!settings.canAddPreset
                    ? String(localized: "You have \(TimerSettings.mostPresets) quick times. Remove one to add another.")
                    : newLength < 1 ? String(localized: "Pick a time first.") : String(localized: "Adds this time at the end.")))
                .accessibilityHint(Text(!settings.canAddPreset
                    ? String(localized: "You have \(TimerSettings.mostPresets) quick times. Remove one to add another.")
                    : String(localized: "Adds this time at the end.")))
        }
    }

    private func add() {
        guard settings.addPreset(seconds: newLength, name: name) else { return }
        name = ""
    }
}

/// One quick time in the list: its length, its name (click Rename to change), arrows and Remove.
private struct PresetEditRow: View {
    let settings: TimerSettings
    let preset: TimerPreset
    let index: Int
    let count: Int
    @State private var draft: String?
    @FocusState private var isTyping: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(TimerText.length(preset.seconds))
                .font(.app(size: 13, weight: .semibold).monospacedDigit())
                .frame(width: 96, alignment: .leading)
            if draft != nil {
                TextField(String(localized: "Name"), text: Binding(get: { draft ?? "" }, set: { draft = $0 }))
                    .textFieldStyle(.plain)
                    .font(.app(size: 13))
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(AppPalette.hover, in: .rect(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(AppPalette.hairlineStrong))
                    .focused($isTyping)
                    .onAppear { isTyping = true }
                    .onSubmit(save)
                    .onExitCommand { draft = nil }
                    .accessibilityLabel(Text("Name for \(TimerText.length(preset.seconds))"))
            } else {
                Text(preset.name.isEmpty ? String(localized: "No name") : preset.name)
                    .font(.app(size: 13))
                    .foregroundStyle(preset.name.isEmpty ? AppPalette.secondaryText : AppPalette.primaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if draft != nil {
                Button(String(localized: "Cancel")) { draft = nil }
                Button(String(localized: "Save"), action: save)
                    .buttonStyle(ProminentPillButtonStyle())
            } else {
                Button(String(localized: "Rename")) { draft = preset.name }
                    .accessibilityLabel(Text("Rename \(TimerText.preset(preset))"))
                arrow(up: true)
                arrow(up: false)
                Button(String(localized: "Remove")) { settings.removePreset(preset.id) }
                    .accessibilityLabel(Text("Remove \(TimerText.preset(preset))"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(AppPalette.hover, in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func arrow(up: Bool) -> some View {
        let isEnabled = up ? index > 0 : index < count - 1
        return Button {
            settings.movePreset(preset.id, to: index + (up ? -1 : 1))
        } label: {
            Image(systemName: up ? "chevron.up" : "chevron.down")
                .font(.app(size: 11, weight: .bold))
        }
        .disabled(!isEnabled)
        .accessibilityLabel(Text(up ? String(localized: "Move \(TimerText.preset(preset)) up") : String(localized: "Move \(TimerText.preset(preset)) down")))
    }

    private func save() {
        guard let draft else { return }
        settings.renamePreset(preset.id, to: draft)
        self.draft = nil
    }
}

/// A small number box with its unit after it ("20 min"), clamped to `range`. Arrow keys step it.
private struct NumberField: View {
    let title: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 4) {
            TextField(title, value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }), format: .number)
                .textFieldStyle(.plain)
                .font(.app(size: 13, weight: .medium).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: 30)
                .padding(.horizontal, 6)
                .frame(height: 30)
                .background(AppPalette.hover, in: .rect(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppPalette.hairline))
                .onKeyPress(.upArrow) { step(1) }
                .onKeyPress(.downArrow) { step(-1) }
                .accessibilityLabel(Text(title))
            Text(unit)
                .font(.app(size: 12.5))
                .foregroundStyle(AppPalette.secondaryText)
                .accessibilityHidden(true)
        }
    }

    private func step(_ amount: Int) -> KeyPress.Result {
        value = min(max(value + amount, range.lowerBound), range.upperBound)
        return .handled
    }
}
