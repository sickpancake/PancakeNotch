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

    private static func agents(_ center: AgentsCenter = .practice()) -> AgentsModule {
        let module = AgentsModule(center: center)
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

        // Agents: the ear for a thread that needs you, the list (one thread's subagents shown), the strip under the notch, nothing running.
        row(.compact, agents())
        let withSubagents = agents()
        if let parent = withSubagents.center.threads.first(where: { !$0.subagents.isEmpty }) { withSubagents.toggleSubagents(of: parent) }
        row(.expanded, withSubagents)
        let asking = agents()
        asking.peekAlert = asking.center.threads.first { $0.status.needsYou }.map { AgentAlert(kind: .needsYou, thread: $0) }
        row(.compact, asking) { $0.peekForSnapshot(asking) }
        row(.expanded, agents(AgentsCenter(settings: emptySettings)))
        // A request to change a file: Review in the list, then the whole change in the taller notch.
        row(.expanded, agents(.practiceWithEdit()))
        let reviewing = agents(.practiceWithEdit())
        if let thread = reviewing.center.threads.first(where: { if case .edit? = $0.approval?.review.content { true } else { false } }) {
            reviewing.review(thread)
        }
        row(.expanded, reviewing) { $0.setTall(true) }

        // AI Usage: one account, all of them, the account menu, the ear and strip for an account that
        // runs low, no accounts.
        row(.expanded, usage())
        let everyone = UsageCenter.practice()
        everyone.selection = .all
        row(.expanded, usage(everyone))
        let withMenu = usage()
        row(.expanded, withMenu) { _ in withMenu.openMenu() }
        row(.compact, usage())
        let low = usage()
        low.peekNear = low.center.earReading
        row(.compact, low) { $0.peekForSnapshot(low) }
        row(.expanded, usage(UsageCenter(settings: emptySettings, stats: nil)))
        return rows
    }
}
