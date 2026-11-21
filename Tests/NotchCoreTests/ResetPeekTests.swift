import AppKit
import SwiftUI
import Testing
@testable import NotchCore

@MainActor
private final class ResetTestStrip: NotchModule {
    var isActive = false
    let moduleID: String
    var onAttach: ((NotchViewModel) -> Void)?
    init(_ id: String) { moduleID = id }
    func attach(to notch: NotchViewModel?) { if let notch { onAttach?(notch) } }
    func expandedView(layout: NotchLayout) -> AnyView { AnyView(Text("Test")) }
    func peekView(layout: NotchLayout) -> AnyView? { AnyView(Text("Reset")) }
}

@MainActor
struct ResetPeekTests {
    func model(missionControl: @escaping @MainActor () -> Bool = { false }) -> NotchViewModel {
        NotchViewModel(layout: NotchLayout(geometry: .simulated(in: CGRect(x: -30_000, y: -30_000, width: 1512, height: 982))),
                       isMissionControlActive: missionControl)
    }

    @Test func aResetWaitsBehindAnAgentAlert() {
        let notch = model()
        let agent = ResetTestStrip("agents"), reset = ResetTestStrip("aiUsage")
        notch.modules = [agent, reset]
        #expect(notch.peek(agent, for: .seconds(10)))
        #expect(!notch.peek(reset, for: .seconds(4), waitingForOtherPeeks: true))
        #expect(notch.peekModuleID == "agents")
        notch.reset()
        #expect(notch.peek(reset, for: .seconds(4), waitingForOtherPeeks: true))
        notch.reset()
    }

    @Test func missionControlAndMissingWindowNeverConsumeANotice() {
        var missionControl = true
        let notch = model { missionControl }
        let reset = ResetTestStrip("aiUsage")
        notch.module = reset
        #expect(!notch.peek(reset, for: .seconds(4), revealOverFullScreen: true))
        missionControl = false
        notch.automaticPeeksAvailable = false
        #expect(!notch.peek(reset, for: .seconds(4), revealOverFullScreen: true))
        notch.automaticPeeksAvailable = true
        notch.open()
        #expect(!notch.peek(reset, for: .seconds(4), revealOverFullScreen: true))
        notch.close()
        #expect(notch.peek(reset, for: .seconds(4), revealOverFullScreen: true))
        notch.reset()
    }

    @Test func fullScreenStripSurvivesFitThenHidesAfterItsTimeout() async throws {
        let controller = NotchWindowController()
        controller.update(geometry: .simulated(in: CGRect(x: -30_000, y: -30_000, width: 1512, height: 982)))
        let reset = ResetTestStrip("aiUsage")
        controller.modules = [reset]
        controller.isHiddenForFullScreen = true
        let notch = try #require(controller.model)
        #expect(!notch.peek(reset, for: .milliseconds(50)))
        #expect(notch.peek(reset, for: .milliseconds(50), revealOverFullScreen: true))
        #expect(controller.isShowing)
        notch.fitWindow?(notch.state)
        #expect(controller.isShowing)
        try await settle(.seconds(2)) { !controller.isShowing }
        #expect(!controller.isShowing)
        #expect(!notch.layout.isPeeking)
        #expect(notch.peekModuleID == nil)
    }

    @Test func laterActivityDoesNotLeaveTheStripBusyForever() async throws {
        let notch = model()
        let strip = ResetTestStrip("aiUsage")
        notch.module = strip
        #expect(notch.peek(strip, for: .milliseconds(30)))
        for _ in 0..<100 where notch.layout.isPeeking { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!notch.layout.isPeeking)
        // A limit changes while the strip is sliding away: this starts a different state transition.
        strip.isActive = true
        notch.activityChanged()
        try await settle(.seconds(2)) { notch.peekModuleID == nil }
        #expect(notch.peekModuleID == nil)
        notch.reset()
    }

    @Test func aResetReadyDuringInitialAttachHasRoomInTheNewWindow() throws {
        let existingWindows = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let controller = NotchWindowController()
        let strip = ResetTestStrip("aiUsage")
        defer { strip.onAttach = nil }
        strip.onAttach = { notch in
            #expect(notch.peek(strip, for: .seconds(10), revealOverFullScreen: true))
        }
        controller.modules = [strip]
        controller.isHiddenForFullScreen = true
        controller.update(geometry: .simulated(in: CGRect(x: -30_000, y: -30_000, width: 1512, height: 982)))
        let notch = try #require(controller.model)
        let window = try #require(NSApplication.shared.windows.first { $0 is NotchPanel && !existingWindows.contains(ObjectIdentifier($0)) })
        #expect(notch.peekModuleID == "aiUsage")
        #expect(controller.isShowing)
        let expected = notch.layout.windowFrame(for: notch.state)
        #expect(window.frame.height >= expected.height)
        #expect(abs(window.frame.maxY - expected.maxY) <= 1)
        #expect(abs(window.frame.midX - expected.midX) <= 1)
        notch.reset()
        controller.isEnabled = false
    }

    @Test func suppressionAndDisplayRemovalBlockReveal() throws {
        let controller = NotchWindowController()
        controller.update(geometry: .simulated(in: CGRect(x: -30_000, y: -30_000, width: 1512, height: 982)))
        let reset = ResetTestStrip("aiUsage")
        controller.modules = [reset]
        let notch = try #require(controller.model)
        controller.isSuppressed = true
        #expect(!notch.peek(reset, for: .seconds(4), revealOverFullScreen: true))
        controller.isSuppressed = false
        controller.update(geometry: nil)
        #expect(!notch.peek(reset, for: .seconds(4), revealOverFullScreen: true))
        #expect(!controller.isShowing)
    }
}
