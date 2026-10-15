import AppKit
import HotKey
import SwiftUI

/// Click, then press a key combination. Esc cancels; Delete clears.
struct ShortcutRecorder: View {
    let controller: ShortcutController
    /// Set while recording when a key press can't be a shortcut, to explain why.
    @Binding var hint: String?
    @State private var monitor: Any?
    @State private var clickMonitor: Any?
    /// When a click stopped recording: a click on the box itself then mustn't start it again.
    @State private var stoppedByClick: Date?
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
            .accessibilityHint(Text(controller.isRecording
                ? String(localized: "Press the keys you want, or Esc to cancel.")
                : String(localized: "Records a new shortcut.")))

            if controller.shortcut != nil, !controller.isRecording {
                Button {
                    controller.set(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.app(size: 13))
                        .foregroundStyle(AppPalette.secondaryText)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(Text("Clear shortcut"))
                .accessibilityLabel(Text("Clear shortcut"))
            }
        }
        .onDisappear(perform: stopRecording)
        // Leaving the window (another app, another window) stops listening too.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if controller.isRecording { stopRecording() }
        }
    }

    private var field: some View {
        HStack(spacing: 4) {
            if controller.isRecording {
                RecordingDot()
                Text("Type shortcut…")
                    .font(.app(size: 13, weight: .medium))
                    .foregroundStyle(AppPalette.secondaryText)
            } else if let shortcut = controller.shortcut {
                ForEach(Array(shortcut.keyCaps.enumerated()), id: \.offset) { _, key in
                    Keycap(label: key)
                }
            } else {
                Text("Record Shortcut")
                    .font(.app(size: 13, weight: .semibold))
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 150, minHeight: 36)
        .background(isHovered && !controller.isRecording ? AppPalette.selection : AppPalette.hover,
                    in: .rect(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(controller.isRecording ? AppPalette.ink : AppPalette.hairlineStrong,
                              lineWidth: controller.isRecording ? 1.5 : 1)
        }
        .contentShape(.rect(cornerRadius: 10))
    }

    private var accessibilityValue: String {
        if controller.isRecording { return String(localized: "Recording") }
        return controller.shortcut?.displayString ?? String(localized: "Not set")
    }

    private func toggleRecording() {
        if controller.isRecording {
            stopRecording()
        } else if let stoppedByClick, Date().timeIntervalSince(stoppedByClick) < 0.6 {
            // This click already stopped recording on its way down.
            self.stoppedByClick = nil
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        hint = nil
        stoppedByClick = nil
        controller.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
        // Clicking anywhere else stops listening, so a later key press can't become the shortcut.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            MainActor.assumeIsolated {
                hint = nil
                stopRecording()
                stoppedByClick = Date()
            }
            return event
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        monitor = nil
        clickMonitor = nil
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
            guard !hotKey.isReservedBySystem else {
                hint = String(localized: "\(hotKey.displayString) is a system shortcut. Try another, like ⌥⌘N.")
                return
            }
            hint = nil
            stopRecording()
            controller.set(hotKey)
        }
    }
}

/// A dot that gently pulses while recording; it stays still with Reduce Motion.
private struct RecordingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    var body: some View {
        Circle()
            .fill(AppPalette.ink)
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

extension HotKey {
    /// "⌥⌘N" as separate keys: ["⌥", "⌘", "N"].
    var keyCaps: [String] {
        let flags = modifierFlags
        var keys: [String] = []
        if flags.contains(.control) { keys.append("⌃") }
        if flags.contains(.option) { keys.append("⌥") }
        if flags.contains(.shift) { keys.append("⇧") }
        if flags.contains(.command) { keys.append("⌘") }
        return keys + [keyLabel]
    }
}
