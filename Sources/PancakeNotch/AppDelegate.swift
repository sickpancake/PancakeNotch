import AppKit
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

    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var appObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = ProcessInfo.processInfo.environment["PANCAKENOTCH_SNAPSHOT"] {
            writeSnapshot(to: path)
            return
        }
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
            try NotchSnapshot.write(geometry: geometry, to: URL(fileURLWithPath: path))
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
