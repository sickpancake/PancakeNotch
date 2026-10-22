import AgentsCore
import AppKit
import NotchCore
import Observation
import SwiftUI

/// Agents in the notch (ADR-0037): a mark and a count in the compact ear while a thread works, needs you
/// or has finished; the list of threads in the open notch, with Allow and Deny for the ones that ask.
@MainActor
@Observable
public final class AgentsModule: NotchModule {
    public let center: AgentsCenter

    @ObservationIgnored public private(set) weak var notch: NotchViewModel?

    /// What the peek strip is about (the latest alert).
    var peekAlert: AgentAlert?
    /// Threads whose subagents are shown under them.
    private(set) var openSubagents: Set<String> = []
    /// Whether this copy peeks for alerts. The center tells one module, so Home's live copy doesn't.
    @ObservationIgnored private let peeks: Bool
    /// Rendering off-screen: a plain list instead of a scroll view.
    @ObservationIgnored public var isSnapshot = false
    @ObservationIgnored private var isShowingList = false

    public init(center: AgentsCenter, peeks: Bool = true) {
        self.center = center
        self.peeks = peeks
    }

    // MARK: NotchModule

    public var moduleID: String { "agents" }
    public var title: String { String(localized: "Agents", comment: "Module name") }
    public var symbol: String { "sparkles" }

    public var menuStatus: String? {
        AgentsText.summary(center.threads, includesFinished: true) ?? String(localized: "Nothing running", comment: "Module Menu status")
    }

    /// An ear while any thread works, needs you or has an unseen finish.
    public var isActive: Bool { center.attention != nil }

    /// The notch opens on Agents while a thread needs you.
    public var wantsFocus: Bool {
        if case .needsYou? = center.attention { return true }
        return false
    }

    public var accessibilityStatus: String? { center.attention.map(AgentsText.spoken) }

    public func attach(to notch: NotchViewModel?) {
        self.notch = notch
        guard notch != nil else {
            hideList()
            if peeks { center.onAlert = nil }
            return
        }
        if peeks { center.onAlert = { [weak self] alert in self?.alerted(alert) } }
        observeCenter()
        notch?.activityChanged()
    }

    public func expandedView(layout: NotchLayout) -> AnyView {
        AnyView(AgentsView(module: self, layout: AgentsLayout(layout)))
    }

    public func compactEars(layout: NotchLayout) -> CompactEars? {
        CompactEars(main: AnyView(AgentsEar(module: self)))
    }

    public func peekView(layout: NotchLayout) -> AnyView? {
        peekAlert.map { AnyView(AgentsPeek(alert: $0)) }
    }

    public func notchDidOpen() {
        guard !isShowingList else { return }
        isShowingList = true
        center.listShown()
    }

    public func notchDidClose() {
        hideList()
    }

    public func userSwitchedAway() {
        hideList()
    }

    private func hideList() {
        openSubagents = []
        guard isShowingList else { return }
        isShowingList = false
        center.listHidden()
    }

    // MARK: Following the threads

    /// Re-checks the ear whenever a thread changes. Observation only: nothing is polled.
    private func observeCenter() {
        withObservationTracking {
            _ = center.attention
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.notch != nil else { return }
                self.notch?.activityChanged()
                self.observeCenter()
            }
        }
    }

    /// A thread needs you or finished after real work: a peek, unless the notch is open and shows it.
    private func alerted(_ alert: AgentAlert) {
        guard let notch, notch.state != .expanded else { return }
        peekAlert = alert
        notch.peek(self, for: .seconds(4))
    }

    // MARK: Actions (from the views)

    func toggleSubagents(of thread: AgentThread) {
        if openSubagents.remove(thread.id) == nil { openSubagents.insert(thread.id) }
    }

    /// Brings the thread's app forward and gets the notch out of its way. The practice notch has no
    /// app: it only tells the lesson.
    func open(_ thread: AgentThread) {
        guard thread.canOpen else { return }
        center.open(thread.id)
        if !center.isPractice { notch?.close() }
    }
}
