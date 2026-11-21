import AppKit
import KeepAwakeCore

/// The menu bar icon (hideable in Settings): open the app, turn the notch on or off, Keep Awake, check for
/// updates, quit. A waiting update puts a small dot on the icon; a small cup shows while Keep Awake keeps
/// the Mac awake (ADR-0041).
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let preferences: Preferences
    private let updates: Updates
    private let keepAwake: KeepAwakeCenter
    private let openApp: () -> Void
    private let notchItem = NSMenuItem(title: "", action: #selector(toggleNotch), keyEquivalent: "")
    private let updatesItem = NSMenuItem(title: "", action: #selector(checkForUpdates), keyEquivalent: "")
    /// Keep Awake and its submenu, shown while the module is switched on.
    private let keepAwakeItem = NSMenuItem(title: String(localized: "Keep Awake"), action: nil, keyEquivalent: "")
    private let keepAwakeMenu = NSMenu()

    init(preferences: Preferences, updates: Updates, keepAwake: KeepAwakeCenter, openApp: @escaping () -> Void) {
        self.preferences = preferences
        self.updates = updates
        self.keepAwake = keepAwake
        self.openApp = openApp
        super.init()
        notchItem.target = self
        updatesItem.target = self
        keepAwakeMenu.delegate = self
        // Each item says itself whether it can be used now (a low battery greys out the lengths).
        keepAwakeMenu.autoenablesItems = false
        keepAwakeItem.submenu = keepAwakeMenu
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
        menu.addItem(keepAwakeItem)
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
        updateIcon()
    }

    private func remove() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    /// The dot on the icon while an update waits to be looked at, the cup while Keep Awake keeps the Mac awake.
    func updateIcon() {
        guard let button = statusItem?.button else { return }
        let pending = updates.pendingVersion != nil
        let awake = keepAwake.isHolding
        button.image = LogoGlyph.templateImage(dot: pending, cup: awake)
        let values = [pending ? String(localized: "Update available") : nil, awake ? String(localized: "Keeping your Mac awake") : nil]
            .compactMap { $0 }
        button.setAccessibilityValue(values.isEmpty ? nil : values.joined(separator: ", "))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === keepAwakeMenu { return fillKeepAwakeMenu() }
        keepAwakeItem.isHidden = !keepAwake.settings.isEnabled
        keepAwakeItem.state = keepAwake.isHolding ? .on : .off
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

    // MARK: Keep Awake

    /// What it's doing, the lengths (each starts a session that long), +30 min and Turn Off. Built each time
    /// it opens, so every item works for the state shown.
    private func fillKeepAwakeMenu() {
        keepAwakeMenu.removeAllItems()
        let status = KeepAwakeStatus(keepAwake)
        var words = status.title + " · " + status.detail
        if status.kind == .holding, let left = keepAwake.remaining(at: keepAwake.now) { words += " · " + KeepAwakeText.left(left) }
        let line = NSMenuItem(title: words, action: nil, keyEquivalent: "")
        line.isEnabled = false
        keepAwakeMenu.addItem(line)
        keepAwakeMenu.addItem(.separator())
        for (index, length) in KeepAwakeLength.choices.enumerated() {
            let item = NSMenuItem(title: KeepAwakeText.menuLength(length), action: #selector(keepAwakeFor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.isEnabled = keepAwake.canTurnOn
            // The length a plain Turn On uses.
            item.state = length == keepAwake.settings.lastLength ? .on : .off
            keepAwakeMenu.addItem(item)
        }
        // Also while it comes back when you plug in: Turn Off keeps it off.
        let comesBack = keepAwake.stoppedForBattery && keepAwake.settings.plugIn == .turnBackOn
        if keepAwake.isHolding || comesBack {
            keepAwakeMenu.addItem(.separator())
            if keepAwake.session?.end != nil {
                let more = NSMenuItem(title: String(localized: "Add 30 Minutes"), action: #selector(extendKeepAwake), keyEquivalent: "")
                more.target = self
                more.isEnabled = keepAwake.canExtend
                keepAwakeMenu.addItem(more)
            }
            let off = NSMenuItem(title: String(localized: "Turn Off"), action: #selector(turnOffKeepAwake), keyEquivalent: "")
            off.target = self
            keepAwakeMenu.addItem(off)
        }
    }

    @objc private func keepAwakeFor(_ sender: NSMenuItem) {
        guard KeepAwakeLength.choices.indices.contains(sender.tag) else { return }
        keepAwake.turnOn(KeepAwakeLength.choices[sender.tag])
    }

    @objc private func extendKeepAwake() {
        keepAwake.extend()
    }

    @objc private func turnOffKeepAwake() {
        keepAwake.turnOff()
    }
}
