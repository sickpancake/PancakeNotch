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
        updateGeometry()
    }

    private func updateGeometry() {
        let geometry = currentGeometry()
        if let geometry {
            logger.info("Notch at \(String(describing: geometry.notchRect), privacy: .public) simulated=\(geometry.isSimulated)")
        } else {
            logger.info("No notch available; idling")
        }
        notchController.update(geometry: geometry)
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
