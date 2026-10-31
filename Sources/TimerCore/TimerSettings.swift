import Foundation
import Observation

/// Which ear a running timer or stopwatch takes (ADR-0040).
public enum TimerEarPlacement: String, CaseIterable, Sendable {
    /// The second ear (#2), whatever its rank: the first module keeps its place.
    case second
    /// Like every other module: its place in the ranking decides.
    case ranking
    /// No ear: the notch stays closed while it runs.
    case off
}

/// What the closed ear shows while a timer runs.
public enum TimerEarContent: String, CaseIterable, Sendable {
    case ringAndTime, time, ring, endTime
}

/// How the digits change.
public enum TimerDigitAnimation: String, CaseIterable, Sendable {
    /// Each digit rolls over like a drum (a horizontal cylinder).
    case drum
    /// Each digit slides up or down.
    case slide
    case off
}

/// What a finish does while a full-screen app hides the notch.
public enum TimerFullScreenAlert: String, CaseIterable, Sendable {
    /// The notch appears over the full-screen app with the Done card, then hides again.
    case showNotch
    case soundOnly
}

/// A quick-start time on the Timer page, with an optional name ("Tea").
public struct TimerPreset: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var seconds: TimeInterval
    public var name: String

    public init(id: UUID = UUID(), seconds: TimeInterval, name: String = "") {
        self.id = id
        self.seconds = seconds
        self.name = name
    }
}

/// The Timer's options in the app window (Modules page). Stored in `UserDefaults`.
@MainActor
@Observable
public final class TimerSettings {
    public static let defaultPresetMinutes: [Double] = [5, 10, 15, 30, 60]
    public static let mostPresets = 12
    /// The alert sound when nothing was chosen yet; one of macOS's own.
    public static let defaultSound = "Glass"

    public var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Keys.enabled) } }
    public var earPlacement: TimerEarPlacement { didSet { defaults.set(earPlacement.rawValue, forKey: Keys.earPlacement) } }
    public var earContent: TimerEarContent { didSet { defaults.set(earContent.rawValue, forKey: Keys.earContent) } }
    public var digitAnimation: TimerDigitAnimation { didSet { defaults.set(digitAnimation.rawValue, forKey: Keys.digitAnimation) } }
    /// Timer and Stopwatch side by side in the open notch instead of a switch.
    public var sideBySide: Bool { didSet { defaults.set(sideBySide, forKey: Keys.sideBySide) } }
    /// A sound from /System/Library/Sounds, or "" for no sound.
    public var sound: String { didSet { defaults.set(sound, forKey: Keys.sound) } }
    public var hapticOnDone: Bool { didSet { defaults.set(hapticOnDone, forKey: Keys.hapticOnDone) } }
    public var fullScreenAlert: TimerFullScreenAlert { didSet { defaults.set(fullScreenAlert.rawValue, forKey: Keys.fullScreenAlert) } }
    /// The quick-start times, in the user's order. Never empty after Reset; at most `mostPresets`.
    public var presets: [TimerPreset] {
        didSet {
            if presets.count > Self.mostPresets { presets = Array(presets.prefix(Self.mostPresets)) }
            if let data = try? JSONEncoder().encode(presets) { defaults.set(data, forKey: Keys.presets) }
        }
    }

    @ObservationIgnored let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        earPlacement = defaults.string(forKey: Keys.earPlacement).flatMap(TimerEarPlacement.init(rawValue:)) ?? .second
        earContent = defaults.string(forKey: Keys.earContent).flatMap(TimerEarContent.init(rawValue:)) ?? .ringAndTime
        digitAnimation = defaults.string(forKey: Keys.digitAnimation).flatMap(TimerDigitAnimation.init(rawValue:)) ?? .drum
        sideBySide = defaults.object(forKey: Keys.sideBySide) as? Bool ?? false
        // A chosen sound this Mac no longer has (renamed in a macOS update) would ring silently: Glass then.
        let savedSound = defaults.string(forKey: Keys.sound) ?? Self.defaultSound
        sound = savedSound.isEmpty || TimerSound.url(for: savedSound) != nil ? savedSound : Self.defaultSound
        hapticOnDone = defaults.object(forKey: Keys.hapticOnDone) as? Bool ?? true
        fullScreenAlert = defaults.string(forKey: Keys.fullScreenAlert).flatMap(TimerFullScreenAlert.init(rawValue:)) ?? .showNotch
        let saved = defaults.data(forKey: Keys.presets).flatMap { try? JSONDecoder().decode([TimerPreset].self, from: $0) }
        presets = saved.map(Self.cleaned) ?? Self.defaultPresets
        if defaults == UserDefaults.standard { Self.user = self }
    }

    /// The user's own settings (the standard defaults), once they exist: practice timers show them.
    public private(set) static weak var user: TimerSettings?

    public static var defaultPresets: [TimerPreset] {
        defaultPresetMinutes.map { TimerPreset(seconds: $0 * 60) }
    }

    public var canAddPreset: Bool { presets.count < Self.mostPresets }

    /// The presets are the defaults, unnamed: Reset would change nothing.
    public var hasDefaultPresets: Bool {
        presets.map(\.seconds) == Self.defaultPresetMinutes.map { $0 * 60 } && presets.allSatisfy { $0.name.isEmpty }
    }

    /// Adds a time (rounded to whole seconds, 1 s to 23:59:59) at the end. Returns whether it was added.
    @discardableResult
    public func addPreset(seconds: TimeInterval, name: String = "") -> Bool {
        let length = min(CountdownTimer.longest, seconds.rounded())
        guard canAddPreset, length >= 1 else { return false }
        presets.append(TimerPreset(seconds: length, name: Self.cleanName(name)))
        return true
    }

    public func removePreset(_ id: UUID) {
        presets.removeAll { $0.id == id }
    }

    public func renamePreset(_ id: UUID, to name: String) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = Self.cleanName(name)
    }

    /// Moves a preset to `index` (clamped), for drag and the arrow buttons.
    public func movePreset(_ id: UUID, to index: Int) {
        guard let from = presets.firstIndex(where: { $0.id == id }) else { return }
        var next = presets
        let preset = next.remove(at: from)
        next.insert(preset, at: min(max(index, 0), next.count))
        if next != presets { presets = next }
    }

    public func resetPresets() {
        presets = Self.defaultPresets
    }

    /// Names stay short (one line in a small button) and lose surrounding spaces.
    static func cleanName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
    }

    /// Saved presets from an older or edited file: valid lengths only, at most `mostPresets`.
    static func cleaned(_ presets: [TimerPreset]) -> [TimerPreset] {
        let valid = presets.filter { $0.seconds >= 1 && $0.seconds <= CountdownTimer.longest }
            .map { TimerPreset(id: $0.id, seconds: $0.seconds.rounded(), name: cleanName($0.name)) }
        return Array(valid.prefix(mostPresets))
    }

    enum Keys {
        static let enabled = "timer.enabled"
        static let earPlacement = "timer.earPlacement"
        static let earContent = "timer.earContent"
        static let digitAnimation = "timer.digitAnimation"
        static let sideBySide = "timer.sideBySide"
        static let sound = "timer.sound"
        static let hapticOnDone = "timer.hapticOnDone"
        static let fullScreenAlert = "timer.fullScreenAlert"
        static let presets = "timer.presets"
    }
}
