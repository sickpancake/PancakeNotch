import AppKit
import SwiftUI
import Testing
@testable import NotchCore

/// A module that asks for the first ear while active, like Keep Awake (ADR-0041).
@MainActor
final class FirstEarModule: NotchModule {
    let moduleID = "keepAwake"
    var isActive = true
    var prefersFirstEar = true

    func attach(to notch: NotchViewModel?) {}
    func expandedView(layout: NotchLayout) -> AnyView { AnyView(EmptyView()) }
    func compactEars(layout: NotchLayout) -> CompactEars? { CompactEars(main: AnyView(EmptyView())) }
    func peekView(layout: NotchLayout) -> AnyView? { AnyView(EmptyView()) }
}

/// A module with something waiting for you, like an agent's question.
@MainActor
final class WaitingEarModule: NotchModule {
    let moduleID = "agents"
    var isActive = true
    var waitsForYou = true

    func attach(to notch: NotchViewModel?) {}
    func expandedView(layout: NotchLayout) -> AnyView { AnyView(EmptyView()) }
    func compactEars(layout: NotchLayout) -> CompactEars? { CompactEars(main: AnyView(EmptyView())) }
}

@MainActor
struct FirstEarTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    func makeModel() -> (NotchViewModel, RankedModule, SecondEarModule, FirstEarModule) {
        let model = NotchViewModel(
            layout: layout,
            behavior: NotchBehavior(openDelay: .milliseconds(10), closeDelay: .milliseconds(10)),
            pointerLocation: { CGPoint(x: 5, y: 5) },
            isMissionControlActive: { false }
        )
        let music = RankedModule("nowPlaying")
        music.hasExtraEar = true
        let timer = SecondEarModule()
        timer.isActive = false
        let awake = FirstEarModule()
        model.modules = [music, timer, awake]
        return (model, music, timer, awake)
    }

    @Test func takesTheFirstEarAndTheTopModuleMovesToTheSecond() {
        let (model, music, _, _) = makeModel()
        music.isActive = true
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "keepAwake.main")
        #expect(ears.right?.id == "nowPlaying.main")
        model.arrangement.swapsEarSides = true
        #expect(model.ears(layout: layout).right?.id == "keepAwake.main")
    }

    @Test func theTimerKeepsTheSecondEar() {
        let (model, music, timer, _) = makeModel()
        music.isActive = true
        timer.isActive = true
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "keepAwake.main")
        #expect(ears.right?.id == "timer.main")
    }

    @Test func aloneItTakesOnlyTheFirstEar() {
        let (model, _, _, _) = makeModel()
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "keepAwake.main")
        #expect(ears.right == nil)
    }

    @Test func inactiveItLeavesTheEarsAsTheyWere() {
        let (model, music, timer, awake) = makeModel()
        awake.isActive = false
        music.isActive = true
        timer.isActive = true
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "nowPlaying.main")
        #expect(ears.right?.id == "timer.main")
    }

    /// An agent waiting beside Keep Awake: Keep Awake keeps #1, the agent takes #2 over the top module.
    @Test func aWaitingAgentTakesTheSecondEar() {
        let (model, music, _, awake) = makeModel()
        music.isActive = true
        let agents = WaitingEarModule()
        model.modules = [music, agents, awake]
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "keepAwake.main")
        #expect(ears.right?.id == "agents.main")
    }

    /// With the Timer on #2, an agent waiting for you takes #1 from Keep Awake: what needs you shows.
    @Test func whatWaitsForYouOutranksKeepAwakeWhenTheTimerHoldsTheSecondEar() {
        let (model, _, timer, awake) = makeModel()
        timer.isActive = true
        let agents = WaitingEarModule()
        model.modules = [timer, agents, awake]
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "agents.main")
        #expect(ears.right?.id == "timer.main")
        agents.waitsForYou = false
        model.activityChanged()
        #expect(model.ears(layout: layout).left?.id == "keepAwake.main")
    }

    /// A Shelf badge must not hide either alert, or displace Keep Awake after the agent is answered.
    @Test(arguments: [false, true])
    func aShelfBadgeWaitsForAlertsAndKeepAwake(swapped: Bool) {
        let (model, music, _, awake) = makeModel()
        music.isActive = true
        let shelf = RankedModule("shelf")
        let agents = WaitingEarModule()
        let timer = WaitingModule("timer")
        timer.isActive = true
        timer.waitsForYou = true
        timer.prefersSecondEar = true
        model.modules = [music, shelf, agents, timer, awake]
        model.arrangement.swapsEarSides = swapped
        model.open(focusing: "shelf")
        model.closeThroughCompact(for: .seconds(1.5), showing: shelf)
        model.close()

        let waiting = model.ears(layout: layout)
        #expect(waiting.left?.moduleID == (swapped ? "timer" : "agents"))
        #expect(waiting.right?.moduleID == (swapped ? "agents" : "timer"))

        agents.isActive = false
        agents.waitsForYou = false
        model.activityChanged()
        let answered = model.ears(layout: layout)
        #expect(answered.left?.moduleID == (swapped ? "timer" : "keepAwake"))
        #expect(answered.right?.moduleID == (swapped ? "keepAwake" : "timer"))

        awake.isActive = false
        model.activityChanged()
        let roomForBadge = model.ears(layout: layout)
        #expect(roomForBadge.left?.moduleID == (swapped ? "timer" : "shelf"))
        #expect(roomForBadge.right?.moduleID == (swapped ? "shelf" : "timer"))
    }
}
