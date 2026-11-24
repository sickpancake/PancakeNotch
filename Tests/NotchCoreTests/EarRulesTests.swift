import AppKit
import SwiftUI
import Testing
@testable import NotchCore

/// The ear rules that aren't pinned elsewhere (ADR-0011's "Ear rules"; NotchModulesTests and
/// SecondEarTests hold the rest). Everything here runs off-screen with stand-in modules.
@MainActor
struct EarRulesTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    /// Modules "a", "b", "c" ranked in that order, none active.
    func makeModel() -> (NotchViewModel, RankedModule, RankedModule, RankedModule) {
        let model = NotchViewModel(
            layout: layout,
            state: .closed,
            pointerLocation: { CGPoint(x: 756, y: 300) },
            isMissionControlActive: { false }
        )
        let a = RankedModule("a"), b = RankedModule("b"), c = RankedModule("c")
        model.modules = [a, b, c]
        model.arrangement.order = ["a", "b", "c"]
        return (model, a, b, c)
    }

    @Test func aThirdActiveModuleWaitsForAFreeSpot() {
        let (model, a, b, c) = makeModel()
        a.isActive = true; b.isActive = true; c.isActive = true
        var ears = model.ears(layout: layout)
        #expect(ears.left?.id == "a.main")
        #expect(ears.right?.id == "b.main")
        // The "+n" count counts what didn't fit.
        #expect(model.earOverflow == .init(side: .left, count: 1))
        a.isActive = false
        ears = model.ears(layout: layout)
        #expect(ears.left?.id == "b.main")
        #expect(ears.right?.id == "c.main")
        #expect(model.earOverflow == nil)
    }

    @Test func theOverflowChipTucksUnderTheSideTheDisplacedWanted() {
        let (model, a, b, _) = makeModel()
        let timer = SecondEarModule()
        model.modules.append(timer)
        a.isActive = true; b.isActive = true
        // "timer" claims the second spot, so "b" is displaced from the first: the count shows in the left ear.
        #expect(model.earOverflow == .init(side: .left, count: 1))
        // A displaced second-spot module puts it under the right ear.
        let timer2 = SecondEarModule("timer2")
        model.modules.append(timer2)
        b.isActive = false
        #expect(model.earOverflow == .init(side: .right, count: 1))
        // Swap sides flips the count with the ears.
        model.arrangement.swapsEarSides = true
        #expect(model.earOverflow == .init(side: .left, count: 1))
    }

    @Test func waitingAlertsKeepTheirSpotAndOverflowCountsTheRest() {
        let (model, a, b, _) = makeModel()
        let agents = WaitingEarModule()
        model.modules.append(agents)
        a.isActive = true; b.isActive = true
        // The waiting module wins a spot first; the loser counts toward the "+n".
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "a.main")
        #expect(ears.right?.id == "agents.main")
        #expect(model.earOverflow == .init(side: .left, count: 1))
    }

    /// A moving pointer for the model's `pointerLocation` closure.
    final class Pointer { var point = CGPoint.zero }

    @Test func tappingTheChipOpensHomeOrTheBestDisplacedModule() {
        let pointer = Pointer()
        let model = NotchViewModel(layout: layout, state: .compact,
            pointerLocation: { pointer.point }, isMissionControlActive: { false })
        let a = RankedModule("a"), b = RankedModule("b"), c = RankedModule("c")
        a.isActive = true; b.isActive = true; c.isActive = true
        model.modules = [a, b, c]
        model.arrangement.order = ["a", "b", "c"]
        let notch = layout.geometry.notchRect
        // The count is the strip at the outer edge of the ear that shows it, inside the outline.
        pointer.point = CGPoint(x: notch.minX - layout.compactEarWidth + 4, y: notch.maxY - 5)
        #expect(model.pointerOverEarOverflow())
        model.tap()
        #expect(model.showsHome)
        model.reset()
        // With tabs-only navigation it opens on the best-ranked displaced module instead.
        model.arrangement.navigation = .tabs
        model.tap()
        #expect(model.selectedModule?.moduleID == "c")
        // The rest of the ear still opens its own module, and nothing below the ear belongs to the notch.
        pointer.point = CGPoint(x: notch.minX - layout.compactEarWidth + 4, y: notch.maxY - layout.geometry.compactHeight - 5)
        #expect(!model.pointerOverEarOverflow())
        pointer.point = CGPoint(x: notch.minX - 10, y: notch.maxY - 5)
        #expect(!model.pointerOverEarOverflow())
        model.reset()
        model.tap()
        #expect(model.selectedModule?.moduleID == "a")
    }

    @Test func anInactiveModuleNeverShowsWhileAnotherIsActive() {
        let (model, a, b, _) = makeModel()
        // "a" is the current module but has nothing to show.
        #expect(model.selectedModule?.moduleID == "a")
        b.isActive = true
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "b.main")
        #expect(ears.right == nil)
    }

    @Test func withTwoShowingTheExtraViewIsDropped() {
        let (model, a, b, _) = makeModel()
        a.isActive = true; a.hasExtraEar = true
        b.isActive = true
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "a.main")
        #expect(ears.right?.id == "b.main")
    }

    @Test func swapSidesFlipsALoneModulesTwoViews() {
        let (model, a, _, _) = makeModel()
        a.isActive = true; a.hasExtraEar = true
        model.arrangement.swapsEarSides = true
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "a.extra")
        #expect(ears.right?.id == "a.main")
    }

    @Test func swapSidesMovesALoneSecondSpotModuleLeft() {
        let (model, _, _, _) = makeModel()
        let timer = SecondEarModule()
        model.modules.append(timer)
        model.arrangement.swapsEarSides = true
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "timer.main")
        #expect(ears.right == nil)
    }

    @Test func theSecondSpotModuleAndTheTopModuleShareWhateverTheirRanks() {
        let (model, a, b, _) = makeModel()
        let timer = SecondEarModule()
        model.modules.append(timer)
        model.arrangement.move("timer", to: 0)
        a.isActive = true; b.isActive = true
        let ears = model.ears(layout: layout)
        // The best-ranked other module keeps #1; "b" waits.
        #expect(ears.left?.id == "a.main")
        #expect(ears.right?.id == "timer.main")
    }

    /// The after-drop count borrows #2 only next to another module; on its own it shows in #1.
    @Test func aBriefModuleAloneTakesTheFirstSpot() {
        let model = NotchViewModel(layout: layout, state: .expanded, pointerLocation: { CGPoint(x: 5, y: 5) }, isMissionControlActive: { false })
        let shelf = RankedModule("shelf")
        let other = RankedModule("other")
        model.modules = [other, shelf]
        model.closeThroughCompact(for: .seconds(5), showing: shelf)
        model.close()
        #expect(model.state == .compact)
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "shelf.main")
        #expect(ears.right == nil)
    }

    @Test func switchedOffModulesNeverGetASpot() {
        let (model, a, b, _) = makeModel()
        a.isActive = true; b.isActive = true
        // Switching a module off removes it from the notch.
        model.modules.removeAll { $0.moduleID == "a" }
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "b.main")
        #expect(ears.right == nil)
    }
}

@MainActor
struct EarOverflowCountTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    @Test func theCountStaysInsideTheOutline() {
        let model = NotchViewModel(layout: layout, state: .compact,
            pointerLocation: { .zero }, isMissionControlActive: { false })
        let a = RankedModule("a"), b = RankedModule("b"), c = RankedModule("c")
        a.isActive = true; b.isActive = true; c.isActive = true
        model.modules = [a, b, c]
        model.arrangement.order = ["a", "b", "c"]
        #expect(model.earOverflow != nil)
        // No strip hangs below the ears any more: the window is just the outline.
        #expect(model.windowFrame(for: .compact) == layout.windowFrame(for: .compact))
        // The reserve only narrows a module's content, never the outline.
        var reserved = layout
        reserved.compactEarReserve = NotchLayout.earCountWidth
        #expect(reserved.bodySize(for: .compact) == layout.bodySize(for: .compact))
        #expect(reserved.compactEarContentWidth == layout.compactEarWidth - NotchLayout.earCountWidth)
    }
}
