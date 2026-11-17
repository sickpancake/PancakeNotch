import AppKit
import SwiftUI
import Testing
@testable import NotchCore

@MainActor
struct OpeningUsabilityVerification {
    final class Module: NotchModule {
        let moduleID: String
        var isActive = false
        var wantsFocus = false
        var waitsForYou = false
        var isIdleForOpening = false
        var earConfiguration: CompactEarConfiguration? = .init()
        init(_ id: String) { moduleID = id }
        func attach(to notch: NotchViewModel?) {}
        func expandedView(layout: NotchLayout) -> AnyView { AnyView(EmptyView()) }
        func compactEars(layout: NotchLayout) -> CompactEars? {
            guard let earConfiguration else { return nil }
            return .init(main: AnyView(EmptyView()), extra: earConfiguration.hasExtra ? AnyView(EmptyView()) : nil)
        }
        func peekView(layout: NotchLayout) -> AnyView? { AnyView(EmptyView()) }
    }

    final class Pointer { var point = CGPoint(x: 5, y: 5) }
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    func make(_ pointer: Pointer) -> NotchViewModel {
        let model = NotchViewModel(layout: layout, pointerLocation: { pointer.point }, isMissionControlActive: { false })
        model.snapshotClock = Date(timeIntervalSince1970: 0)
        return model
    }

    @Test(arguments: EarVerificationInputs.orders(["nowPlaying", "agents", "timer"]))
    func openingPriorityTable(order: [String]) async {
        var checked = 0
        for musicState in 0..<3 { // playing, paused, empty
            for waitingMask in 0..<4 {
                for navigation in NotchNavigation.allCases {
                    for prefersHome in [false, true] {
                        for last in order {
                            for target in [nil, "nowPlaying", "agents", "timer", "disabled"] {
                                let model = make(Pointer())
                                let modules = order.map(Module.init)
                                let music = modules.first { $0.moduleID == "nowPlaying" }!
                                music.wantsFocus = musicState == 0
                                music.isIdleForOpening = musicState != 0
                                for module in modules where module.moduleID != "nowPlaying" {
                                    module.waitsForYou = waitingMask & (module.moduleID == "agents" ? 1 : 2) != 0
                                }
                                model.modules = modules
                                model.arrangement.order = order
                                model.arrangement.navigation = navigation
                                model.home.opening = prefersHome ? .home : .lastModule
                                model.select(last)
                                let homeAvailable = navigation != .tabs
                                let expected: String
                                if let target, order.contains(target) { expected = target }
                                else if let waiting = modules.first(where: \.waitsForYou) { expected = waiting.moduleID }
                                else if homeAvailable && prefersHome { expected = "home" }
                                else if musicState == 0 { expected = "nowPlaying" }
                                else if homeAvailable && last == "nowPlaying" { expected = "home" }
                                else { expected = last }
                                model.open(focusing: target)
                                let actual = model.showsHome ? "home" : model.selectedModule?.moduleID
                                model.reset()
                                if actual != expected {
                                    Issue.record("OPENING_DESTINATION: order=\(order), music=\(musicState), waiting=\(waitingMask), navigation=\(navigation), home=\(prefersHome), last=\(last), target=\(target ?? "automatic"); expected \(expected), got \(actual ?? "none")")
                                    return
                                }
                                checked += 1
                                if checked.isMultiple(of: 32) { await Task.yield() }
                            }
                        }
                    }
                }
            }
        }
    }

    enum Event: String, CaseIterable { case agentWaits, timerDone, shelfBadge, swapSides, rerank, removeAgent, songStrip }
    static let traces: [[Event]] = {
        var all: [[Event]] = [[]], frontier: [[Event]] = [[]]
        for _ in 0..<3 {
            frontier = frontier.flatMap { trace in Event.allCases.map { trace + [$0] } }
            all += frontier
        }
        return all
    }()

    @Test func eventOrdersKeepPointingAndOpeningInAgreement() async {
        var checked = 0
        for trace in Self.traces {
            for probe in 0..<4 {
                let pointer = Pointer()
                let notch = make(pointer)
                let modules = EarVerificationInputs.ids.map(Module.init)
                let byID = Dictionary(uniqueKeysWithValues: modules.map { ($0.moduleID, $0) })
                for module in modules { module.isActive = !["shelf", "aiUsage"].contains(module.moduleID) }
                byID["nowPlaying"]!.wantsFocus = true
                byID["nowPlaying"]!.earConfiguration = .init(hasExtra: true)
                byID["timer"]!.earConfiguration = .init(placement: .second)
                byID["keepAwake"]!.earConfiguration = .init(placement: .first)
                notch.modules = modules
                for event in trace {
                    switch event {
                    case .agentWaits: byID["agents"]!.waitsForYou = true
                    case .timerDone: byID["timer"]!.waitsForYou = true
                    case .shelfBadge:
                        notch.open(focusing: "shelf")
                        notch.closeThroughCompact(for: .seconds(300), showing: byID["shelf"]!)
                        notch.close()
                    case .swapSides: notch.arrangement.swapsEarSides.toggle()
                    case .rerank: notch.arrangement.order.reverse()
                    case .removeAgent: notch.modules.removeAll { $0.moduleID == "agents" }
                    case .songStrip: _ = notch.peek(byID["nowPlaying"]!, for: .seconds(300))
                    }
                    notch.activityChanged()
                }
                let ears = notch.ears(layout: notch.layout)
                let expectedOwner: String?
                let rect = layout.geometry.notchRect
                switch probe {
                case 0: pointer.point = CGPoint(x: rect.minX - 10, y: rect.maxY - 5); expectedOwner = ears.left?.moduleID
                case 1: pointer.point = CGPoint(x: rect.maxX + 10, y: rect.maxY - 5); expectedOwner = ears.right?.moduleID
                case 2: pointer.point = CGPoint(x: rect.midX, y: rect.maxY - 5); expectedOwner = nil
                default:
                    guard notch.layout.isPeeking else { notch.reset(); continue }
                    pointer.point = CGPoint(x: rect.maxX + 10, y: rect.maxY - layout.geometry.compactHeight - 5)
                    expectedOwner = notch.peekModuleID
                }
                let defaultOwner = notch.rankedModules.first(where: \.waitsForYou)?.moduleID ?? "nowPlaying"
                let targeted = notch.moduleUnderPointer()
                notch.tap()
                let opened = notch.showsHome ? "home" : notch.selectedModule?.moduleID
                notch.reset()
                if targeted != expectedOwner || opened != (expectedOwner ?? defaultOwner) {
                    Issue.record("POINTED_OWNER: trace=\(trace.map(\.rawValue)), probe=\(probe); drawn=\(expectedOwner ?? "middle"), targeted=\(targeted ?? "middle"), opened=\(opened ?? "none"), automatic=\(defaultOwner)")
                    return
                }
                checked += 1
                if checked.isMultiple(of: 16) { await Task.yield() }
            }
        }
    }
}
