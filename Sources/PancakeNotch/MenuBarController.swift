import AppKit

/// The menu bar icon (hideable in Settings): open the app, turn the notch on or off, quit.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let preferences: Preferences
    private let openApp: () -> Void
    private let notchItem = NSMenuItem(title: "", action: #selector(toggleNotch), keyEquivalent: "")

    init(preferences: Preferences, openApp: @escaping () -> Void) {
        self.preferences = preferences
        self.openApp = openApp
        super.init()
        notchItem.target = self
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
        menu.delegate = self
        let open = NSMenuItem(title: String(localized: "Open PancakeNotch…"), action: #selector(openChosen), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)
        menu.addItem(notchItem)
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        notchItem.title = preferences.notchEnabled
            ? String(localized: "Turn Notch Off")
            : String(localized: "Turn Notch On")
    }

    @objc private func openChosen() {
        openApp()
    }

    @objc private func toggleNotch() {
        preferences.notchEnabled.toggle()
    }
}
