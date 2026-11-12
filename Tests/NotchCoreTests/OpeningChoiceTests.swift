import AppKit
import SwiftUI
import Testing
@testable import NotchCore

/// A module whose activity, focus and spot the test sets: Agents ("needs you") or the Timer ("Done").
@MainActor
final class WaitingModule: NotchModule {
    let moduleID: String
    var isActive = false
    var wantsFocus = false
    var isIdleForOpening = false
    var waitsForYou = false
    var prefersSecondEar = false
    weak var notch: NotchViewModel?

    init(_ id: String) { moduleID = id }

    func attach(to notch: NotchViewModel?) { self.notch = notch }
    func expandedView(layout: NotchLayout) -> AnyView { AnyView(EmptyView()) }
    func compactEars(layout: NotchLayout) -> CompactEars? { CompactEars(main: AnyView(EmptyView())) }
    func peekView(layout: NotchLayout) -> AnyView? { AnyView(EmptyView()) }
}

/// What the notch opens on when you point at it while a song plays (an ear, a strip or the middle), and
/// who gets the spots beside it. Each test replays a path TLA+ found (NotchEars.tla, UX review 2026-11-03).
@MainActor
struct OpeningChoiceTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    final class Pointer {
        var location = CGPoint(x: 5, y: 5)
    }

    /// The default order (Now Playing, Shelf, Agents, Timer) with a song playing.
    func makeModel(_ pointer: Pointer) -> (NotchViewModel, RankedModule, WaitingModule, WaitingModule) {
        let model = NotchViewModel(
            layout: layout,
            behavior: NotchBehavior(openDelay: .milliseconds(10), closeDelay: .milliseconds(10)),
            pointerLocation: { pointer.location },
            isMissionControlActive: { false }
        )
        let music = RankedModule("nowPlaying")
        music.hasExtraEar = true
        music.isActive = true
        music.wantsFocus = true
        let agents = WaitingModule("agents")
        let timer = WaitingModule("timer")
        timer.prefersSecondEar = true
        model.modules = [music, RankedModule("shelf"), agents, timer]
        return (model, music, agents, timer)
    }

    var rightEar: CGPoint { CGPoint(x: layout.geometry.notchRect.maxX + 10, y: layout.geometry.notchRect.maxY - 5) }
    var leftEar: CGPoint { CGPoint(x: layout.geometry.notchRect.minX - 10, y: layout.geometry.notchRect.maxY - 5) }
    var middle: CGPoint { CGPoint(x: layout.geometry.notchRect.midX, y: layout.geometry.notchRect.maxY - 5) }
    /// On the strip under the compact notch, below the ears.
    var strip: CGPoint {
        CGPoint(x: layout.geometry.notchRect.midX, y: layout.geometry.notchRect.maxY - layout.geometry.compactHeight - 10)
    }

    func agentNeedsYou(_ model: NotchViewModel, _ agents: WaitingModule) {
        agents.isActive = true
        agents.wantsFocus = true
        agents.waitsForYou = true
        model.activityChanged()
    }

    func timerIsDone(_ model: NotchViewModel, _ timer: WaitingModule) {
        timer.isActive = true
        timer.wantsFocus = true
        timer.waitsForYou = true
        model.activityChanged()
    }

    // MARK: Pointing at an ear or a strip

    // WhatYouClickIsWhatOpens: an agent needs you → you click the agent ear.
    @Test func clickingAnEarOpensThatModule() {
        let pointer = Pointer()
        let (model, _, agents, _) = makeModel(pointer)
        agentNeedsYou(model, agents)
        #expect(model.ears(layout: layout).right?.moduleID == "agents")
        pointer.location = rightEar
        model.tap()
        #expect(model.state == .expanded)
        #expect(model.selectedModule?.moduleID == "agents")
    }

    // An ear that isn't waiting for you (a working agent, the Shelf's count) opens its module too.
    @Test func hoveringAnyEarOpensThatModule() async throws {
        let pointer = Pointer()
        let (model, _, agents, _) = makeModel(pointer)
        agents.isActive = true
        model.activityChanged()
        pointer.location = rightEar
        model.hoverChanged(true)
        try await settle(.milliseconds(40)) { model.state == .expanded }
        #expect(model.selectedModule?.moduleID == "agents")
    }

    // The song's own ear still opens on the song, also while an agent waits.
    @Test func clickingTheSongEarOpensTheSong() {
        let pointer = Pointer()
        let (model, _, agents, _) = makeModel(pointer)
        agentNeedsYou(model, agents)
        pointer.location = leftEar
        model.tap()
        #expect(model.selectedModule?.moduleID == "nowPlaying")
    }

    // Alone, the song fills both ears: its sound bars open on it too.
    @Test func theSoundBarsEarOpensTheSong() {
        let pointer = Pointer()
        let (model, _, _, _) = makeModel(pointer)
        model.select("shelf")
        pointer.location = rightEar
        model.tap()
        #expect(model.selectedModule?.moduleID == "nowPlaying")
    }

    // WhatYouClickIsWhatOpens: an agent needs you → its strip shows → you click the strip.
    @Test func clickingAStripOpensWhatItIsAbout() {
        let pointer = Pointer()
        let (model, _, agents, _) = makeModel(pointer)
        agentNeedsYou(model, agents)
        #expect(model.peek(agents, for: .seconds(5)))
        pointer.location = strip
        #expect(model.layout.outline(for: .compact, contains: strip))
        model.tap()
        #expect(model.selectedModule?.moduleID == "agents")
    }

    // A new song's strip opens on the song, also on its right half, under the Timer's ear (a bug in main:
    // that half counted as the Timer's ear).
    @Test func clickingTheSongStripOpensTheSong() {
        let pointer = Pointer()
        let (model, music, _, timer) = makeModel(pointer)
        timer.isActive = true
        model.activityChanged()
        #expect(model.peek(music, for: .seconds(5)))
        pointer.location = CGPoint(x: rightEar.x, y: strip.y)
        model.tap()
        #expect(model.selectedModule?.moduleID == "nowPlaying")
    }

    @Test func hoveringAStripOpensWhatItIsAbout() async throws {
        let pointer = Pointer()
        let (model, _, agents, _) = makeModel(pointer)
        agents.isActive = true
        model.activityChanged()
        #expect(model.peek(agents, for: .seconds(5)))
        pointer.location = strip
        model.hoverChanged(true)
        try await settle(.milliseconds(40)) { model.state == .expanded }
        #expect(model.selectedModule?.moduleID == "agents")
    }

    // MARK: Opening the usual way

    // UrgentComesFirst: an agent needs you → you hover the middle of the notch.
    @Test func anAgentThatNeedsYouComesBeforeTheSong() async throws {
        let pointer = Pointer()
        let (model, _, agents, _) = makeModel(pointer)
        agentNeedsYou(model, agents)
        pointer.location = middle
        model.hoverChanged(true)
        try await settle(.milliseconds(40)) { model.state == .expanded }
        #expect(model.selectedModule?.moduleID == "agents")
    }

    // UrgentComesFirst: a timer finishes, its open notch closes → you hover the middle.
    @Test func aFinishedTimerComesBeforeTheSong() async throws {
        let pointer = Pointer()
        let (model, _, _, timer) = makeModel(pointer)
        timerIsDone(model, timer)
        pointer.location = middle
        model.hoverChanged(true)
        try await settle(.milliseconds(40)) { model.state == .expanded }
        #expect(model.selectedModule?.moduleID == "timer")
    }

    // Both waiting: the agent (ranked before the Timer) comes first; the Timer's ear still opens the Timer.
    @Test func withBothWaitingTheOrderDecides() {
        let pointer = Pointer()
        let (model, _, agents, timer) = makeModel(pointer)
        agentNeedsYou(model, agents)
        timerIsDone(model, timer)
        pointer.location = middle
        model.tap()
        #expect(model.selectedModule?.moduleID == "agents")
        model.reset()
        pointer.location = rightEar
        model.tap()
        #expect(model.selectedModule?.moduleID == "timer")
    }

    // Nothing waiting: the song comes first, as before; the keyboard shortcut and VoiceOver too.
    @Test func otherwiseTheSongComesFirst() {
        let pointer = Pointer()
        let (model, _, _, _) = makeModel(pointer)
        model.select("shelf")
        pointer.location = middle
        model.tap()
        #expect(model.selectedModule?.moduleID == "nowPlaying")
        model.reset()
        pointer.location = rightEar
        model.toggle()
        #expect(model.selectedModule?.moduleID == "nowPlaying")
    }

    // Answered: the song comes first again.
    @Test func onceAnsweredTheSongComesFirstAgain() {
        let pointer = Pointer()
        let (model, _, agents, _) = makeModel(pointer)
        agentNeedsYou(model, agents)
        pointer.location = middle
        model.tap()
        #expect(model.selectedModule?.moduleID == "agents")
        agents.isActive = false
        agents.wantsFocus = false
        agents.waitsForYou = false
        model.activityChanged()
        model.reset()
        model.tap()
        #expect(model.selectedModule?.moduleID == "nowPlaying")
    }

    // MARK: Who gets a spot

    // An agent that needs you takes the song's spot when the Timer holds the other one (the song waits).
    @Test func aWaitingAgentGetsASpotBeforeTheSong() {
        let pointer = Pointer()
        let (model, _, agents, timer) = makeModel(pointer)
        timerIsDone(model, timer)
        agentNeedsYou(model, agents)
        let ears = model.ears(layout: layout)
        #expect(ears.left?.moduleID == "agents")
        #expect(ears.right?.moduleID == "timer")
    }

    // A drop's temporary Shelf badge must not evict either waiting alert. Once the agent is answered,
    // the badge can use the free spot, while Done keeps the Timer's second spot.
    @Test(arguments: [false, true], [false, true])
    func waitingAlertsKeepTheirEarsDuringAShelfBadge(swapped: Bool, shelfRankedFirst: Bool) {
        let pointer = Pointer()
        let (model, _, agents, timer) = makeModel(pointer)
        let shelf = model.modules.first { $0.moduleID == "shelf" }!
        model.arrangement.swapsEarSides = swapped
        if shelfRankedFirst { model.arrangement.move("shelf", to: 0) }
        agentNeedsYou(model, agents)
        timerIsDone(model, timer)
        model.open(focusing: "shelf")
        model.closeThroughCompact(for: .seconds(1.5), showing: shelf)
        model.close()

        let waiting = model.ears(layout: layout)
        #expect(waiting.left?.moduleID == (swapped ? "timer" : "agents"))
        #expect(waiting.right?.moduleID == (swapped ? "agents" : "timer"))

        agents.isActive = false
        agents.waitsForYou = false
        agents.wantsFocus = false
        model.activityChanged()
        let answered = model.ears(layout: layout)
        #expect(answered.left?.moduleID == (swapped ? "timer" : "shelf"))
        #expect(answered.right?.moduleID == (swapped ? "shelf" : "timer"))
    }

    // With room for both, nobody changes sides: the song stays left, the agent right.
    @Test func withRoomTheSidesFollowTheOrder() {
        let pointer = Pointer()
        let (model, _, agents, _) = makeModel(pointer)
        agentNeedsYou(model, agents)
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "nowPlaying.main")
        #expect(ears.right?.id == "agents.main")
    }

    // Three active, none waiting: the top two by rank, as before.
    @Test func withoutWaitingTheTopTwoByRankStay() {
        let pointer = Pointer()
        let (model, _, agents, _) = makeModel(pointer)
        let shelf = model.modules.first { $0.moduleID == "shelf" } as? RankedModule
        shelf?.isActive = true
        agents.isActive = true
        model.activityChanged()
        let ears = model.ears(layout: layout)
        #expect(ears.left?.moduleID == "nowPlaying")
        #expect(ears.right?.moduleID == "shelf")
        // The agent starts waiting: it takes the Shelf's spot, the song keeps its side.
        agents.waitsForYou = true
        let waiting = model.ears(layout: layout)
        #expect(waiting.left?.moduleID == "nowPlaying")
        #expect(waiting.right?.moduleID == "agents")
    }
}
