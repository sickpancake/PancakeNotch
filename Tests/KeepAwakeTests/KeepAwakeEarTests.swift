import AppKit
import Foundation
import NotchCore
import SwiftUI
import Testing
@testable import KeepAwakeCore
@testable import ModuleKeepAwake

/// The real Keep Awake module in the spots beside the notch, as Help ("What shows beside the notch") and the
/// Modules page describe it: it takes the first spot ahead of better-ranked modules, gives it up when off, and
/// steps aside for something waiting for you while the second spot is taken (ADR-0011's ear rules).
@MainActor
struct KeepAwakeEarTests {
    /// A module with an ear that the test switches on and off.
    final class StandIn: NotchModule {
        let moduleID: String
        var isActive = false
        var waitsForYou = false
        var prefersSecondEar = false
        init(_ id: String) { moduleID = id }
        var title: String { moduleID }
        var symbol: String { "circle" }
        var menuStatus: String? { nil }
        func attach(to notch: NotchViewModel?) {}
        func expandedView(layout: NotchLayout) -> AnyView { AnyView(EmptyView()) }
        func compactEars(layout: NotchLayout) -> CompactEars? { CompactEars(main: AnyView(EmptyView())) }
        func peekView(layout: NotchLayout) -> AnyView? { nil }
    }

    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
    let center: KeepAwakeCenter
    let keepAwake: KeepAwakeModule
    let notch: NotchViewModel

    init() {
        let name = "KeepAwakeEar-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let clock = TestClock()
        center = KeepAwakeCenter(settings: KeepAwakeSettings(defaults: defaults), defaults: defaults,
                                 holder: PretendPowerHold(), now: { clock.now },
                                 power: { PowerState(onBattery: false, percent: 100) },
                                 bootTime: { Date(timeIntervalSinceReferenceDate: 899_000_000) })
        keepAwake = KeepAwakeModule(center: center)
        notch = NotchViewModel(layout: layout, isMissionControlActive: { false })
    }

    /// Ranks the stand-ins first and Keep Awake last.
    func show(_ others: [StandIn]) {
        notch.modules = others + [keepAwake]
        notch.arrangement.order = others.map(\.moduleID) + [keepAwake.moduleID]
    }

    @Test func itAsksForTheFirstSpotUnderTheIDTheModulesPageUses() {
        #expect(keepAwake.prefersFirstEar)
        #expect(!keepAwake.prefersSecondEar)
        // The Modules page's spot labels and picture look for this ID.
        #expect(keepAwake.moduleID == "keepAwake")
    }

    @Test func onItTakesTheFirstSpotAheadOfABetterRankedModule() {
        let music = StandIn("music")
        music.isActive = true
        show([music])
        center.turnOn(.untilStopped)
        #expect(keepAwake.isActive)
        var ears = notch.ears(layout: layout)
        #expect(ears.left?.id == "keepAwake.main")
        #expect(ears.right?.id == "music.main")
        notch.arrangement.swapsEarSides = true
        ears = notch.ears(layout: layout)
        #expect(ears.left?.id == "music.main")
        #expect(ears.right?.id == "keepAwake.main")
    }

    @Test func offItGivesTheSpotBack() {
        let music = StandIn("music")
        music.isActive = true
        show([music])
        center.turnOn(.untilStopped)
        center.turnOff()
        #expect(!keepAwake.isActive)
        let ears = notch.ears(layout: layout)
        #expect(ears.left?.id == "music.main")
        #expect(ears.right == nil)
    }

    @Test func somethingWaitingForYouBorrowsTheFirstSpotWhileTheSecondIsTaken() {
        let timer = StandIn("timer"), agent = StandIn("agent")
        timer.isActive = true; timer.prefersSecondEar = true
        agent.isActive = true
        show([timer, agent])
        center.turnOn(.untilStopped)
        var ears = notch.ears(layout: layout)
        #expect(ears.left?.id == "keepAwake.main")
        #expect(ears.right?.id == "timer.main")
        agent.waitsForYou = true
        ears = notch.ears(layout: layout)
        #expect(ears.left?.id == "agent.main")
        #expect(ears.right?.id == "timer.main")
        agent.waitsForYou = false
        ears = notch.ears(layout: layout)
        #expect(ears.left?.id == "keepAwake.main")
    }
}
