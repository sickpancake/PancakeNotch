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
        a.isActive = false
        ears = model.ears(layout: layout)
        #expect(ears.left?.id == "b.main")
        #expect(ears.right?.id == "c.main")
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
