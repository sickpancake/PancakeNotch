import AppKit
import SwiftUI

/// The companion app window. It lives in the same process; the Dock icon shows only while it's
/// open, and the window is torn down on close to give its memory back (ADR-0017).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private var window: NSWindow?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "PancakeNotch Settings")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences))
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Release after AppKit finishes closing, so the SwiftUI view tree is freed.
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentView = nil
            self?.window = nil
        }
    }
}

extension SettingsWindowController {
    /// Renders each settings section off-screen to `<directory>/settings-<section>.png` without
    /// showing a window (design checks; `PANCAKENOTCH_SNAPSHOT_SETTINGS=<directory>`).
    static func writeSnapshots(preferences: Preferences, to directory: URL) throws {
        for section in SettingsSection.allCases {
            let view = NSHostingView(rootView: SettingsView(preferences: preferences, section: section)
                .background(Color(nsColor: .windowBackgroundColor)))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("settings-\(section.rawValue).png"))
        }
    }
}
