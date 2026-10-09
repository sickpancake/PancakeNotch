import AppKit
import NotchCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "app")

    /// Set `PANCAKENOTCH_SIMULATE_NOTCH=1` to fake a notch on screens without one (CI, external displays).
    private let simulateNotch = ProcessInfo.processInfo.environment["PANCAKENOTCH_SIMULATE_NOTCH"] == "1"

    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        guard let geometry = currentGeometry() else {
            logger.info("No notch available; idling")
            return
        }
        logger.info("Notch at \(String(describing: geometry.notchRect), privacy: .public) simulated=\(geometry.isSimulated)")
    }

    private func currentGeometry() -> NotchGeometry? {
        if let geometry = NSScreen.builtIn?.notchGeometry { return geometry }
        if simulateNotch, let screen = NSScreen.main { return .simulated(in: screen.frame) }
        return nil
    }
}
