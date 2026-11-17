import AppKit
import AgentsCore
import ModuleAgents
import ModuleKeepAwake
import ModuleNowPlaying
import ModuleShelf
import ModuleTimer
import NotchCore
import NowPlayingCore
import Testing

@MainActor
struct EarModuleContractVerification {
    @Test func everyMigratedModuleDeclaresItsActualContent() {
        let shelf = PracticeShelf(seeded: false)
        defer { shelf.close() }
        let modules: [any NotchModule] = [
            NowPlayingModule(center: .practice()), shelf.module, ShelfPreviewModule(),
            AgentsModule(center: .practiceEmpty(), peeks: false),
            AIUsageModule(center: .practiceEmpty(), peeks: false),
            TimerSnapshot.module(), KeepAwakeSnapshot.module()
        ]
        let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        for module in modules {
            guard let configuration = module.earConfiguration,
                  let content = module.compactEars(layout: layout),
                  configuration.hasExtra == (content.extra != nil) else {
                Issue.record("MODULE_CONFIGURATION: \(module.moduleID) lost its declared ear content")
                return
            }
            let expected: CompactEarPlacement = module.moduleID == "keepAwake" ? .first
                : module.moduleID == "timer" ? .second : .byRank
            if configuration.placement != expected {
                Issue.record("MODULE_CONFIGURATION: \(module.moduleID) changed its default placement")
                return
            }
        }
    }
}
