import Foundation
import NotchCore
import TimerCore

/// Notch states for the off-screen snapshot (`PANCAKENOTCH_SNAPSHOT`): the Timer's ears (running alone,
/// beside another module, paused, done, the stopwatch) and its open pages.
@MainActor
public enum TimerSnapshot {
    /// A clock that starts at a fixed moment (so the pictures don't change between runs) and moves only
    /// when told.
    public final class Clock {
        public var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        public func advance(_ seconds: TimeInterval) { now += seconds }
    }

    public static func module(setUp: (TimerCenter, Clock) -> Void = { _, _ in }, settings: (TimerSettings) -> Void = { _ in }) -> TimerModule {
        let clock = Clock()
        let center = TimerCenter(now: { clock.now })
        setUp(center, clock)
        // A fresh throwaway domain each time, so one picture's settings don't leak into the next.
        let suite = "io.github.sickpancake.PancakeNotch.timer-snapshot"
        let defaults = UserDefaults(suiteName: suite) ?? UserDefaults()
        defaults.removePersistentDomain(forName: suite)
        let timerSettings = TimerSettings(defaults: defaults)
        settings(timerSettings)
        let module = TimerModule(center: center, settings: timerSettings, presents: false)
        module.isSnapshot = true
        return module
    }

    /// A 25-minute timer, 4 min 18 s in.
    static func runningTimer(_ center: TimerCenter, _ clock: Clock) {
        center.startTimer(seconds: 25 * 60)
        clock.advance(4 * 60 + 18)
    }

    public static func models(layout: NotchLayout, others: () -> any NotchModule) -> [NotchViewModel] {
        func model(_ state: NotchState, _ modules: [any NotchModule], setUp: (NotchViewModel) -> Void = { _ in }) -> NotchViewModel {
            let model = NotchViewModel(layout: layout, state: state, arrangement: ModuleArrangement())
            model.modules = modules
            setUp(model)
            return model
        }
        let running = module(setUp: runningTimer)
        let paused = module { center, clock in
            center.startTimer(seconds: 90)
            clock.advance(23)
            center.pauseTimer()
        }
        let done = module { center, clock in
            center.startTimer(seconds: 5 * 60)
            clock.advance(5 * 60)
            center.timeMayHaveJumped()
        }
        let stopwatch = module { center, clock in
            center.startStopwatch()
            clock.advance(83.45)
        }
        let laps = module { center, clock in
            center.startStopwatch()
            for lap in [61.2, 58.9, 64.35, 60.02] {
                clock.advance(lap)
                center.lap()
            }
            clock.advance(12.5)
        }
        return [
            model(.compact, [running]),
            model(.compact, [others(), module(setUp: runningTimer)]),
            model(.compact, [others(), module { center, clock in
                center.startTimer(seconds: 90)
                clock.advance(23)
                center.pauseTimer()
            }]),
            model(.compact, [module(setUp: runningTimer, settings: { $0.earContent = .endTime })]),
            model(.compact, [stopwatch]),
            model(.expanded, [module()]),
            model(.expanded, [module(setUp: runningTimer)]),
            model(.expanded, [paused]),
            model(.expanded, [laps]),
            model(.expanded, [module(setUp: runningTimer, settings: { $0.sideBySide = true })]),
            model(.compact, [done]),
            model(.expanded, [module { center, clock in
                center.startTimer(seconds: 5 * 60)
                clock.advance(5 * 60)
                center.timeMayHaveJumped()
            }]),
            // Long times must fit when the module has both ears, too.
            model(.compact, [module { center, _ in center.startTimer(seconds: CountdownTimer.longest) }]),
            model(.compact, [module { center, clock in
                center.startStopwatch()
                clock.advance(24 * 3_600)
            }]),
            // Neighbours follow the typed 4, rather than surrounding the old 31 minutes.
            model(.expanded, [module { center, _ in center.customSeconds = 31 * 60 + 3 }]) { model in
                guard let timer = model.selectedModule as? TimerModule else { return }
                timer.beginEditing(.minutes)
                timer.typed = "4"
            },
            model(.expanded, [module(settings: { settings in
                settings.sideBySide = true
                for index in 1...7 { _ = settings.addPreset(seconds: TimeInterval(index * 60), name: "Quick time \(index)") }
            })]),
        ]
    }
}
