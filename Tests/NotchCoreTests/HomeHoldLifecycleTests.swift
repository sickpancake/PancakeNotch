import AppKit
import Testing
@testable import NotchCore

@MainActor struct HomeHoldLifecycleTests {
    @Test func repeatedHoldKeepsPageAndDoesNotEditLayout() {
        let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        let model = NotchViewModel(layout: layout)
        model.snapshotClock = Date(timeIntervalSince1970: 0)
        model.home.opening = .home
        model.home.layout = HomeLayout(placements: [
            .init(kind: .clock, size: .small, slot: .init(page: 0, column: 0, row: 0)),
            .init(kind: .battery, size: .small, slot: .init(page: 1, column: 0, row: 0))
        ])
        model.open()
        model.showHomePage(1)
        let saved = model.home.layout
        model.beginHomeEditing()
        model.beginHomeEditing()
        model.openFromHome(.clock)
        #expect(model.isEditingHome && model.showsHome && model.homePage == 1)
        #expect(model.home.layout == saved)
        model.tap()
        #expect(!model.isEditingHome && model.showsHome && model.state == .expanded)
        #expect(model.home.layout == saved)
    }
}
