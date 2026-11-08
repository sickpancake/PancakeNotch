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
    /// The request whose change is on the review screen (the notch is taller meanwhile). Only the very
    /// request Review was clicked for: once it's answered or replaced, the list comes back.
    private(set) var reviewing: (threadID: String, approval: PendingApproval)?
    /// The thread whose row is open a little to show its whole title, what it's doing and where it runs:
    /// the one the pointer rested on. At most one, and never while the list isn't on screen.
    private(set) var previewed: String?
    /// The row the pointer is over, and the wait before it opens.
    @ObservationIgnored private var hovered: String?
    @ObservationIgnored private(set) var previewWait: Task<Void, Never>?
    /// How long the pointer rests on a row before it opens, so sweeping across the list doesn't make
    /// rows jump.
    static let previewDelay: Duration = .milliseconds(350)
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

    /// The notch opens on Agents while a thread needs you, also while a song plays (ADR-0037), and its
    /// "!" gets a spot beside the notch before modules that don't wait.
    public var wantsFocus: Bool { waitsForYou }
    public var waitsForYou: Bool {
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
        // A hover that reached the list after it left the screen can't leave a row open for this showing.
        endPreview()
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
        reviewing = nil
        endPreview()
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

    /// Shows a request's whole change in the taller notch, to Allow or Deny it there.
    func review(_ thread: AgentThread) {
        guard let approval = thread.approval, case .edit = approval.review.content else { return }
        reviewing = (thread.id, approval)
        endPreview()
        notch?.setTall(true)
    }

    /// Back to the list (Back, or the request went away).
    func closeReview() {
        guard reviewing != nil else { return }
        reviewing = nil
        notch?.setTall(false)
    }

    /// The pointer came onto a row or left it. A row opens after the pointer rests on it for
    /// `previewDelay`; it closes as soon as the pointer leaves, or another row is hovered.
    func hoverChanged(_ threadID: String, isInside: Bool) {
        if isInside {
            // A real notch's list that isn't showing (closing, another module) takes no new hover. Practice
            // notches have no notch and are always taken to be showing.
            guard hovered != threadID, notch == nil || isShowingList else { return }
            hovered = threadID
            if previewed != threadID { previewed = nil }
            previewWait?.cancel()
            guard previewed == nil else { return }
            previewWait = Task { [weak self] in
                try? await Task.sleep(for: Self.previewDelay)
                guard !Task.isCancelled, let self, self.hovered == threadID, self.reviewing == nil,
                      self.center.threads.contains(where: { $0.id == threadID }) else { return }
                self.previewed = threadID
            }
        } else {
            if hovered == threadID {
                hovered = nil
                previewWait?.cancel()
                previewWait = nil
            }
            if previewed == threadID { previewed = nil }
        }
    }

    /// The rows changed (a thread came, went, changed place or grew, subagents shown): if anything above
    /// the pointer's row changed, or the row itself went, that row was moved out from under the pointer.
    /// It doesn't stay open, and a wait for it is dropped. `AgentsView` tells this, so it's told also when
    /// the last thread goes and the "No agents" note takes the list's place.
    func rowsMoved(from old: [RowSpot], to new: [RowSpot]) {
        guard let id = hovered ?? previewed else { return }
        func above(_ rows: [RowSpot]) -> ArraySlice<RowSpot>? { rows.firstIndex { $0.id == id }.map { rows[..<$0] } }
        if above(old) != above(new) { endPreview() }
    }

    /// The user scrolled the list: the rows moved under a pointer that stayed put.
    func listScrolled() {
        endPreview()
    }

    /// For the off-screen snapshot: this thread's row open, as if the pointer rested on it.
    func previewForSnapshot(_ threadID: String) {
        hovered = threadID
        previewed = threadID
    }

    /// One row of the list, as far as where the rows below it sit: a thread's row (taller with a command's
    /// lines) or a subagent's.
    struct RowSpot: Equatable {
        let id: String
        var extraLines = 0
    }

    private func endPreview() {
        previewWait?.cancel()
        previewWait = nil
        hovered = nil
        previewed = nil
    }

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
