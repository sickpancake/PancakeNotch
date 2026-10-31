@testable import AgentsCore
import AppKit
import Foundation
import NotchCore
import Testing
@testable import ModuleAgents

@MainActor
struct AIUsageModuleTests {
    func makeModule(peeks: Bool = true) -> (AIUsageModule, NotchViewModel) {
        let module = AIUsageModule(center: .practice(), peeks: peeks)
        let notch = NotchViewModel(
            layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))),
            state: .expanded,
            pointerLocation: { CGPoint(x: 756, y: 100) }
        )
        notch.module = module
        return (module, notch)
    }

    @Test func theSymbolsExist() {
        let module = AIUsageModule(center: .practice())
        #expect(NSImage(systemSymbolName: module.symbol, accessibilityDescription: nil) != nil)
        #expect(NSImage(systemSymbolName: AgentsModule(center: .practice()).symbol, accessibilityDescription: nil) != nil)
        for tool in AgentTool.allCases {
            #expect(NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil) != nil)
        }
    }

    @Test func theMenuLineFollowsTheChosenAccount() {
        let (module, _) = makeModule()
        // The practice center starts on the personal account, whose session has 63% left.
        #expect(module.menuStatus == "Session 63% left")
        module.center.selection = .all
        #expect(module.menuStatus == "All accounts")
    }

    @Test func anAccountUnderTenPercentTakesAnEar() {
        let (module, _) = makeModule()
        #expect(module.isActive)
        #expect(module.accessibilityStatus?.contains("Claude Max 2") == true)
    }

    @Test func theMenuHoldsTheNotchOpenUntilItCloses() {
        let (module, _) = makeModule()
        #expect(!module.holdsOpen)
        module.openMenu()
        #expect(module.holdsOpen)
        module.choose(.all)
        #expect(!module.holdsOpen)
        #expect(module.center.selection == .all)
    }

    @Test func leavingTheModuleClosesTheMenu() {
        let (module, _) = makeModule()
        module.openMenu()
        module.userSwitchedAway()
        #expect(!module.holdsOpen)
        module.openMenu()
        module.notchDidClose()
        #expect(!module.holdsOpen)
    }

    @Test func theAccountMenuCanBeUsedWithTheKeyboard() throws {
        let (module, notch) = makeModule()
        _ = notch
        func key(_ code: UInt16) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                          isARepeat: false, keyCode: code))
        }
        module.openMenu()
        let initial = module.focusedAccount
        #expect(module.handleKey(try key(125)))
        #expect(module.focusedAccount != initial)
        let choice = module.focusedAccount
        #expect(module.handleKey(try key(36)))
        #expect(module.center.selection == choice)
        #expect(!module.holdsOpen)
        module.openMenu()
        #expect(module.handleKey(try key(53)))
        #expect(!module.holdsOpen)
    }

    @Test func aCopyThatDoesNotPeekLeavesTheCenterAlone() {
        let (peeking, _) = makeModule()
        #expect(peeking.center.onNearLimit != nil)
        let (quiet, _) = makeModule(peeks: false)
        #expect(quiet.center.onNearLimit == nil)
    }
}

@MainActor
struct ResetModuleDeliveryTests {
    @Test func pendingResetWaitsForAgentThenStartsAndSwitchOffDismissesIt() async throws {
        let defaults = UserDefaults(suiteName: "ResetModule.\(UUID().uuidString)")!
        defaults.set(true, forKey: "aiUsage.enabled")
        let settings = AgentsSettings(defaults: defaults)
        settings.warnsNearLimit = false
        let center = UsageCenter(settings: settings, stats: nil)
        defer { center.stop() }
        let account = AgentAccount(tool: .claude, folder: URL(fileURLWithPath: "/tmp/usage-test"), plan: "Pro", name: "Work")
        center.setAccounts([account])
        let reset = AIUsageModule(center: center)
        let agents = AgentsModule(center: .practice())
        agents.peekAlert = agents.center.threads.first { $0.status.needsYou }.map { AgentAlert(kind: .needsYou, thread: $0) }
        let notch = NotchViewModel(layout: NotchLayout(geometry: .simulated(in: CGRect(x: -30_000, y: -30_000, width: 1512, height: 982))),
                                   isMissionControlActive: { false })
        notch.modules = [agents, reset]
        #expect(notch.peek(agents, for: .milliseconds(40)))
        center.setLimits(AccountLimits(state: .available, limits: [
            UsageLimit(kind: .session, usedPercent: 98, resetsAt: Date().addingTimeInterval(-90), window: nil)
        ]), for: account.id)
        #expect(notch.peekModuleID == "agents")
        #expect(center.pendingResets.count == 1)
        for _ in 0..<100 where notch.peekModuleID != "aiUsage" { try await Task.sleep(for: .milliseconds(20)) }
        #expect(notch.peekModuleID == "aiUsage")
        #expect(center.pendingResets.isEmpty)
        #expect(reset.peekReset?.items.first?.account.id == account.id)
        settings.peeksOnReset = false
        for _ in 0..<100 where notch.peekModuleID != nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(notch.peekModuleID == nil)
        notch.modules = []
    }

    @Test func unpinningRetriesAnUnannouncedResetWithoutAnotherFileWrite() async throws {
        let defaults = UserDefaults(suiteName: "ResetUnpin.\(UUID().uuidString)")!
        defaults.set(true, forKey: "aiUsage.enabled")
        let settings = AgentsSettings(defaults: defaults)
        settings.warnsNearLimit = false
        let center = UsageCenter(settings: settings, stats: nil)
        defer { center.stop() }
        let account = AgentAccount(tool: .claude, folder: URL(fileURLWithPath: "/tmp/unpin"), plan: "Pro")
        center.setAccounts([account])
        let module = AIUsageModule(center: center)
        let notch = NotchViewModel(layout: NotchLayout(geometry: .simulated(in: CGRect(x: -30_000, y: -30_000, width: 1512, height: 982))),
                                   isMissionControlActive: { false })
        notch.isPinned = true
        notch.module = module
        center.setLimits(AccountLimits(state: .available, limits: [
            UsageLimit(kind: .session, usedPercent: 80, resetsAt: Date().addingTimeInterval(-90), window: nil)
        ]), for: account.id)
        #expect(notch.peekModuleID == nil)
        #expect(center.pendingResets.count == 1)
        notch.isPinned = false
        for _ in 0..<100 where notch.peekModuleID == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(notch.peekModuleID == "aiUsage")
        #expect(center.pendingResets.isEmpty)
        notch.reset()
        notch.modules = []
    }

    @Test func practiceExampleClosesExpandedPreviewThenPeeksWithoutTouchingRealLimits() async throws {
        let module = AIUsageModule(center: .practice(), peeks: false)
        let notch = NotchViewModel(layout: NotchLayout(geometry: .simulated(in: CGRect(x: -30_000, y: -30_000, width: 1512, height: 982))),
                                   state: .expanded, isMissionControlActive: { false })
        notch.module = module
        let limits = module.center.limits
        module.showResetExample()
        for _ in 0..<100 where notch.peekModuleID == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(notch.peekModuleID == "aiUsage")
        #expect(notch.state != .expanded)
        #expect(module.center.limits == limits)
        notch.reset()
        notch.modules = []
    }
}

@MainActor
struct ResetInteractionRetryTests {
    final class MissionControl {
        var active = true
    }

    func fixture() -> (AIUsageModule, NotchViewModel, MissionControl) {
        let defaults = UserDefaults(suiteName: "ResetInteraction.\(UUID().uuidString)")!
        defaults.set(true, forKey: "aiUsage.enabled")
        let settings = AgentsSettings(defaults: defaults)
        settings.warnsNearLimit = false
        let center = UsageCenter(settings: settings, stats: nil)
        let account = AgentAccount(tool: .claude, folder: URL(fileURLWithPath: "/tmp/reset-interaction"), plan: "Pro")
        center.setAccounts([account])
        let module = AIUsageModule(center: center)
        let missionControl = MissionControl()
        let notch = NotchViewModel(
            layout: NotchLayout(geometry: .simulated(in: CGRect(x: -30_000, y: -30_000, width: 1512, height: 982))),
            isMissionControlActive: { missionControl.active }
        )
        notch.module = module
        center.setLimits(AccountLimits(state: .available, limits: [
            UsageLimit(kind: .session, usedPercent: 80, resetsAt: Date().addingTimeInterval(-90), window: nil)
        ]), for: account.id)
        return (module, notch, missionControl)
    }

    @Test func pointerInteractionRetriesAfterMissionControlWithoutAFileWrite() async throws {
        let (module, notch, missionControl) = fixture()
        defer { notch.modules = []; module.center.stop() }
        #expect(notch.peekModuleID == nil)
        #expect(module.center.pendingResets.count == 1)
        // An interaction while Mission Control remains up cannot consume the reset.
        module.resetRetryInteractionOccurred()
        try await Task.sleep(for: .milliseconds(700))
        #expect(notch.peekModuleID == nil)
        #expect(module.center.pendingResets.count == 1)
        missionControl.active = false
        module.resetRetryInteractionOccurred()
        for _ in 0..<100 where notch.peekModuleID == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(notch.peekModuleID == "aiUsage")
        #expect(module.center.pendingResets.isEmpty)
        notch.reset()
    }

    @Test func applicationSwitchNotificationRetriesTheBlockedReset() async throws {
        let (module, notch, missionControl) = fixture()
        defer { notch.modules = []; module.center.stop() }
        #expect(module.center.pendingResets.count == 1)
        missionControl.active = false
        // This is a process-local notification, not a real application activation.
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        for _ in 0..<100 where notch.peekModuleID == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(notch.peekModuleID == "aiUsage")
        #expect(module.center.pendingResets.isEmpty)
        notch.reset()
    }

    @Test func detachingCancelsAnInteractionAttemptWithoutAcknowledgingTheReset() async throws {
        let (module, notch, missionControl) = fixture()
        defer { module.center.stop() }
        missionControl.active = false
        module.resetRetryInteractionOccurred()
        notch.modules = []
        try await Task.sleep(for: .milliseconds(700))
        #expect(notch.peekModuleID == nil)
        #expect(module.center.pendingResets.count == 1)
    }
}
