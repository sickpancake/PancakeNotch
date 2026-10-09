import AppKit
import SwiftUI

/// The companion app window. It lives in the same process; the Dock icon shows only while it's
/// open, and the window is torn down on close to give its memory back (ADR-0017).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private let shortcuts: ShortcutController
    private var window: NSWindow?

    init(preferences: Preferences, shortcuts: ShortcutController) {
        self.preferences = preferences
        self.shortcuts = shortcuts
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = Self.makeWindow(
            rootView: SettingsView(preferences: preferences, shortcuts: shortcuts),
            windowClass: NSWindow.self
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("Settings")
        return window
    }

    /// A window whose sidebar runs up under the traffic lights, with no visible title bar.
    private static func makeWindow(rootView: SettingsView, windowClass: NSWindow.Type) -> NSWindow {
        let size = SettingsView.minimumSize
        let window = windowClass.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "PancakeNotch Settings") // still used by the Window menu and VoiceOver
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentMinSize = size
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = [.minSize]
        window.contentView = hostingView
        window.setContentSize(size)
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
    /// Renders the whole window for each section, in light and dark, off-screen to
    /// `<directory>/settings-<section>-<light|dark>.png` without showing anything (design checks;
    /// `PANCAKENOTCH_SNAPSHOT_SETTINGS=<directory>`).
    static func writeSnapshots(preferences: Preferences, shortcuts: ShortcutController, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let appearances: [(name: String, appearance: NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        for (name, appearance) in appearances {
            for section in SettingsSection.allCases {
                let window = makeWindow(
                    rootView: SettingsView(preferences: preferences, shortcuts: shortcuts, section: section),
                    windowClass: SnapshotWindow.self
                )
                window.appearance = NSAppearance(named: appearance)
                // The frame view also draws the traffic lights, so the image looks like the real window.
                guard let view = window.contentView?.superview ?? window.contentView else { continue }
                view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?
                    .write(to: directory.appendingPathComponent("settings-\(section.rawValue)-\(name).png"))
            }
        }
    }
}

/// Draws as if it were the focused window, so snapshots show controls in their active colours.
private final class SnapshotWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}
