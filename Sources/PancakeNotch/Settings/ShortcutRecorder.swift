import AppKit
import HotKey
import SwiftUI

/// Click, then press a key combination. Esc cancels; Delete clears.
struct ShortcutRecorder: View {
    let controller: ShortcutController
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Button(action: toggleRecording) {
                    Text(title)
                        .monospaced(controller.shortcut != nil && !controller.isRecording)
                        .frame(minWidth: 130)
                }
                .accessibilityLabel(Text("Open and close the notch shortcut"))
                .accessibilityValue(Text(controller.shortcut?.displayString ?? String(localized: "Not set")))

                if controller.shortcut != nil, !controller.isRecording {
                    Button {
                        controller.set(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear shortcut"))
                }
            }
            if let message = hint ?? controller.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var title: String {
        if controller.isRecording { return String(localized: "Type shortcut…") }
        return controller.shortcut?.displayString ?? String(localized: "Record Shortcut")
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
            stopRecording()
        case 51 where modifiers.isEmpty, 117 where modifiers.isEmpty: // Delete, Forward Delete
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
