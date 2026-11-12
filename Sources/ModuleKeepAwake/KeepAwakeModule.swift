import AppKit
import KeepAwakeCore
import NotchCore
import Observation
import SwiftUI

/// Keep Awake in the notch (ADR-0041): while it keeps the Mac awake it takes the first ear with a coffee cup
/// (a draining ring for a timed session); its page says why and until when, with the lengths, +30 min and
/// Turn On / Turn Off. When it stops by itself (time up, battery low) a short strip says so.
@MainActor
@Observable
public final class KeepAwakeModule: NotchModule {
    public let center: KeepAwakeCenter

    @ObservationIgnored public private(set) weak var notch: NotchViewModel?

    /// The battery stopped it and plugging in brings it back (the battery strip says so).
    private var comesBack: Bool { center.stoppedForBattery && center.settings.plugIn == .turnBackOn }
    /// What it last told with a strip, while the strip shows or waits for the notch to close.
    private(set) var ended: KeepAwakeNotice?
    /// It stopped by itself while the open notch showed another module: the strip shows once it closes.
    private var endPending = false
    /// The display is asleep: nothing ticks.
    private(set) var isDisplayAsleep = false
    /// Rendering off-screen: no ticking, plain rings.
    @ObservationIgnored public var isSnapshot = false
    /// Whether this copy shows the strip. Home's live copy shares the center but stays quiet.
    @ObservationIgnored private let presents: Bool
    @ObservationIgnored private var displayObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var observationGeneration = 0
    /// How long the strip stays under the notch.
    @ObservationIgnored var stripTime: Duration = .seconds(5)

    public init(center: KeepAwakeCenter, presents: Bool = true) {
        self.center = center
        self.presents = presents
    }

    // MARK: NotchModule

    public var moduleID: String { "keepAwake" }
    public var title: String { String(localized: "Keep Awake", comment: "Module name") }
    public var symbol: String { "cup.and.heat.waves" }
    public var menuStatus: String? { KeepAwakeStatus.short(center) }

    /// An ear exactly while it keeps the Mac awake.
    public var isActive: Bool { center.isHolding }
    /// Always the first ear while on; the Timer keeps the second (ADR-0041).
    public var prefersFirstEar: Bool { true }
    public var accessibilityStatus: String? { center.isHolding ? KeepAwakeStatus.spoken(center) : nil }

    public func attach(to notch: NotchViewModel?) {
        observationGeneration += 1
        self.notch = notch
        guard notch != nil else {
            if presents { center.onNotice = nil }
            stopWatchingDisplay()
            return
        }
        if presents { center.onNotice = { [weak self] reason in self?.noticed(reason) } }
        watchDisplay()
        observe()
        notch?.activityChanged()
    }

    public func expandedView(layout: NotchLayout) -> AnyView {
        AnyView(KeepAwakeView(module: self, layout: KeepAwakeLayout(layout)))
    }

    public func compactEars(layout: NotchLayout) -> CompactEars? {
        CompactEars(main: AnyView(KeepAwakeEar(module: self, width: layout.compactEarWidth, height: layout.geometry.compactHeight)))
    }

    public func peekView(layout: NotchLayout) -> AnyView? {
        ended.map { AnyView(KeepAwakePeek(reason: $0, comesBack: comesBack)) }
    }

    public func notchDidOpen() {
        // The page shows it's off: nothing left to tell.
        if notch?.selectedModule === self { endPending = false }
    }

    // MARK: Following the center

    /// Re-checks the ear whenever it starts or stops keeping the Mac awake. Observation only.
    private func observe() {
        let generation = observationGeneration
        withObservationTracking {
            _ = center.isHolding
            _ = notch?.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.notch != nil, self.observationGeneration == generation else { return }
                // Back on: an old "ended" strip no longer tells the truth.
                if self.center.isHolding, self.ended?.isStop == true { self.clearEnded() }
                // Plugged in (or the stop lifted) before a waiting battery strip could show: it's no longer true.
                if self.ended == .batteryLow, !self.center.batteryStops { self.clearEnded() }
                self.notch?.activityChanged()
                self.showPendingStrip()
                self.observe()
            }
        }
    }

    /// It stopped by itself: a strip where it can be seen. Open on this page: the page shows it. Open on
    /// another module: the strip when the notch closes. Closed: the strip now.
    private func noticed(_ reason: KeepAwakeNotice) {
        guard let notch else { return }
        ended = reason
        notch.activityChanged()
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: Self.stripText(reason, comesBack: comesBack).spoken, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )
        if notch.state == .expanded {
            endPending = !(notch.selectedModule === self && !notch.showsHome)
        } else {
            notch.requestPeek(from: self, for: stripTime, revealsInFullScreen: false)
        }
    }

    private func showPendingStrip() {
        guard let notch, endPending, notch.state != .expanded else { return }
        endPending = false
        notch.peek(self, for: stripTime)
    }

    /// Off-screen pictures: the strip for `reason`, without anything having ended.
    public func showNoticeForSnapshot(_ reason: KeepAwakeNotice) {
        ended = reason
    }

    private func clearEnded() {
        endPending = false
        guard ended != nil else { return }
        notch?.endPeek(of: self)
        ended = nil
    }

    /// The strip's words: a title and a detail, and what VoiceOver says. `comesBack`: plugging in brings it back.
    static func stripText(_ reason: KeepAwakeNotice, comesBack: Bool = false) -> (title: String, detail: String, spoken: String) {
        let detail = String(localized: "Your Mac can sleep again", comment: "Keep Awake strip")
        switch reason {
        case .timeUp:
            let title = String(localized: "Keep Awake ended", comment: "Keep Awake strip: the time ran out")
            return (title, detail, title + ". " + detail)
        case .batteryLow:
            let title = String(localized: "Battery low", comment: "Keep Awake strip: stopped for the battery")
            guard comesBack else {
                return (title, detail, String(localized: "Keep Awake stopped, battery low. Your Mac can sleep again."))
            }
            let back = String(localized: "Back on when you plug in", comment: "Keep Awake strip: stopped for the battery, comes back")
            return (title, back, String(localized: "Keep Awake stopped, battery low. It comes back on when you plug in."))
        case .batteryLowKeepsGoing:
            let title = String(localized: "Battery low", comment: "Keep Awake strip: low battery, keeps going")
            let going = String(localized: "Keep Awake keeps going", comment: "Keep Awake strip: low battery, keeps going")
            return (title, going, String(localized: "Battery low. Keep Awake keeps going."))
        case .backOn:
            let title = String(localized: "Keep Awake turned on", comment: "Keep Awake strip: on after plugging in")
            let plugged = String(localized: "Your Mac is plugged in", comment: "Keep Awake strip: back on after plugging in")
            return (title, plugged, title + ". " + plugged)
        }
    }

    // MARK: Actions

    /// Runs a control's action: using the notch keeps an alert's close from shutting it.
    func user(_ action: () -> Void) {
        notch?.userInteracted()
        action()
    }

    // MARK: Display sleep

    private func watchDisplay() {
        guard displayObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        displayObservers = [
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isDisplayAsleep = true }
            },
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isDisplayAsleep = false }
            },
        ]
    }

    private func stopWatchingDisplay() {
        displayObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        displayObservers = []
        isDisplayAsleep = false
    }

    /// The page's "min left" may change (once a minute): on screen, awake, and a timed session runs.
    var pageTicks: Bool {
        !isSnapshot && !isDisplayAsleep && notch?.isOnScreen == true && center.session?.end != nil && center.isHolding
    }
}

public extension KeepAwakeModule {
    /// A practice copy for the app window (Learn, Modules): the user's settings, its own center that holds
    /// nothing, always plugged in.
    static func practice() -> KeepAwakeModule {
        let settings = KeepAwakeSettings.user ?? KeepAwakeSettings(defaults: UserDefaults(suiteName: "PracticeKeepAwake") ?? .standard)
        return KeepAwakeModule(center: KeepAwakeCenter(settings: settings, isPractice: true))
    }
}
