import AppKit
import Observation
import os
import Sparkle

/// Automatic updates through Sparkle (ADR-0005). It checks once a day and asks before installing.
/// A check that finds an update stays quiet: a dot on the menu bar icon, a card on Home and a menu
/// item. Sparkle's window opens only when the user clicks one of them (gentle reminders).
///
/// Only released builds can update: the release pipeline writes the update-signing public key into
/// Info.plist. Builds made on a Mac have none, so there is no updater and every update control hides.
@MainActor
@Observable
final class Updates: NSObject {
    /// Whether this copy can update itself (a released build).
    let isAvailable: Bool
    /// The version a background check found, waiting for the user to look at it.
    private(set) var pendingVersion: String?
    /// Whether "Check for Updates…" can start a check right now.
    private(set) var canCheck = false
    /// When Sparkle last asked for the update feed.
    private(set) var lastCheck: Date?
    /// Called when `pendingVersion` changes (the menu bar icon's dot).
    @ObservationIgnored var onPendingChange: (() -> Void)?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "updates")
    /// The switch's value without Sparkle (snapshots).
    @ObservationIgnored private var storedAutomaticallyChecks = true

    /// The "Check for updates automatically" switch (Sparkle keeps it in the app's defaults).
    var automaticallyChecks: Bool {
        get {
            access(keyPath: \.automaticallyChecks)
            return controller?.updater.automaticallyChecksForUpdates ?? storedAutomaticallyChecks
        }
        set {
            withMutation(keyPath: \.automaticallyChecks) {
                if let controller {
                    controller.updater.automaticallyChecksForUpdates = newValue
                } else {
                    storedAutomaticallyChecks = newValue
                }
            }
        }
    }

    init(bundle: Bundle = .main) {
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        isAvailable = !(key ?? "").isEmpty && !(feed ?? "").isEmpty
        super.init()
    }

    /// A released build's updates without Sparkle, for the off-screen snapshots.
    init(snapshotPendingVersion: String?, lastCheck: Date?) {
        isAvailable = true
        super.init()
        pendingVersion = snapshotPendingVersion
        self.lastCheck = lastCheck
        canCheck = true
    }

    /// Starts Sparkle's daily schedule. Does nothing in builds that can't update.
    func start() {
        guard isAvailable, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        do {
            try controller.updater.start()
        } catch {
            logger.error("Updater didn't start: \(error.localizedDescription, privacy: .public)")
            self.controller = nil
            return
        }
        // Sparkle changes it on the main thread.
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
        lastCheck = controller.updater.lastUpdateCheckDate
    }

    /// "Check for Updates…" and the update hints: shows Sparkle's window (the waiting update, if any).
    func checkNow() {
        guard let controller else { return }
        NSApp.activate()
        controller.updater.checkForUpdates()
    }

    private func setPending(_ version: String?) {
        guard pendingVersion != version else { return }
        pendingVersion = version
        onPendingChange?()
    }
}

extension Updates: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastCheck = updater.lastUpdateCheckDate
    }
}

extension Updates: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// A check the user asked for shows its window straight away; a scheduled one waits for a click.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate, !state.userInitiated {
            setPending(update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        setPending(nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        setPending(nil)
    }
}
