@testable import AgentsCore
import Foundation
import NotchCore
import Testing
@testable import ModuleAgents

/// Replays the paths of the hover-preview model (`.claude/skills/verify-agents-hover/model/AgentsHover.tla`)
/// on the real `AgentsModule`: the views' events (`hoverChanged`, `rowsMoved`) and the notch's
/// (`notchDidClose`, `notchDidOpen`, `userSwitchedAway`), one call per step. Each test names the rule it
/// guards. A path the code gets wrong (a new finding) may be wrapped in `withKnownIssue` while it stands:
/// it then fails with "known issue not recorded" the moment the code is fixed (then remove the wrapper).
@MainActor
struct AgentsPreviewReplayTests {
    let working = PracticeAgents.workingID
    let asking = PracticeAgents.askingID
    let done = PracticeAgents.doneID

    func module(_ center: AgentsCenter = .practice()) -> AgentsModule {
        AgentsModule(center: center, peeks: false)
    }

    /// The list's rows as `AgentsView` reports them, each one line tall.
    func rows(_ ids: String...) -> [AgentsModule.RowSpot] {
        ids.map { AgentsModule.RowSpot(id: $0) }
    }

    /// Longer than the delay, so a wait that was going to fire has. On a busy machine (CI) the wait can
    /// get its turn after the test does, so it's also awaited: the check sees what the wait left.
    func pastTheDelay(_ agents: AgentsModule) async throws {
        try await Task.sleep(for: AgentsModule.previewDelay + .milliseconds(250))
        await agents.previewWait?.value
    }

    func part(of delay: Double) async throws {
        try await Task.sleep(for: AgentsModule.previewDelay * delay)
    }

    // MARK: Rule 4: only after the pointer rested

    @Test func aRowOpensOnlyAfterThePointerRestedOnIt() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)
        #expect(agents.previewed == nil)
        try await pastTheDelay(agents)
        #expect(agents.previewed == working)
    }

    @Test func sweepingAcrossRowsOpensNone() async throws {
        let agents = module()
        for id in [asking, working, done] {
            agents.hoverChanged(id, isInside: true)
            try await part(of: 0.2)
            agents.hoverChanged(id, isInside: false)
        }
        try await pastTheDelay(agents)
        #expect(agents.previewed == nil)
    }

    /// OpensOnlyAfterRest: the wait of an earlier visit must not count for a row the pointer just came back to.
    @Test func comingBackToARowStartsTheWaitAgain() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)
        try await part(of: 0.7)
        agents.hoverChanged(working, isInside: false)
        agents.hoverChanged(working, isInside: true)
        try await part(of: 0.7)       // 1.4 delays since the first visit, 0.7 since this one
        #expect(agents.previewed == nil)
        try await part(of: 0.7)
        await agents.previewWait?.value
        #expect(agents.previewed == working)
    }

    /// The same through another row: the wait for the first visit to B must have been cancelled when A was entered.
    @Test func comingBackToARowThroughAnotherRowStartsTheWaitAgain() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)          // 0
        try await part(of: 0.3)
        agents.hoverChanged(asking, isInside: true)           // 0.3
        try await part(of: 0.3)
        agents.hoverChanged(asking, isInside: false)          // 0.6
        agents.hoverChanged(working, isInside: false)
        agents.hoverChanged(working, isInside: true)
        try await part(of: 0.5)                               // 1.1 delays since the first visit, 0.5 since this one
        #expect(agents.previewed == nil)
        try await pastTheDelay(agents)
        #expect(agents.previewed == working)
    }

    // MARK: Rules 1, 2, 6, 7: one row, where the pointer is

    @Test func leavingARowClosesItAtOnce() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        agents.hoverChanged(working, isInside: false)
        #expect(agents.previewed == nil)
    }

    @Test func leavingBeforeTheDelayCancelsTheOpening() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)
        agents.hoverChanged(working, isInside: false)
        try await pastTheDelay(agents)
        #expect(agents.previewed == nil)
    }

    /// SwiftUI may deliver the enter of row B before the exit of row A: only B may end up open.
    @Test func enteringTheNextRowBeforeTheExitOfTheLastLeavesOnlyTheNext() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        #expect(agents.previewed == working)
        agents.hoverChanged(asking, isInside: true)
        #expect(agents.previewed == nil)                       // A closes at once
        agents.hoverChanged(working, isInside: false)          // the late exit of A
        #expect(agents.previewed == nil)
        try await pastTheDelay(agents)
        #expect(agents.previewed == asking)
    }

    @Test func enteringTheNextRowBeforeTheExitOfOneStillWaitingOpensOnlyTheNext() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)
        try await part(of: 0.5)
        agents.hoverChanged(asking, isInside: true)
        agents.hoverChanged(working, isInside: false)
        try await pastTheDelay(agents)
        #expect(agents.previewed == asking)
    }

    // MARK: Rule 3: nothing while the list is off screen

    @Test func closingTheNotchEndsAnOpenRowAndReopeningShowsNone() async throws {
        let agents = module()
        agents.notchDidOpen()
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        agents.notchDidClose()
        #expect(agents.previewed == nil)
        agents.notchDidOpen()
        #expect(agents.previewed == nil)
    }

    @Test func closingTheNotchCancelsAWaitingRow() async throws {
        let agents = module()
        agents.notchDidOpen()
        agents.hoverChanged(working, isInside: true)
        agents.notchDidClose()
        try await pastTheDelay(agents)
        #expect(agents.previewed == nil)
    }

    @Test func switchingToAnotherModuleEndsTheRowAndTheWait() async throws {
        let agents = module()
        agents.notchDidOpen()
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        agents.hoverChanged(asking, isInside: true)
        agents.userSwitchedAway()
        try await pastTheDelay(agents)
        #expect(agents.previewed == nil)
    }

    @Test func theReviewScreenEndsTheRowAndNothingOpensBehindIt() async throws {
        let center = AgentsCenter.practiceWithEdit()
        let agents = module(center)
        let editing = try #require(center.threads.first { $0.id == PracticeAgents.editingID })
        agents.hoverChanged(editing.id, isInside: true)
        try await pastTheDelay(agents)
        #expect(agents.previewed == editing.id)
        agents.review(editing)
        #expect(agents.previewed == nil)
        // A row entered while the review screen is up never opens.
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        #expect(agents.previewed == nil)
    }

    @Test func reviewingWhileARowIsStillWaitingCancelsIt() async throws {
        let center = AgentsCenter.practiceWithEdit()
        let agents = module(center)
        let editing = try #require(center.threads.first { $0.id == PracticeAgents.editingID })
        agents.hoverChanged(editing.id, isInside: true)
        agents.review(editing)
        agents.closeReview()
        try await pastTheDelay(agents)
        #expect(agents.previewed == nil)
    }

    // MARK: Rule 5: rows that moved

    @Test func aRowMovedOutFromUnderThePointerCloses() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        agents.rowsMoved(from: rows(asking, working, done), to: rows(asking, done, working))   // it changed place
        #expect(agents.previewed == nil)
    }

    @Test func aRowPushedDownByAThreadAboveItCloses() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        agents.rowsMoved(from: rows(working, done), to: rows("claude:new", working, done))
        #expect(agents.previewed == nil)
    }

    @Test func aRowWaitingToOpenIsDroppedWhenItsRowMoves() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)
        agents.rowsMoved(from: rows(asking, working), to: rows(working))
        try await pastTheDelay(agents)
        #expect(agents.previewed == nil)
    }

    @Test func subagentsShownAboveARowPushItAndClose() async throws {
        let agents = module()
        agents.hoverChanged(done, isInside: true)
        try await pastTheDelay(agents)
        agents.rowsMoved(from: rows(working, done), to: rows(working, "claude:practice-cookie", done))
        #expect(agents.previewed == nil)
    }

    @Test func aThreadGoingAwayThatIsNotTheOpenOneKeepsItOpen() async throws {
        let agents = module()
        agents.hoverChanged(asking, isInside: true)
        try await pastTheDelay(agents)
        agents.rowsMoved(from: rows(asking, working, done), to: rows(asking, working))
        #expect(agents.previewed == asking)
    }

    @Test func theOpenRowGoingAwayCloses() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        agents.rowsMoved(from: rows(asking, working), to: rows(asking))
        #expect(agents.previewed == nil)
    }

    /// A row above grows (a request's command lines appear): the open row is pushed down from under the pointer.
    @Test func aRowAboveGrowingPushesTheOpenRowAndCloses() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        agents.rowsMoved(from: [.init(id: asking), .init(id: working)], to: [.init(id: asking, extraLines: 1), .init(id: working)])
        #expect(agents.previewed == nil)
    }

    /// The open row itself grows (its own request lines appear under it): it stays where it is, and open.
    @Test func theOpenRowGrowingKeepsItOpen() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        agents.rowsMoved(from: [.init(id: asking), .init(id: working)], to: [.init(id: asking), .init(id: working, extraLines: 2)])
        #expect(agents.previewed == working)
    }

    /// Shifts: the user scrolls the list under a pointer that stays put.
    @Test func scrollingClosesTheOpenRowAndDropsAWait() async throws {
        let agents = module()
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        agents.listScrolled()
        #expect(agents.previewed == nil)
        agents.hoverChanged(asking, isInside: true)
        agents.listScrolled()
        try await pastTheDelay(agents)
        #expect(agents.previewed == nil)
    }

    // MARK: The last thread goes (was a finding in Shipped.cfg, fixed)

    /// NothingWhileHidden / MovedRowsClose: when the last thread goes, the "No agents running" note
    /// replaces the list. `AgentsView`, which stays, reports the rows as gone, so the open row, the
    /// hovered id and any wait are dropped; a thread with that id coming back doesn't open by itself.
    @Test func whenTheLastThreadGoesTheOpenRowIsForgotten() async throws {
        let center = AgentsCenter.practice()
        let agents = module(center)
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        #expect(agents.previewed == working)
        for id in [asking, working, done] { center.forget(id) }
        agents.rowsMoved(from: rows(asking, working, done), to: [])          // AgentsView, now showing the note
        center.reset()                                                   // the same threads come back
        agents.rowsMoved(from: [], to: rows(asking, working, done))
        #expect(agents.previewed == nil)
    }

    /// The same while the row is only waiting; the wait itself also checks that its thread is still there.
    @Test func aWaitingRowIsNotOpenedForAThreadThatIsGone() async throws {
        let center = AgentsCenter.practice()
        let agents = module(center)
        agents.hoverChanged(working, isInside: true)
        for id in [asking, working, done] { center.forget(id) }
        try await pastTheDelay(agents)
        #expect(agents.previewed == nil)
    }

    /// Closing the notch also cleans it up.
    @Test func closingAndReopeningTheNotchCleansUpAfterTheLastThreadWent() async throws {
        let center = AgentsCenter.practice()
        let agents = module(center)
        agents.hoverChanged(working, isInside: true)
        for id in [asking, working, done] { center.forget(id) }
        agents.notchDidClose()
        center.reset()
        agents.notchDidOpen()
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        #expect(agents.previewed == working)
    }

    // MARK: A real notch: hover only while the list shows

    /// NothingWhileHidden: notchDidClose runs as the close *starts*, while the list is still drawn; a
    /// hover that arrives during the close animation, or after it, must not start a wait.
    @Test func aHoverWhileTheListIsNotShowingIsIgnored() async throws {
        let agents = module()
        let notch = NotchViewModel(layout: NotchLayout(geometry: .simulated(in: CGRect(x: -30_000, y: -30_000, width: 1512, height: 982))),
                                   isMissionControlActive: { false })
        notch.modules = [agents]
        defer { notch.modules = [] }
        agents.hoverChanged(working, isInside: true)                    // the notch never opened
        try await pastTheDelay(agents)
        #expect(agents.previewed == nil)
        agents.notchDidOpen()
        agents.hoverChanged(working, isInside: true)
        try await pastTheDelay(agents)
        #expect(agents.previewed == working)
        agents.notchDidClose()                                           // the close starts
        agents.hoverChanged(asking, isInside: true)                     // a hover during the animation
        try await pastTheDelay(agents)
        #expect(agents.previewed == nil)
        agents.notchDidOpen()                                            // and nothing left over on reopening
        #expect(agents.previewed == nil)
    }
}
