import Foundation
import KeepAwakeCore
import NotchCore

/// Notch states for the off-screen snapshot (`PANCAKENOTCH_SNAPSHOT`): Keep Awake's ear (alone, beside other
/// modules, with the Timer), its page in each state, and its strips.
@MainActor
public enum KeepAwakeSnapshot {
    /// A clock that starts at a fixed moment (so the pictures don't change between runs) and moves only when told.
    public final class Clock {
        public var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        public func advance(_ seconds: TimeInterval) { now += seconds }
    }

    public static func module(power: PowerState = .pluggedIn, setUp: (KeepAwakeCenter, Clock) -> Void = { _, _ in },
                              settings: (KeepAwakeSettings) -> Void = { _ in }) -> KeepAwakeModule {
        let clock = Clock()
        // A fresh throwaway domain each time, so one picture's settings don't leak into the next.
        let suite = "io.github.sickpancake.PancakeNotch.keepawake-snapshot"
        let defaults = UserDefaults(suiteName: suite) ?? UserDefaults()
        defaults.removePersistentDomain(forName: suite)
        let keepAwakeSettings = KeepAwakeSettings(defaults: defaults)
        settings(keepAwakeSettings)
        var current = power
        let center = KeepAwakeCenter(settings: keepAwakeSettings, now: { clock.now }, power: { current }, bootTime: { nil })
        setUp(center, clock)
        current = power
        let module = KeepAwakeModule(center: center, presents: false)
        module.isSnapshot = true
        return module
    }

    /// An hour, 18 minutes in.
    static func timed(_ center: KeepAwakeCenter, _ clock: Clock) {
        center.turnOn(.timed(3600))
        clock.advance(18 * 60)
    }

    /// - Parameter others: other modules to show beside it (Now Playing; Now Playing and a running Timer).
    public static func models(layout: NotchLayout, others: () -> [any NotchModule], withTimer: () -> [any NotchModule]) -> [NotchViewModel] {
        func model(_ state: NotchState, _ modules: [any NotchModule], setUp: (NotchViewModel) -> Void = { _ in }) -> NotchViewModel {
            let model = NotchViewModel(layout: layout, state: state, arrangement: ModuleArrangement())
            model.modules = modules
            setUp(model)
            return model
        }
        func ended(_ reason: KeepAwakeNotice) -> KeepAwakeModule {
            let module = module()
            module.showNoticeForSnapshot(reason)
            return module
        }
        return [
            model(.compact, [module(setUp: timed)]),
            model(.compact, others() + [module(setUp: timed)]),
            model(.compact, withTimer() + [module { center, _ in center.turnOn(.untilStopped) }]),
            model(.expanded, [module()]),
            model(.expanded, [module(setUp: timed)]),
            model(.expanded, [module { center, _ in center.setWork(agents: true, converting: false) }]),
            model(.expanded, [module { center, _ in
                center.setWork(agents: true, converting: false)
                center.turnOff()
            }]),
            model(.expanded, [module(power: PowerState(onBattery: true, percent: 14))]),
            model(.expanded, [module(setUp: { center, _ in center.turnOn(.untilStopped) }, settings: { $0.screen = .canTurnOff })]),
            model(.compact, [ended(.timeUp)]) { $0.peekForSnapshot($0.modules[0]) },
            model(.compact, [ended(.batteryLow)]) { $0.peekForSnapshot($0.modules[0]) },
            model(.compact, [ended(.batteryLowKeepsGoing)]) { $0.peekForSnapshot($0.modules[0]) },
            model(.compact, [ended(.backOn)]) { $0.peekForSnapshot($0.modules[0]) },
            // Kept going on a low battery: the page says so.
            model(.expanded, [module(power: PowerState(onBattery: true, percent: 8), setUp: { center, _ in center.turnOn(.untilStopped) },
                                     settings: { $0.lowBattery = .keepGoing })]),
            // Stopped by a low battery, coming back when plugged in: the page offers Turn Off.
            model(.expanded, [module(setUp: { center, _ in
                center.turnOn(.untilStopped)
                center.setPower(PowerState(onBattery: true, percent: 8))
            }, settings: { $0.batteryCutoff = 10 })]),
        ]
    }
}
