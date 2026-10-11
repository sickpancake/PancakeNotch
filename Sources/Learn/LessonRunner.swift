import Foundation
import Observation

/// Walks through one lesson: the current step ticks when its signal arrives, then moves on.
@MainActor
@Observable
public final class LessonRunner {
    public let lesson: Lesson
    /// The step being shown; equals `lesson.steps.count` when finished.
    public private(set) var stepIndex: Int = 0
    /// Step ids the user actually did (not skipped).
    public private(set) var ticked: Set<String> = []
    public private(set) var skipped: Set<String> = []
    /// The step that just ticked, shown as done for a moment before moving on (nil otherwise).
    public private(set) var justTicked: String?
    /// Called when the last step is ticked or skipped (again after `back` or `restart` and a new run-through).
    @ObservationIgnored public var onFinish: (() -> Void)?

    @ObservationIgnored private let advanceDelay: Duration
    /// The one-shot wait between a tick and the next step. Cancelled by skip/back/restart.
    @ObservationIgnored private var advanceTask: Task<Void, Never>?

    public init(lesson: Lesson, advanceDelay: Duration = .milliseconds(700)) {
        self.lesson = lesson
        self.advanceDelay = advanceDelay
    }

    public var currentStep: LessonStep? {
        lesson.steps.indices.contains(stepIndex) ? lesson.steps[stepIndex] : nil
    }

    public var isFinished: Bool { stepIndex >= lesson.steps.count }

    /// Ticks the current step if `signal` is the one it waits for; anything else is ignored.
    public func receive(_ signal: LessonSignal) {
        guard justTicked == nil, let step = currentStep, step.signal == signal else { return }
        ticked.insert(step.id)
        justTicked = step.id
        if advanceDelay == .zero {
            finishTick()
            return
        }
        let delay = advanceDelay
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.finishTick()
        }
    }

    /// Marks the current step skipped and moves on straight away.
    /// During the short pause after a tick it just moves on (the step stays ticked).
    public func skip() {
        if justTicked != nil {
            cancelPendingAdvance()
            advance()
            return
        }
        guard let step = currentStep else { return }
        skipped.insert(step.id)
        advance()
    }

    /// Goes to the previous step and clears its tick or skip. Does nothing on the first step.
    /// During the short pause after a tick it also un-ticks the current step.
    public func back() {
        if let id = justTicked {
            cancelPendingAdvance()
            ticked.remove(id)
        }
        guard stepIndex > 0 else { return }
        stepIndex -= 1
        let id = lesson.steps[stepIndex].id
        ticked.remove(id)
        skipped.remove(id)
    }

    /// Starts the lesson over from the first step.
    public func restart() {
        cancelPendingAdvance()
        stepIndex = 0
        ticked = []
        skipped = []
    }

    private func finishTick() {
        advanceTask = nil
        justTicked = nil
        advance()
    }

    private func cancelPendingAdvance() {
        advanceTask?.cancel()
        advanceTask = nil
        justTicked = nil
    }

    /// Moves to the next step; reaching the end calls `onFinish` (once per time the end is reached).
    private func advance() {
        guard !isFinished else { return }
        stepIndex += 1
        if isFinished {
            onFinish?()
        }
    }
}
