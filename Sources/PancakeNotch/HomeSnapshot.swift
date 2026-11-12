import AgentsCore
import Foundation
import ModuleAgents
import ModuleKeepAwake
import ModuleNowPlaying
import ModuleShelf
import ModuleTimer
import NotchCore
import NowPlayingCore
import SwiftUI

/// Home's states for the off-screen notch sheet (`PANCAKENOTCH_SNAPSHOT`, ADR-0042): the default layout,
/// switched-off modules as ghosts, an empty Home, a second page, and every widget at every size with
/// data and empty.
@MainActor
enum HomeSnapshot {
    /// A fixed time, so the pictures don't change between runs.
    static let clock = Date(timeIntervalSince1970: 1_794_390_060) // a Wednesday morning

    static func pickerRows(layout: NotchLayout) -> [AnyView] {
        let choices: [[HomeWidgetKind]] = [[.nowPlaying, .stopwatch, .battery, .statistics, .allModules, .clock], []]
        return choices.map { kinds in
            let model = home(layout, .default, modules: live())
            let resolver = HomeWidgetResolver(modules: model.modules, arrangement: model.arrangement,
                                              extras: model.homeExtras)
            return HomeWidgetPickerSnapshot.view(model: model, kinds: kinds, resolver: resolver)
        }
    }

    static func models(layout: NotchLayout) -> [NotchViewModel] {
        let smalls: [HomeWidgetKind] = [.nowPlaying, .timer, .stopwatch, .agents, .aiUsage, .shelf, .keepAwake, .clock, .battery, .statistics]
        let mediums: [HomeWidgetKind] = smalls
        let larges: [HomeWidgetKind] = HomeWidgetKind.allCases.filter { $0.supports(.large) }
        return [
            home(layout, .default, modules: live(), intro: true),
            home(layout, .default, modules: [NowPlayingSnapshot.module(), ShelfSnapshot.module(itemCount: 3)]),
            home(layout, HomeLayout(), modules: live()),
            home(layout, twoPages, modules: live()) { $0.showHomePage(1) },
        ]
            + pages(of: smalls, size: .small).map { home(layout, $0, modules: live()) }
            + pages(of: smalls, size: .small).map { home(layout, $0, modules: empty()) }
            + pages(of: mediums, size: .medium).map { home(layout, $0, modules: live()) }
            + pages(of: mediums, size: .medium).map { home(layout, $0, modules: empty()) }
            + pages(of: larges, size: .large).map { home(layout, $0, modules: live()) }
            + pages(of: larges, size: .large).map { home(layout, $0, modules: empty()) }
    }

    private static func home(_ layout: NotchLayout, _ homeLayout: HomeLayout, modules: [any NotchModule],
                             intro: Bool = false, setUp: (NotchViewModel) -> Void = { _ in }) -> NotchViewModel {
        let settings = HomeSettings()
        settings.layout = homeLayout
        settings.hasSeenIntro = !intro
        let model = NotchViewModel(layout: layout, state: .expanded, home: settings)
        model.snapshotClock = clock
        model.homeExtras = HomeExtras.practice(home: settings)
        model.openAppPage = { _ in } // shows the empty Home's Customize button
        model.modules = modules
        model.toggleHome()
        setUp(model)
        return model
    }

    /// Widgets of one size, laid out page by page in reading order, one layout per page.
    private static func pages(of kinds: [HomeWidgetKind], size: HomeWidgetSize) -> [HomeLayout] {
        var layouts: [HomeLayout] = []
        var current = HomeLayout()
        for kind in kinds where kind.supports(size) {
            if case .success(let next) = current.adding(kind, size: size), next.placement(of: kind)?.slot.page == 0 {
                current = next
            } else {
                layouts.append(current)
                current = (try? HomeLayout().adding(kind, size: size).get()) ?? HomeLayout()
            }
        }
        if !current.isEmpty { layouts.append(current) }
        return layouts
    }

    private static var twoPages: HomeLayout {
        var layout = HomeLayout.default
        for kind in [HomeWidgetKind.stopwatch, .battery, .statistics] {
            if case .success(let next) = layout.adding(kind) { layout = next }
        }
        return layout
    }

    /// Every module with something to show: a song, a running timer and stopwatch with laps, agents at
    /// work, limits, files on the Shelf, Keep Awake on.
    private static func live() -> [any NotchModule] {
        let agents = AgentsModule(center: .practice())
        agents.isSnapshot = true
        let usage = AIUsageModule(center: .practice())
        usage.isSnapshot = true
        let timer = TimerSnapshot.module { center, clock in
            center.startTimer(seconds: 25 * 60)
            clock.advance(4 * 60 + 18)
            center.startStopwatch()
            clock.advance(83)
            center.lap()
            clock.advance(41)
            center.lap()
            clock.advance(12)
        }
        return [NowPlayingSnapshot.module(), ShelfSnapshot.module(itemCount: 7), agents, usage, timer,
                KeepAwakeSnapshot.module { center, _ in center.turnOn(.timed(3600)) }]
    }

    /// Every module with nothing to show yet.
    private static func empty() -> [any NotchModule] {
        let nowPlaying = NowPlayingModule(center: .snapshotNothingPlaying(lastPlayer: nil, seen: []))
        nowPlaying.isSnapshot = true
        let agents = AgentsModule(center: .practiceEmpty())
        agents.isSnapshot = true
        let usage = AIUsageModule(center: .practiceEmpty())
        usage.isSnapshot = true
        return [nowPlaying, ShelfSnapshot.module(itemCount: 0), agents, usage, TimerSnapshot.module(), KeepAwakeSnapshot.module()]
    }
}
