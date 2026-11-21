import AppKit
import SwiftUI
import Testing
@testable import NotchCore

@MainActor private final class LiveReviewModule: NotchModule {
    let moduleID: String
    var waitsForYou = false
    var isActive = false
    var wantsFocus = false
    var openedKind: HomeWidgetKind?
    init(_ id: String) { moduleID = id }
    func expandedView(layout: NotchLayout) -> AnyView { AnyView(EmptyView()) }
    func compactEars(layout: NotchLayout) -> CompactEars? { nil }
    func peekView(layout: NotchLayout) -> AnyView? { nil }
    func attach(to notch: NotchViewModel?) {}
    func openedFromHome(_ kind: HomeWidgetKind) { openedKind = kind }
}

/// Replays of the Home liveness model (verify-home-live) on the real view model: when widgets may tick,
/// where a click goes, and the opening setting against something waiting for you.
@MainActor struct HomeReplayLive {
    private func make() -> (NotchViewModel, LiveReviewModule) {
        let m = NotchViewModel(layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))),
                               pointerLocation: { CGPoint(x: -1000, y: -1000) }, isMissionControlActive: { false })
        let timer = LiveReviewModule("timer")
        m.modules = [timer]
        m.home.opening = .home
        m.home.layout = HomeLayout(placements: [
            HomePlacement(kind: .statistics, size: .small, slot: HomeSlot(page: 0, column: 0, row: 0)),
            HomePlacement(kind: .clock, size: .small, slot: HomeSlot(page: 1, column: 0, row: 0))])
        return (m, timer)
    }

    @Test func closeAndFullScreenStopHome() {
        let (m, _) = make()
        m.open(); #expect(m.homeIsLive(onPage: 0))
        m.isOnScreen = false; #expect(!m.homeIsLive(onPage: 0))
        m.isOnScreen = true; #expect(m.homeIsLive(onPage: 0))
        m.close(); #expect(!m.homeIsLive(onPage: 0)); #expect(!m.showsHome)
    }

    @Test func snapshotsNeverTick() {
        let (m, _) = make()
        m.snapshotClock = Date(timeIntervalSince1970: 0)
        m.open(); #expect(m.showsHome); #expect(!m.homeIsLive(onPage: 0))
    }

    /// The page sliding away stops at once; only the page that shows ticks.
    @Test func departingPageStops() {
        let (m, _) = make()
        m.open(); #expect(m.homeIsLive(onPage: 0)); #expect(!m.homeIsLive(onPage: 1))
        m.showHomePage(1)
        #expect(!m.homeIsLive(onPage: 0)); #expect(m.homeIsLive(onPage: 1))
    }

    /// A module page in front of Home: nothing on Home ticks.
    @Test func moduleInFrontStopsHome() {
        let (m, _) = make()
        m.open(); m.select("timer")
        #expect(!m.homeIsLive(onPage: 0))
    }

    /// Statistics reads once per opening: page changes keep the opening, coming back to Home starts a new one.
    @Test func eachOpeningIsANewVisit() {
        let (m, _) = make()
        m.open(); let first = m.homeVisit
        m.showHomePage(1); m.showHomePage(0); #expect(m.homeVisit == first)
        m.toggleHome(); m.toggleHome(); #expect(m.homeVisit == first + 1)
        m.close(); m.open(); #expect(m.homeVisit == first + 2)
    }

    @Test func waitingWinsAndReopenReturnsHome() {
        let (m, timer) = make()
        timer.waitsForYou = true
        m.open(); #expect(!m.showsHome); #expect(m.selectedModule?.moduleID == "timer")
        m.close(); m.open(); #expect(!m.showsHome)
        m.close(); timer.waitsForYou = false
        m.open(); #expect(m.showsHome)
        m.close(); m.home.opening = .lastModule
        m.open(); #expect(!m.showsHome)
    }

    @Test func attentionCloseStopsHome() async throws {
        let (m, timer) = make()
        m.attentionCloseDelay = .milliseconds(10)
        timer.waitsForYou = true
        m.openForAttention(focusing: "timer")
        #expect(m.state == .expanded); #expect(!m.showsHome)
        for _ in 0..<100 where m.state == .expanded { try await Task.sleep(for: .milliseconds(5)) }
        #expect(m.state != .expanded); #expect(!m.homeIsLive(onPage: 0))
    }

    @Test func routesAndNoOpCards() {
        let (m, timer) = make()
        m.open(); m.openFromHome(.stopwatch)
        #expect(!m.showsHome); #expect(timer.openedKind == .stopwatch)
        var statistics = 0
        m.openAppPage = { if case .statistics = $0 { statistics += 1 } }
        m.toggleHome(); m.openFromHome(.statistics)
        #expect(statistics == 1); #expect(m.showsHome)
        for kind: HomeWidgetKind in [.clock, .battery, .allModules] {
            #expect(!kind.opensFromHome)
            m.openFromHome(kind); #expect(m.showsHome)
        }
        #expect(HomeWidgetResolver(modules: [], arrangement: m.arrangement).isTurnedOff(.stopwatch))
        m.select("timer"); #expect(!m.showsHome) // All Modules' buttons use select.
    }
}
