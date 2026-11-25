import AgentsCore
import Foundation
import NotchCore

/// Agents and AI Usage states for the off-screen snapshot (`PANCAKENOTCH_SNAPSHOT`), on the practice
/// centers: nothing real is read.
@MainActor
public enum AgentsSnapshot {
    /// Settings for centers that stay empty (no threads, no accounts), apart from the user's own.
    private static var emptySettings: AgentsSettings {
        AgentsSettings(defaults: UserDefaults(suiteName: "io.github.sickpancake.PancakeNotch.snapshots.agents") ?? .standard)
    }

    /// Pretend Devin, found and not connected, on settings that start empty every run (Connect saves to them).
    private static func devinReminder() -> ConnectReminder {
        let name = "io.github.sickpancake.PancakeNotch.snapshots.reminder"
        UserDefaults().removePersistentDomain(forName: name)
        return .preview(.devin, settings: AgentsSettings(defaults: UserDefaults(suiteName: name) ?? .standard))
    }

    private static func agents(_ center: AgentsCenter = .practice(), reminder: ConnectReminder? = nil) -> AgentsModule {
        let module = AgentsModule(center: center, reminder: reminder)
        module.isSnapshot = true
        return module
    }

    private static func usage(_ center: UsageCenter = .practice()) -> AIUsageModule {
        let module = AIUsageModule(center: center)
        module.isSnapshot = true
        return module
    }

    public static func models(layout: NotchLayout) -> [NotchViewModel] {
        var rows: [NotchViewModel] = []
        func row(_ state: NotchState, _ module: any NotchModule, setUp: (NotchViewModel) -> Void = { _ in }) {
            let model = NotchViewModel(layout: layout, state: state)
            model.modules = [module]
            setUp(model)
            rows.append(model)
        }

        // Agents: the ear for a thread that needs you, the list (one thread's subagents shown), the strip under the notch, a row
        // opened by the pointer, nothing running.
        row(.compact, agents())
        let withSubagents = agents()
        if let parent = withSubagents.center.threads.first(where: { !$0.subagents.isEmpty }) { withSubagents.toggleSubagents(of: parent) }
        row(.expanded, withSubagents)
        let asking = agents()
        asking.peekAlert = asking.center.threads.first { $0.status.needsYou }.map { AgentAlert(kind: .needsYou, thread: $0) }
        row(.compact, asking) { $0.peekForSnapshot(asking) }
        // The pointer rests on the working thread: its row opens to show all of it and the app it runs in.
        // (Set once the notch has opened: opening ends any preview.)
        let previewing = agents()
        row(.expanded, previewing) { _ in
            if let thread = previewing.center.threads.first(where: { $0.status == .working }) { previewing.previewForSnapshot(thread.id) }
        }
        // A finished agent (issue #65): the strip says what it changed, and its opened row shows the last
        // commit with Open in editor, Terminal here and Copy summary.
        let finished = agents()
        finished.peekAlert = finished.center.threads.first { $0.doneSummary != nil }.map { AgentAlert(kind: .finished, thread: $0) }
        row(.compact, finished) { $0.peekForSnapshot(finished) }
        let finishedPreview = agents()
        row(.expanded, finishedPreview) { model in
            model.setTall(true)
            if let thread = finishedPreview.center.threads.first(where: { $0.doneSummary != nil }) { finishedPreview.previewForSnapshot(thread.id) }
        }
        row(.expanded, agents(AgentsCenter(settings: emptySettings)))
        // Devin cloud sessions (issue #55): asking, working, failed and finished with a pull request.
        row(.expanded, agents(.practiceCloud()))
        // A request to change a file: Review in the list, then the whole change in the taller notch.
        row(.expanded, agents(.practiceWithEdit()))
        let reviewing = agents(.practiceWithEdit())
        if let thread = reviewing.center.threads.first(where: { if case .edit? = $0.approval?.review.content { true } else { false } }) {
            reviewing.review(thread)
        }
        row(.expanded, reviewing) { $0.setTall(true) }

        // Devin on this Mac but not connected (issue #78): the strip, once; the Connect row above the list and
        // above "No agents running"; the row after Connect.
        let reminded = agents(reminder: devinReminder())
        reminded.peekReminder = .devin
        row(.compact, reminded) { $0.peekForSnapshot(reminded) }
        row(.expanded, agents(reminder: devinReminder()))
        row(.expanded, agents(AgentsCenter(settings: emptySettings), reminder: devinReminder()))
        let justConnected = devinReminder()
        justConnected.connect()
        row(.expanded, agents(AgentsCenter(settings: emptySettings), reminder: justConnected))

        // AI Usage: one account, all of them, the account menu, the ear and strip for an account that
        // runs low, no accounts.
        row(.expanded, usage())
        let everyone = UsageCenter.practice()
        everyone.selection = .all
        row(.expanded, usage(everyone))
        // Devin cloud: its ACUs, and its line under all accounts.
        let devin = UsageCenter.practiceWithDevin()
        devin.selection = .account(AgentAccount.devinCloud.id)
        row(.expanded, usage(devin))
        let devinAll = UsageCenter.practiceWithDevin()
        devinAll.selection = .all
        row(.expanded, usage(devinAll))
        let withMenu = usage()
        row(.expanded, withMenu) { _ in withMenu.openMenu() }
        row(.compact, usage())
        let low = usage()
        low.peekNear = low.center.earReading
        row(.compact, low) { $0.peekForSnapshot(low) }
        let reset = usage()
        reset.peekReset = reset.center.exampleResetNotice()
        row(.compact, reset) { $0.peekForSnapshot(reset) }
        let summary = usage()
        let sampleAccounts = summary.center.accounts
        summary.peekReset = LimitResetNotice(items: sampleAccounts.prefix(2).map { account in
            .init(account: account, reset: LimitReset(accountID: account.id, kind: .weekly, endedAt: .now, leftBefore: 8))
        })
        row(.compact, summary) { $0.peekForSnapshot(summary) }
        row(.expanded, usage(UsageCenter(settings: emptySettings, stats: nil)))
        return rows
    }
}
