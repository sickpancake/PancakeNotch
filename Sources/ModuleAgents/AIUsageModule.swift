import AgentsCore
import AppKit
import NotchCore
import Observation
import SwiftUI

/// AI Usage in the notch (ADR-0037): the plan limits and token totals of the Claude Code and Codex
/// accounts on this Mac, with a ring and a number in the compact ear when one is nearly out.
@MainActor
@Observable
public final class AIUsageModule: NotchModule {
    public let center: UsageCenter

    @ObservationIgnored public private(set) weak var notch: NotchViewModel?

    /// The account menu is showing: it keeps the notch open.
    private(set) var isMenuOpen = false
    private(set) var focusedAccount: AccountSelection = .all
    var menuChoices: [AccountSelection] {
        [.all] + AgentTool.allCases.flatMap { tool in
            center.accounts.filter { $0.tool == tool }.map { .account($0.id) }
        }
    }
    /// What the peek strip is about (the latest account to run low).
    var peekNear: NearLimit?
    /// Whether this copy peeks. The center tells one module, so Home's live copy doesn't.
    @ObservationIgnored private let peeks: Bool
    /// Rendering off-screen: plain lists instead of scroll views.
    @ObservationIgnored public var isSnapshot = false
    /// `viewShown()` was called and `viewHidden()` hasn't been yet (the center counts them).
    @ObservationIgnored private var isShowingHistory = false
    @ObservationIgnored private var clickAwayMonitor: Any?
    @ObservationIgnored private var appSwitchObserver: (any NSObjectProtocol)?

    public init(center: UsageCenter, peeks: Bool = true) {
        self.center = center
        self.peeks = peeks
    }

    // MARK: NotchModule

    public var moduleID: String { "aiUsage" }
    public var title: String { String(localized: "AI Usage", comment: "Module name") }
    public var symbol: String { "gauge.with.dots.needle.50percent" }

    public var menuStatus: String? {
        if center.accounts.isEmpty { return String(localized: "No accounts found", comment: "Module Menu status") }
        let account = center.selectedAccount
        return AIUsageText.menuStatus(account: account, limits: account.flatMap { center.limits[$0.id] })
    }

    /// An ear while an account is under 10% left.
    public var isActive: Bool { center.nearLimit != nil }

    public var accessibilityStatus: String? { center.nearLimit.map { AIUsageText.spoken($0, now: .now) } }

    public func attach(to notch: NotchViewModel?) {
        self.notch = notch
        guard notch != nil else {
            closeMenu()
            hideHistory()
            if peeks { center.onNearLimit = nil }
            return
        }
        if peeks { center.onNearLimit = { [weak self] near in self?.ranLow(near) } }
        observeCenter()
        notch?.activityChanged()
    }

    public func expandedView(layout: NotchLayout) -> AnyView {
        AnyView(AIUsageView(module: self, layout: AgentsLayout(layout)))
    }

    public func compactEars(layout: NotchLayout) -> CompactEars? {
        CompactEars(main: AnyView(AIUsageEar(module: self)))
    }

    public func peekView(layout: NotchLayout) -> AnyView? {
        peekNear.map { AnyView(AIUsagePeek(near: $0)) }
    }

    /// The token history is read only while this view is on screen.
    public func notchDidOpen() {
        guard !isShowingHistory else { return }
        isShowingHistory = true
        center.viewShown()
    }

    public func notchDidClose() {
        closeMenu()
        hideHistory()
    }

    public func userSwitchedAway() {
        closeMenu()
        hideHistory()
    }

    private func hideHistory() {
        guard isShowingHistory else { return }
        isShowingHistory = false
        center.viewHidden()
    }

    // MARK: Following the limits

    /// Re-checks the ear whenever the limits change. Observation only: nothing is polled.
    private func observeCenter() {
        withObservationTracking {
            _ = center.nearLimit
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.notch != nil else { return }
                self.notch?.activityChanged()
                self.observeCenter()
            }
        }
    }

    /// An account dropped under 10% left: a peek, unless the notch is open and shows it.
    private func ranLow(_ near: NearLimit) {
        guard let notch, notch.state != .expanded else { return }
        peekNear = near
        notch.peek(self, for: .seconds(4))
    }

    // MARK: The account menu

    /// The menu keeps the notch open while it's showing.
    public var holdsOpen: Bool { isMenuOpen }

    func toggleMenu() {
        if isMenuOpen { closeMenu() } else { openMenu() }
    }

    func openMenu() {
        guard !isMenuOpen else { return }
        isMenuOpen = true
        focusedAccount = center.selection
        center.accountsMenuOpened()
        notch?.requestKeyFocus?()
        watchClicksAway()
    }

    func closeMenu() {
        guard isMenuOpen else { return }
        isMenuOpen = false
        stopWatchingClicksAway()
        notch?.holdReleased()
    }

    func choose(_ selection: AccountSelection) {
        center.choose(selection)
        closeMenu()
    }

    /// Esc closes the menu. While it's open it takes every key, like a system menu (⌘ shortcuts still go through).
    public func handleKey(_ event: NSEvent) -> Bool {
        guard isMenuOpen else { return false }
        guard !event.modifierFlags.contains(.command) else { return false }
        switch event.keyCode {
        case 53: closeMenu()
        case 125: moveMenuFocus(by: 1)
        case 126: moveMenuFocus(by: -1)
        case 48: moveMenuFocus(by: event.modifierFlags.contains(.shift) ? -1 : 1)
        case 115: focusedAccount = menuChoices.first ?? .all
        case 119: focusedAccount = menuChoices.last ?? .all
        case 36, 76, 49: choose(focusedAccount)
        default: break
        }
        return true
    }

    func focus(_ choice: AccountSelection) { focusedAccount = choice }

    func moveMenuFocus(by amount: Int) {
        let choices = menuChoices
        let index = choices.firstIndex(of: focusedAccount) ?? 0
        focusedAccount = choices[(index + amount + choices.count) % choices.count]
    }

    /// A click elsewhere in the app window closes the menu in a practice notch, the way a click in
    /// another app closes it in the real one.
    public func clickedOutsidePreview() {
        closeMenu()
    }

    /// A click in another app, or switching to another app, closes the menu. Clicks on the notch itself
    /// are the scrim's.
    private func watchClicksAway() {
        guard clickAwayMonitor == nil else { return }
        clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeMenu() }
        }
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.closeMenu() }
        }
    }

    private func stopWatchingClicksAway() {
        if let clickAwayMonitor { NSEvent.removeMonitor(clickAwayMonitor) }
        clickAwayMonitor = nil
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        appSwitchObserver = nil
    }
}
