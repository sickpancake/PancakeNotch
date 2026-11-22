import Foundation
import NotchCore
import NotesCore

/// Off-screen pictures of Notes (`PancakeNotch --snapshot`).
@MainActor
public enum NotesSnapshot {
    public nonisolated static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    public static func module(notes: Bool = true, setUp: (NotesModule) -> Void = { _ in }) -> NotesModule {
        let suite = "io.github.sickpancake.PancakeNotch.notes-snapshot"
        let defaults = UserDefaults(suiteName: suite) ?? UserDefaults()
        defaults.removePersistentDomain(forName: suite)
        let store = notes ? NotesStore.practice(now: now) : NotesStore(directory: nil, now: { now })
        let module = NotesModule(store: store, settings: NotesSettings(defaults: defaults))
        module.isSnapshot = true
        setUp(module)
        return module
    }

    public static func models(layout: NotchLayout, others: () -> [any NotchModule]) -> [NotchViewModel] {
        func model(_ modules: [any NotchModule]) -> NotchViewModel {
            let model = NotchViewModel(layout: layout, state: .expanded, arrangement: ModuleArrangement())
            model.modules = modules
            return model
        }
        return [
            model([module(notes: false)]),
            model([module()]),
            model([module()] + others()),
            model([module { module in
                if let note = module.notes.dropFirst().first { module.select(note.id) }
                module.store.delete(module.notes.last!.id)
            }]),
            model([module { $0.isDropTargeted = true }]),
        ]
    }
}
