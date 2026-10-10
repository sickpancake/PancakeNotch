import AppKit
import ModuleShelf
import NotchCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "app")

    /// Set `PANCAKENOTCH_SIMULATE_NOTCH=1` to fake a notch on screens without one (CI, external displays).
    private let simulateNotch = ProcessInfo.processInfo.environment["PANCAKENOTCH_SIMULATE_NOTCH"] == "1"

    /// Set `PANCAKENOTCH_DEBUG_STATE=compact|expanded` to pin the notch in that state (screenshots, design work).
    private let notchController = NotchWindowController(
        initialState: ProcessInfo.processInfo.environment["PANCAKENOTCH_DEBUG_STATE"].flatMap(NotchState.init(rawValue:))
    )

    private let preferences = Preferences()
    private let stats = UsageStats()
    private let shelfSettings = ShelfSettings()
    /// Loads only the saved item list; files are checked when the notch opens.
    private lazy var shelfStore = ShelfStore()
    /// Exists only while the Shelf is switched on.
    private var shelf: ShelfModule?
    private lazy var shortcuts = ShortcutController { [weak self] in self?.notchController.toggle() }
    private lazy var appWindow = AppWindowController(
        preferences: preferences,
        shortcuts: shortcuts,
        stats: stats,
        shelfSettings: shelfSettings,
        shelfStore: shelfStore
    )
    private lazy var menuBar = MenuBarController(
        preferences: preferences,
        openApp: { [weak self] in self?.showAppWindow() }
    )

    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var appObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = ProcessInfo.processInfo.environment["PANCAKENOTCH_SNAPSHOT"] {
            writeSnapshot(to: path)
            return
        }
        if let path = ProcessInfo.processInfo.environment["PANCAKENOTCH_SNAPSHOT_SETTINGS"] {
            try? AppWindowController.writeSnapshots(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
            return
        }
        NSApp.mainMenu = MainMenu.make(settingsTarget: self, settingsAction: #selector(showAppWindow))
        notchController.onOpen = { [weak self] in self?.stats.recordOpen() }
        observePreferences()
        seedShelfIfRequested()
        observeShelf()
        _ = shortcuts // registers the saved shortcut
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateGeometry() }
        }
        // Entering or leaving a full-screen app switches Spaces.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFullScreen() }
        }
        // Switching apps can bring a listed app to the front within the same Space.
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFullScreen() }
        }
        updateGeometry()
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows the app window — the way back
    /// when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showAppWindow()
        return false
    }

    @objc private func showAppWindow() {
        appWindow.show()
    }

    /// Applies preferences now and again whenever one changes (no polling).
    private func observePreferences() {
        withObservationTracking {
            notchController.isEnabled = preferences.notchEnabled
            notchController.behavior = preferences.notchBehavior
            menuBar.isVisible = preferences.showMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor in self?.observePreferences() }
        }
    }

    /// `PANCAKENOTCH_SHELF_SEED=/folder` fills an empty Shelf with that folder's files (memory checks;
    /// pair it with `PANCAKENOTCH_SHELF_DIR` so the real Shelf isn't touched).
    private func seedShelfIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["PANCAKENOTCH_SHELF_SEED"], shelfStore.items.isEmpty,
              let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)
        else { return }
        let inputs = files.sorted { $0.path < $1.path }.map { ShelfInput.file($0, owned: false) }
        shelfStore.add(inputs, duplicates: .addAgain)
    }

    /// Creates the Shelf when it's switched on and drops it when it's off (no drops are accepted then).
    private func observeShelf() {
        withObservationTracking {
            if shelfSettings.isEnabled {
                if shelf == nil { shelf = ShelfModule(store: shelfStore, settings: shelfSettings) }
            } else {
                shelf = nil
            }
            notchController.module = shelf
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeShelf() }
        }
    }

    /// Full-screen apps keep the notch working, except apps on the user's hide list (ADR-0030).
    private func updateFullScreen() {
        let hiddenApps = NotchSettings.appsHiddenInFullScreen
        var suppress = false
        if !hiddenApps.isEmpty,
           let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           hiddenApps.contains(frontmost),
           let screen = NSScreen.builtIn {
            suppress = FullScreenDetector.isFullScreen(displayID: screen.displayID)
        }
        if suppress != notchController.isSuppressed {
            logger.info("Notch \(suppress ? "hidden for full-screen app" : "shown", privacy: .public)")
        }
        notchController.isSuppressed = suppress
    }

    private func updateGeometry() {
        let geometry = currentGeometry()
        if let geometry {
            logger.info("Notch at \(String(describing: geometry.notchRect), privacy: .public) simulated=\(geometry.isSimulated)")
        } else {
            logger.info("No notch available; idling")
        }
        notchController.update(geometry: geometry)
        updateFullScreen()
    }

    /// Renders all notch states to a PNG and quits. See `NotchSnapshot`.
    private func writeSnapshot(to path: String) {
        let geometry = currentGeometry() ?? .simulated(in: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982))
        do {
            try NotchSnapshot.write(geometry: geometry, to: URL(fileURLWithPath: path)) { layout in
                ShelfSnapshot.models(layout: layout)
            }
        } catch {
            logger.error("Snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
        NSApp.terminate(nil)
    }

    private func currentGeometry() -> NotchGeometry? {
        if let geometry = NSScreen.builtIn?.notchGeometry { return geometry }
        if simulateNotch, let screen = NSScreen.main { return .simulated(in: screen.frame) }
        return nil
    }
}
