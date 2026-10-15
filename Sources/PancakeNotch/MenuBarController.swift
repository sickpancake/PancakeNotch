import AppKit

/// The menu bar icon (hideable in Settings): open the app, turn the notch on or off, check for
/// updates, quit. A waiting update puts a small dot on the icon.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let preferences: Preferences
    private let updates: Updates
    private let openApp: () -> Void
    private let notchItem = NSMenuItem(title: "", action: #selector(toggleNotch), keyEquivalent: "")
    private let updatesItem = NSMenuItem(title: "", action: #selector(checkForUpdates), keyEquivalent: "")

    init(preferences: Preferences, updates: Updates, openApp: @escaping () -> Void) {
        self.preferences = preferences
        self.updates = updates
        self.openApp = openApp
        super.init()
        notchItem.target = self
        updatesItem.target = self
    }

    var isVisible: Bool = false {
        didSet {
            guard isVisible != oldValue else { return }
            isVisible ? install() : remove()
        }
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.setAccessibilityLabel(String(localized: "PancakeNotch"))
        item.button?.toolTip = String(localized: "PancakeNotch")
        let menu = NSMenu()
        menu.delegate = self
        let open = NSMenuItem(title: String(localized: "Open PancakeNotch"), action: #selector(openChosen), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(notchItem)
        if updates.isAvailable {
            menu.addItem(.separator())
            menu.addItem(updatesItem)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: String(localized: "Quit PancakeNotch"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        item.menu = menu
        statusItem = item
        updatePending()
    }

    private func remove() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    /// The dot on the icon while an update waits to be looked at.
    func updatePending() {
        guard let button = statusItem?.button else { return }
        let pending = updates.pendingVersion != nil
        button.image = LogoGlyph.templateImage(dot: pending)
        button.setAccessibilityValue(pending ? String(localized: "Update available") : nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        notchItem.title = preferences.notchEnabled
            ? String(localized: "Turn Notch Off")
            : String(localized: "Turn Notch On")
        if let version = updates.pendingVersion {
            updatesItem.title = String(localized: "Update to \(version)…")
        } else {
            updatesItem.title = String(localized: "Check for Updates…")
        }
        updatesItem.isEnabled = updates.pendingVersion != nil || updates.canCheck
    }

    @objc private func openChosen() {
        openApp()
    }

    @objc private func toggleNotch() {
        preferences.notchEnabled.toggle()
    }

    @objc private func checkForUpdates() {
        updates.checkNow()
    }
}
