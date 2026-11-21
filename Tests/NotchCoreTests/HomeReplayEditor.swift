import Testing
@testable import NotchCore

/// Editor transaction replays against production HomeSettings/HomeHistory.
/// View-only cancellation and focus cannot be called through these APIs; see verify-home-editor.
@Suite @MainActor struct HomeReplayEditor {
    func unwrap(_ value: HomeLayout?) throws -> HomeLayout { try #require(value) }

    func settings(_ layout: HomeLayout = .default) -> HomeSettings {
        let home = HomeSettings(); home.layout = layout; return home
    }

    @Test func undoRedoExactAndNewEditClearsRedo() throws {
        let home = settings(); var history = HomeHistory()
        let before = home.layout
        home.edit(&history) { $0.adding(.statistics) }
        let after = home.layout
        home.layout = try unwrap(history.undo(current: home.layout))
        #expect(home.layout == before)
        home.layout = try unwrap(history.redo(current: home.layout))
        #expect(home.layout == after)
        home.layout = try unwrap(history.undo(current: home.layout))
        home.edit(&history) { $0.adding(.battery) }
        #expect(!history.canRedo)
    }

    @Test func refusalAndNoOpPreserveBothStacks() throws {
        let home = settings(); var history = HomeHistory()
        home.edit(&history) { $0.adding(.statistics) }
        home.layout = try unwrap(history.undo(current: home.layout))
        let before = home.layout, stack = history
        #expect(home.edit(&history) { $0.adding(.timer) } == .alreadyOnHome)
        #expect(home.layout == before && history == stack)
        #expect(home.edit(&history) { $0.inserting(.allModules, size: .small, at: .init(page: 0, column: 0, row: 0)) } == .unsupportedSize)
        #expect(home.layout == before && history == stack)
        home.edit(&history) { .success($0) }
        #expect(home.layout == before && history == stack)
    }

    @Test func fullRefusalHasNoHistory() {
        let home = settings(); var history = HomeHistory()
        let before = home.layout
        #expect(home.edit(&history) { _ in .failure(.full) } == .full)
        #expect(home.layout == before && !history.canUndo)
    }

    @Test func presetsAndResetUndoInOneStep() throws {
        for preset in HomePreset.allCases {
            let home = settings(HomePreset.work.layout); var history = HomeHistory()
            home.layout.statisticsMetric = "listeningThisWeek"
            let before = home.layout
            home.edit(&history) { .success($0.applying(preset)) }
            let after = home.layout
            if after != before {
                home.layout = try unwrap(history.undo(current: home.layout))
                #expect(home.layout == before)
                home.layout = try unwrap(history.redo(current: home.layout))
                #expect(home.layout == after)
            }
            let preReset = home.layout
            home.edit(&history) { _ in .success(.default) }
            if preReset != .default {
                home.layout = try unwrap(history.undo(current: home.layout))
                #expect(home.layout == preReset)
            }
        }
    }

    @Test func previewsNeverWriteAndDuplicateGalleryAddRefused() throws {
        let home = settings(); var history = HomeHistory()
        let before = home.layout
        _ = home.layout.previewMoving(.timer, to: .init(page: 1, column: 0, row: 0))
        _ = home.layout.previewInserting(.statistics, size: .small, at: .init(page: 2, column: 0, row: 0))
        #expect(home.layout == before && !history.canUndo)
        home.edit(&history) { $0.adding(.statistics) }
        let after = home.layout, stack = history
        #expect(home.layout.contains(.statistics))
        #expect(home.edit(&history) { $0.adding(.statistics) } == .alreadyOnHome)
        #expect(home.layout == after && history == stack)
        home.layout = try unwrap(history.undo(current: home.layout))
        #expect(!home.layout.contains(.statistics))
    }

    @Test func statisticsSurvivesMoveResizeUndo() throws {
        let home = settings(HomeLayout(placements: [.init(kind: .statistics, size: .small, slot: .init(page: 0, column: 0, row: 0))], statisticsMetric: "shelvedThisWeek"))
        var history = HomeHistory()
        let initial = home.layout
        home.edit(&history) { $0.movingToPage(.statistics, page: 2) }
        let moved = home.layout
        home.edit(&history) { $0.resizing(.statistics, to: .medium) }
        #expect(home.layout.statisticsMetric == initial.statisticsMetric)
        home.layout = try unwrap(history.undo(current: home.layout))
        #expect(home.layout == moved)
        home.layout = try unwrap(history.undo(current: home.layout))
        #expect(home.layout == initial)
    }

    @Test func boundedEditSequencesAlwaysSaveRepairedLayouts() throws {
        // Every ordered pair from ten editor operations, then Undo twice/Redo twice.
        let edits: [(HomeLayout) -> Result<HomeLayout, HomeEditRefusal>] = [
            { $0.adding(.statistics) }, { $0.adding(.battery) },
            { $0.movingToPage(.timer, page: 2) }, { $0.nudging(.timer, by: .right) },
            { $0.resizing(.nowPlaying, to: .small) }, { .success($0.removing(.clock)) },
            { .success($0.applying(.music)) }, { .success($0.applying(.minimal)) },
            { _ in .success(.default) }, { $0.movingToPage(.timer, page: 3) }
        ]
        for first in edits { for second in edits {
            let home = settings(); var history = HomeHistory(); var snapshots = [home.layout]
            for edit in [first, second] {
                let before = home.layout
                home.edit(&history, edit)
                #expect(home.layout == HomeLayout.decode(home.layout.encoded()))
                if home.layout != before { snapshots.append(home.layout) }
            }
            for expected in snapshots.dropLast().reversed() {
                home.layout = try unwrap(history.undo(current: home.layout))
                #expect(home.layout == expected)
            }
            for expected in snapshots.dropFirst() {
                home.layout = try unwrap(history.redo(current: home.layout))
                #expect(home.layout == expected)
            }
        } }
    }
}
