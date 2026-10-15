import Foundation
import Observation

/// Which lessons are done, and the one-time Home box / onboarding flags. Stored on this Mac only.
@MainActor
@Observable
public final class LearnProgress {
    /// Lessons the user finished. Persisted one key per lesson ("learn.done.<id>").
    private var done: Set<LessonID> {
        didSet {
            for id in LessonID.allCases where done.contains(id) != oldValue.contains(id) {
                defaults.set(done.contains(id), forKey: Keys.done(id))
            }
        }
    }

    /// The user closed the "Learn the basics" box on the Home page.
    public var homeBoxHidden: Bool { didSet { defaults.set(homeBoxHidden, forKey: Keys.homeBoxHidden) } }
    /// The first-launch onboarding was seen through (or skipped).
    public var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: Keys.onboardingDone) } }
    /// The welcome step to come back to: closing the window pauses the welcome instead of ending it.
    public var onboardingStep: Int { didSet { defaults.set(onboardingStep, forKey: Keys.onboardingStep) } }
    /// The welcome has opened by itself once. It doesn't open again at launch; opening the window
    /// carries on where it was paused.
    public var onboardingShown: Bool { didSet { defaults.set(onboardingShown, forKey: Keys.onboardingShown) } }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        done = Set(LessonID.allCases.filter { defaults.bool(forKey: Keys.done($0)) })
        homeBoxHidden = defaults.bool(forKey: Keys.homeBoxHidden)
        onboardingDone = defaults.bool(forKey: Keys.onboardingDone)
        onboardingStep = defaults.integer(forKey: Keys.onboardingStep)
        onboardingShown = defaults.bool(forKey: Keys.onboardingShown)
    }

    /// About › Show Welcome Again: from the first step.
    public func showWelcomeAgain() {
        onboardingStep = 0
        onboardingDone = false
    }

    /// Skip or Done: the welcome is over, and starts from the top if it's shown again.
    public func finishWelcome() {
        onboardingStep = 0
        onboardingDone = true
    }

    public func isDone(_ id: LessonID) -> Bool { done.contains(id) }

    public func markDone(_ id: LessonID) {
        if !done.contains(id) { done.insert(id) }
    }

    public func reset(_ id: LessonID) {
        if done.contains(id) { done.remove(id) }
    }

    public var doneCount: Int { done.count }

    public var allDone: Bool { done.count == LessonID.allCases.count }

    private enum Keys {
        static func done(_ id: LessonID) -> String { "learn.done.\(id.rawValue)" }
        static let homeBoxHidden = "learn.homeBoxHidden"
        static let onboardingDone = "onboarding.done"
        static let onboardingStep = "onboarding.step"
        static let onboardingShown = "onboarding.shown"
    }
}
