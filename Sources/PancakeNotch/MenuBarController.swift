import AppKit

/// The menu bar icon (hideable in Settings) with Settings… and Quit.
@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
    }

    var isVisible: Bool = false {
        didSet {
            guard isVisible != oldValue else { return }
            isVisible ? install() : remove()
        }
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "capsule.portrait.tophalf.filled",
                accessibilityDescription: String(localized: "PancakeNotch")
            ) ?? NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: String(localized: "PancakeNotch"))
        }
        let menu = NSMenu()
        let settings = NSMenuItem(title: String(localized: "Settings…"), action: #selector(settingsChosen), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: String(localized: "Quit PancakeNotch"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        item.menu = menu
        statusItem = item
    }

    private func remove() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    @objc private func settingsChosen() {
        openSettings()
    }
}
