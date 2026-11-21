import Testing
@testable import NotchCore

struct HomeScrollMotionTests {
    @Test func fingersAndNearestPage() {
        var m = HomeScrollMotion()
        m.begin(page: 1, time: 0)
        m.move(y: -40, x: 0, time: 0.2)
        #expect(m.position(height: 100, count: 3) == 1.4)
        #expect(m.target(height: 100, count: 3, time: 0.4) == 1)
        m.move(y: -20, x: 0, time: 0.5)
        #expect(m.target(height: 100, count: 3, time: 0.7) == 2)
    }
    @Test func flickBoundariesAndReversal() {
        var m = HomeScrollMotion()
        m.begin(page: 0, time: 0)
        m.move(y: -12, x: 0, time: 0.01)
        #expect(m.target(height: 100, count: 3, time: 0.02) == 1)
        m.move(y: 8, x: 0, time: 0.02)
        #expect(m.target(height: 100, count: 3, time: 0.03) == 0)
        m.begin(page: 0, time: 0)
        m.move(y: 100, x: 0, time: 1)
        #expect(m.position(height: 100, count: 3) < 0)
        #expect(m.position(height: 100, count: 3) > -0.05)
        #expect(m.target(height: 100, count: 3, time: 1) == 0)
        m.begin(page: 1, time: 0)
        m.move(y: -1000, x: 0, time: 1)
        #expect(m.target(height: 100, count: 3, time: 1) == 2)
    }
    @Test func horizontalAndWheel() {
        var m = HomeScrollMotion()
        m.begin(page: 1, time: 0)
        m.move(y: 4, x: 30, time: 0.1)
        m.move(y: 80, x: 0, time: 0.2)
        #expect(!m.vertical)
        #expect(m.position(height: 100, count: 3) == 1)
        var wheel = HomePageScrollTracker()
        #expect(wheel.handle(phase: .other, deltaY: -1, deltaX: 0, isPrecise: false, time: 0) == 1)
        #expect(wheel.handle(phase: .other, deltaY: -1, deltaX: 0, isPrecise: false, time: 0.1) == nil)
        #expect(wheel.handle(phase: .other, deltaY: 1, deltaX: 0, isPrecise: false, time: 0.4) == -1)
    }
}

extension HomeReplayNotch {
    @Test func dragTargetMomentumAndTeardown() {
        let m = model()
        m.home.layout = HomeLayout(placements: [
            HomePlacement(kind: .clock, size: .small, slot: .init(page: 0, column: 0, row: 0)),
            HomePlacement(kind: .battery, size: .small, slot: .init(page: 1, column: 0, row: 0))
        ])
        m.open()
        m.handleHomePreciseScroll(phase: .began, deltaY: -10, deltaX: 0, time: 1)
        #expect(m.homeRenderedPages.count == 2)
        m.handleHomePreciseScroll(phase: .changed, deltaY: -80, deltaX: 0, time: 1.1)
        #expect(m.homePage == 1)
        #expect(!m.homeIsLive(onPage: 0))
        #expect(m.homeIsLive(onPage: 1))
        m.handleHomePreciseScroll(phase: .ended, deltaY: 0, deltaX: 0, time: 1.11)
        m.handleHomePreciseScroll(phase: .other, deltaY: -100, deltaX: 0, time: 1.12, momentum: true)
        #expect(m.homePage == 1)
        #expect((m.homeScrollPosition ?? Double(m.homePage)) == 1)
        m.toggleHome()
        #expect(m.homeScrollPosition == nil)
        #expect(!m.homeIsLive(onPage: 1))
    }
}
