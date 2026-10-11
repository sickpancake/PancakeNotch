import AppKit
import Testing
@testable import Learn

@MainActor
struct LessonRunnerTests {
    private func runner(_ lesson: Lesson = .basics) -> LessonRunner {
        LessonRunner(lesson: lesson, advanceDelay: .zero)
    }

    @Test func startsOnTheFirstStep() {
        let runner = runner()
        #expect(runner.stepIndex == 0)
        #expect(runner.currentStep?.id == Lesson.basics.steps[0].id)
        #expect(!runner.isFinished)
        #expect(runner.justTicked == nil)
    }

    @Test func ticksOnlyOnTheCurrentStepsSignal() {
        let runner = runner()
        runner.receive(.notchShrunk)        // step 2's signal, too early
        runner.receive(.shelfItemAdded)     // another lesson's signal
        #expect(runner.stepIndex == 0)
        #expect(runner.ticked.isEmpty)

        runner.receive(.notchOpened)
        #expect(runner.stepIndex == 1)
        #expect(runner.ticked == [Lesson.basics.steps[0].id])
        #expect(runner.justTicked == nil)

        runner.receive(.notchOpened)        // repeating the old signal does nothing
        #expect(runner.stepIndex == 1)
    }

    @Test func skipMarksSkippedNotTicked() {
        let runner = runner()
        runner.skip()
        #expect(runner.stepIndex == 1)
        #expect(runner.skipped == [Lesson.basics.steps[0].id])
        #expect(runner.ticked.isEmpty)
    }

    @Test func backUndoesThePreviousStep() {
        let runner = runner()
        runner.back()                       // no-op at the start
        #expect(runner.stepIndex == 0)

        runner.receive(.notchOpened)
        runner.skip()
        #expect(runner.stepIndex == 2)

        runner.back()
        #expect(runner.stepIndex == 1)
        #expect(runner.skipped.isEmpty)
        #expect(runner.ticked == [Lesson.basics.steps[0].id])

        runner.back()
        #expect(runner.stepIndex == 0)
        #expect(runner.ticked.isEmpty)
    }

    @Test func restartClearsEverything() {
        let runner = runner()
        runner.receive(.notchOpened)
        runner.skip()
        runner.restart()
        #expect(runner.stepIndex == 0)
        #expect(runner.ticked.isEmpty)
        #expect(runner.skipped.isEmpty)
        #expect(runner.justTicked == nil)
    }

    @Test func onFinishFiresOnceAtTheEnd() {
        let runner = runner()
        var finishes = 0
        runner.onFinish = { finishes += 1 }
        runner.receive(.notchOpened)
        runner.receive(.notchShrunk)
        runner.receive(.notchClosed)
        #expect(finishes == 0)
        runner.skip()
        #expect(runner.isFinished)
        #expect(runner.currentStep == nil)
        #expect(runner.stepIndex == Lesson.basics.steps.count)
        #expect(finishes == 1)

        // Nothing more counts once finished.
        runner.skip()
        runner.receive(.shortcutSet)
        #expect(finishes == 1)
        #expect(runner.stepIndex == Lesson.basics.steps.count)
    }

    @Test func waitsBeforeMovingOn() async throws {
        let runner = LessonRunner(lesson: .basics, advanceDelay: .milliseconds(30))
        runner.receive(.notchOpened)
        let first = Lesson.basics.steps[0].id
        #expect(runner.justTicked == first)
        #expect(runner.ticked == [first])
        #expect(runner.stepIndex == 0)

        runner.receive(.notchShrunk)        // ignored while the tick is showing
        #expect(runner.ticked == [first])

        try await Task.sleep(for: .milliseconds(300))
        #expect(runner.justTicked == nil)
        #expect(runner.stepIndex == 1)
    }

    @Test func restartCancelsAPendingMove() async throws {
        let runner = LessonRunner(lesson: .basics, advanceDelay: .milliseconds(30))
        runner.receive(.notchOpened)
        runner.restart()
        try await Task.sleep(for: .milliseconds(300))
        #expect(runner.stepIndex == 0)
        #expect(runner.ticked.isEmpty)
        #expect(runner.justTicked == nil)
    }
}

@MainActor
struct LearnProgressTests {
    private let suiteName = "LearnProgressTests-\(UUID().uuidString)"

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }

    @Test func startsEmpty() {
        withDefaults { defaults in
            let progress = LearnProgress(defaults: defaults)
            #expect(progress.doneCount == 0)
            #expect(!progress.allDone)
            #expect(!progress.isDone(.basics))
            #expect(!progress.homeBoxHidden)
            #expect(!progress.onboardingDone)
        }
    }

    @Test func survivesRelaunch() {
        withDefaults { defaults in
            let progress = LearnProgress(defaults: defaults)
            progress.markDone(.basics)
            progress.homeBoxHidden = true
            progress.onboardingDone = true
            #expect(defaults.bool(forKey: "learn.done.basics"))
            #expect(defaults.bool(forKey: "learn.homeBoxHidden"))
            #expect(defaults.bool(forKey: "onboarding.done"))

            let reloaded = LearnProgress(defaults: defaults)
            #expect(reloaded.isDone(.basics))
            #expect(!reloaded.isDone(.shelf))
            #expect(reloaded.doneCount == 1)
            #expect(reloaded.homeBoxHidden)
            #expect(reloaded.onboardingDone)
        }
    }

    @Test func allDoneAndReset() {
        withDefaults { defaults in
            let progress = LearnProgress(defaults: defaults)
            for id in LessonID.allCases { progress.markDone(id) }
            #expect(progress.allDone)
            #expect(progress.doneCount == LessonID.allCases.count)

            progress.reset(.shelf)
            #expect(!progress.allDone)
            #expect(!LearnProgress(defaults: defaults).isDone(.shelf))
        }
    }
}

struct LessonContentTests {
    @Test func everyLessonIsListedOnce() {
        #expect(Lesson.all.map(\.id) == LessonID.allCases)
        for id in LessonID.allCases {
            #expect(Lesson.lesson(id).id == id)
        }
    }

    @Test(arguments: Lesson.all.map(\.id))
    func lessonTextIsComplete(id: LessonID) {
        let lesson = Lesson.lesson(id)
        #expect(!lesson.title.isEmpty)
        #expect(!lesson.summary.isEmpty)
        #expect(!lesson.symbol.isEmpty)
        #expect(!lesson.steps.isEmpty)
        #expect(Set(lesson.steps.map(\.id)).count == lesson.steps.count)
        #expect(Set(lesson.steps.map(\.signal)).count == lesson.steps.count)
        for step in lesson.steps {
            #expect(!step.id.isEmpty)
            #expect(!step.title.isEmpty)
            #expect(!step.detail.isEmpty)
            #expect(!step.symbol.isEmpty)
        }
    }

    @Test func symbolsExist() {
        let names = Lesson.all.flatMap { [$0.symbol] + $0.steps.map(\.symbol) }
        for name in names {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "missing SF Symbol \(name)")
        }
    }

    @Test func stepIdsAreUniqueAcrossLessons() {
        let ids = Lesson.all.flatMap { $0.steps.map(\.id) }
        #expect(Set(ids).count == ids.count)
    }
}
