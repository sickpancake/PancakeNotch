import Foundation
import Observation

/// How long Turn On keeps the Mac awake (ADR-0041).
public enum KeepAwakeLength: Codable, Hashable, Sendable {
    case timed(TimeInterval)
    case untilStopped

    /// The choices on the page and in the menu bar menu: 30 min, 1 h, 2 h, 4 h, Until I stop.
    public static let choices: [KeepAwakeLength] = [.timed(30 * 60), .timed(60 * 60), .timed(2 * 3600), .timed(4 * 3600), .untilStopped]
    /// Turn On's length the first time.
    public static let standard = KeepAwakeLength.timed(60 * 60)

    public var seconds: TimeInterval? {
        if case .timed(let seconds) = self { return seconds }
        return nil
    }
}

/// What stays awake while Keep Awake holds the Mac.
public enum KeepAwakeScreen: String, CaseIterable, Sendable {
    /// The screen stays on (and so doesn't lock by itself).
    case staysOn
    /// Only the Mac stays awake: the screen dims, sleeps and locks as usual.
    case canTurnOff
}

/// Whether a Keep Awake you turned on comes back when PancakeNotch opens again (an update, or you quit it).
public enum KeepAwakeReopen: String, CaseIterable, Sendable {
    /// Comes back, but not after the Mac restarted (so it's never left on from yesterday).
    case carryOn
    /// Comes back, even after the Mac restarted.
    case carryOnAfterRestart
    /// Stays off.
    case startOff
}

/// What Keep Awake does on battery at the cutoff (ADR-0041 amendment 2026-11-03).
public enum KeepAwakeLowBattery: String, CaseIterable, Sendable {
    /// Stops, with a strip, and can't start again on battery below the cutoff.
    case stop
    /// Carries on, with one strip saying the battery is low.
    case keepGoing
}

/// What comes back when you plug in after the battery stopped Keep Awake.
public enum KeepAwakePlugIn: String, CaseIterable, Sendable {
    /// The session the battery stopped (if time is left) and automatic keep-awake come back, with a strip.
    case turnBackOn
    /// It stays off until you turn it on, or until the work that runs now ends.
    case stayOff
}

/// Keep Awake's options in the app window (Modules page). Stored in `UserDefaults`.
@MainActor
@Observable
public final class KeepAwakeSettings {
    /// The battery cutoffs offered, in percent; `nil` (Never) is offered too.
    public static let cutoffChoices: [Int] = [10, 20, 30, 50]
    public static let defaultCutoff = 20

    public var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Keys.enabled); changed() } }
    public var screen: KeepAwakeScreen { didSet { defaults.set(screen.rawValue, forKey: Keys.screen); changed() } }
    /// On by itself while an AI agent works or waits for you (needs the Agents module).
    public var whileAgentsWork: Bool { didSet { defaults.set(whileAgentsWork, forKey: Keys.whileAgentsWork); changed() } }
    /// On by itself while the Shelf converts a file.
    public var whileConverting: Bool { didSet { defaults.set(whileConverting, forKey: Keys.whileConverting); changed() } }
    /// Stops on battery at or below this percent; `nil` never stops for the battery.
    public var batteryCutoff: Int? { didSet { defaults.set(batteryCutoff ?? 0, forKey: Keys.batteryCutoff); changed() } }
    /// Stop or keep going on battery at the cutoff.
    public var lowBattery: KeepAwakeLowBattery { didSet { defaults.set(lowBattery.rawValue, forKey: Keys.lowBattery); changed() } }
    /// What plugging in brings back after the battery stopped it (read when you plug in).
    public var plugIn: KeepAwakePlugIn { didSet { defaults.set(plugIn.rawValue, forKey: Keys.plugIn) } }
    public var reopen: KeepAwakeReopen { didSet { defaults.set(reopen.rawValue, forKey: Keys.reopen) } }
    /// The length picked last: a plain Turn On uses it.
    public var lastLength: KeepAwakeLength {
        didSet { if let data = try? JSONEncoder().encode(lastLength) { defaults.set(data, forKey: Keys.lastLength) } }
    }

    @ObservationIgnored let defaults: UserDefaults
    /// The centers following these settings (the real one and practice copies), told in the same step as a
    /// change so a hold never lags behind a setting (KeepAwake.tla).
    @ObservationIgnored private let listeners = NSHashTable<KeepAwakeCenter>.weakObjects()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        screen = defaults.string(forKey: Keys.screen).flatMap(KeepAwakeScreen.init(rawValue:)) ?? .staysOn
        whileAgentsWork = defaults.object(forKey: Keys.whileAgentsWork) as? Bool ?? true
        whileConverting = defaults.object(forKey: Keys.whileConverting) as? Bool ?? true
        // 0 is Never; a missing or odd value is the default.
        let cutoff = (defaults.object(forKey: Keys.batteryCutoff) as? NSNumber)?.intValue ?? Self.defaultCutoff
        batteryCutoff = cutoff == 0 ? nil : Self.cutoffChoices.contains(cutoff) ? cutoff : Self.defaultCutoff
        lowBattery = defaults.string(forKey: Keys.lowBattery).flatMap(KeepAwakeLowBattery.init(rawValue:)) ?? .stop
        plugIn = defaults.string(forKey: Keys.plugIn).flatMap(KeepAwakePlugIn.init(rawValue:)) ?? .turnBackOn
        reopen = defaults.string(forKey: Keys.reopen).flatMap(KeepAwakeReopen.init(rawValue:)) ?? .carryOn
        let saved = defaults.data(forKey: Keys.lastLength).flatMap { try? JSONDecoder().decode(KeepAwakeLength.self, from: $0) }
        lastLength = saved.flatMap { KeepAwakeLength.choices.contains($0) ? $0 : nil } ?? .standard
        if defaults == UserDefaults.standard { Self.user = self }
    }

    func addListener(_ center: KeepAwakeCenter) {
        listeners.add(center)
    }

    private func changed() {
        for center in listeners.allObjects { center.settingsChanged() }
    }

    /// The user's own settings (the standard defaults), once they exist: practice copies show them.
    public private(set) static weak var user: KeepAwakeSettings?

    enum Keys {
        static let enabled = "keepAwake.enabled"
        static let screen = "keepAwake.screen"
        static let whileAgentsWork = "keepAwake.whileAgentsWork"
        static let whileConverting = "keepAwake.whileConverting"
        static let batteryCutoff = "keepAwake.batteryCutoff"
        static let lowBattery = "keepAwake.lowBattery"
        static let plugIn = "keepAwake.plugIn"
        static let reopen = "keepAwake.reopen"
        static let lastLength = "keepAwake.lastLength"
    }
}
