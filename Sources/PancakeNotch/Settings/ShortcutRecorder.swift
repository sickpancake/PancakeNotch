import AppKit
import HotKey
import SwiftUI

/// Click, then press a key combination. Esc cancels; Delete clears.
struct ShortcutRecorder: View {
    let controller: ShortcutController
    /// Set while recording when a key press can't be a shortcut, to explain why.
    @Binding var hint: String?
    @State private var monitor: Any?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                field
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityLabel(Text("Open and close the notch shortcut"))
            .accessibilityValue(Text(accessibilityValue))
            .accessibilityHint(Text(controller.isRecording ? "Press the keys you want, or Esc to cancel." : "Records a new shortcut."))

            if controller.shortcut != nil, !controller.isRecording {
                Button {
                    controller.set(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(Text("Clear shortcut"))
                .accessibilityLabel(Text("Clear shortcut"))
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var field: some View {
        HStack(spacing: 4) {
            if controller.isRecording {
                RecordingDot()
                Text("Type shortcut…")
                    .foregroundStyle(.secondary)
            } else if let shortcut = controller.shortcut {
                ForEach(Array(keys(of: shortcut).enumerated()), id: \.offset) { _, key in
                    Keycap(label: key)
                }
            } else {
                Text("Record Shortcut")
                    .font(.body.weight(.medium))
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 140, minHeight: 32)
        .background(isHovered && !controller.isRecording ? SettingsPalette.hover : SettingsPalette.windowBackground, in: .rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(controller.isRecording ? SettingsPalette.ink : SettingsPalette.hairline,
                              lineWidth: controller.isRecording ? 1.5 : 1)
        }
        .contentShape(.rect(cornerRadius: 9))
    }

    private var accessibilityValue: String {
        if controller.isRecording { return String(localized: "Recording") }
        return controller.shortcut?.displayString ?? String(localized: "Not set")
    }

    /// "⌥⌘N" as separate keys: ["⌥", "⌘", "N"].
    private func keys(of shortcut: HotKey) -> [String] {
        let flags = shortcut.modifierFlags
        var keys: [String] = []
        if flags.contains(.control) { keys.append("⌃") }
        if flags.contains(.option) { keys.append("⌥") }
        if flags.contains(.shift) { keys.append("⇧") }
        if flags.contains(.command) { keys.append("⌘") }
        return keys + [shortcut.keyLabel]
    }

    private func toggleRecording() {
        controller.isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        hint = nil
        controller.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        controller.isRecording = false
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        switch Int(event.keyCode) {
        case 53 where modifiers.isEmpty: // Esc
            hint = nil
            stopRecording()
        case 51 where modifiers.isEmpty, 117 where modifiers.isEmpty: // Delete, Forward Delete
            hint = nil
            stopRecording()
            controller.set(nil)
        default:
            guard let hotKey = HotKey(event: event) else {
                hint = String(localized: "Include ⌘, ⌥ or ⌃ (or use a function key).")
                return
            }
            hint = nil
            stopRecording()
            controller.set(hotKey)
        }
    }
}

/// One key of a shortcut, drawn as a small key cap.
private struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(SettingsPalette.cardBackground, in: .rect(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(SettingsPalette.hairline)
            }
            .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
    }
}

/// A dot that gently pulses while recording; it stays still with Reduce Motion.
private struct RecordingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    var body: some View {
        Circle()
            .fill(SettingsPalette.ink)
            .frame(width: 7, height: 7)
            .opacity(isDimmed ? 0.25 : 1)
            .padding(.trailing, 2)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isDimmed = true
                }
            }
            .accessibilityHidden(true)
    }
}
