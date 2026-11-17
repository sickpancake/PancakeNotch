import AppKit
import SwiftUI
import Testing
@testable import NotchCore

@MainActor
struct EarRenderingTests {
    final class Module: NotchModule {
        let moduleID: String
        var isActive = true
        var earConfiguration: CompactEarConfiguration?
        var builds = 0

        init(_ id: String, configuration: CompactEarConfiguration? = CompactEarConfiguration()) {
            moduleID = id
            earConfiguration = configuration
        }
        func attach(to notch: NotchViewModel?) {}
        func expandedView(layout: NotchLayout) -> AnyView { AnyView(EmptyView()) }
        func compactEars(layout: NotchLayout) -> CompactEars? {
            builds += 1
            guard let earConfiguration else { return nil }
            return CompactEars(main: AnyView(EmptyView()),
                extra: earConfiguration.hasExtra ? AnyView(EmptyView()) : nil)
        }
    }

    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    @Test func targetingDoesNotBuildViewsAndRenderingBuildsOnlyOwners() {
        let point = CGPoint(x: layout.geometry.notchRect.maxX + 10, y: layout.geometry.notchRect.maxY - 5)
        let model = NotchViewModel(layout: layout, pointerLocation: { point }, isMissionControlActive: { false })
        let noEars = Module("noEars", configuration: nil)
        let a = Module("a"), b = Module("b"), c = Module("c")
        model.modules = [noEars, a, b, c]
        model.arrangement.order = ["noEars", "a", "b", "c"]
        #expect(model.moduleUnderPointer() == "b")
        #expect(([noEars.builds, a.builds, b.builds, c.builds] as [Int]) == [0, 0, 0, 0])
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "a.main")
        #expect(ears.right?.id == "b.main")
        #expect(([noEars.builds, a.builds, b.builds, c.builds] as [Int]) == [0, 1, 1, 0])
        // A fresh decision follows rank changes immediately; there is no allocation cache to go stale.
        model.arrangement.order = ["c", "a", "b", "noEars"]
        model.arrangement.swapsEarSides = true
        #expect(model.moduleUnderPointer() == "c")
        model.tap()
        #expect(model.selectedModule?.moduleID == "c")
        #expect(([noEars.builds, a.builds, b.builds, c.builds] as [Int]) == [0, 1, 1, 0])
    }

    @Test func twoViewsFromOneOwnerAreBuiltOnce() {
        let model = NotchViewModel(layout: layout)
        let music = Module("music", configuration: CompactEarConfiguration(hasExtra: true))
        model.modules = [music]
        model.arrangement.swapsEarSides = true
        let ears = model.ears(layout: layout)
        #expect(ears.left?.id == "music.extra")
        #expect(ears.right?.id == "music.main")
        #expect(music.builds == 1)
    }
}
