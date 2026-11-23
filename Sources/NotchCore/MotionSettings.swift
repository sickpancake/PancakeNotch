import AppKit
import Observation
import SwiftUI

/// Calmer motion: fades instead of springs, slides, wiggles and bouncing bars (issue #99). It's on while
/// the Mac's Reduce Motion is on (System Settings › Accessibility › Display) or PancakeNotch's own switch
/// is (Settings › General). Views read the result as `accessibilityReduceMotion`, because each window's
/// root hands it down with `followsMotionSettings()`; models read `MotionSettings.shared.reducesMotion`.
@MainActor
@Observable
public final class MotionSettings {
    /// The app's settings, saved in the standard defaults and following the Mac's switch.
    public static let shared = MotionSettings()

    /// Posted (object: the settings) when `reducesMotion` changes, for models that keep motion state.
    public static let didChangeNotification = Notification.Name("PancakeNotchReduceMotionDidChange")

    static let key = "reduceMotion"

    /// PancakeNotch's own switch. Off by default, so the app moves as before unless the Mac asks.
    public var reduceMotionInApp: Bool {
        didSet {
            defaults.set(reduceMotionInApp, forKey: Self.key)
            announceIfChanged()
        }
    }

    /// The Mac's Reduce Motion, kept current while the app runs.
    public private(set) var macReducesMotion: Bool

    /// What the whole app follows: either switch.
    public var reducesMotion: Bool { reduceMotionInApp || macReducesMotion }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let readMacSetting: () -> Bool
    @ObservationIgnored private var announced: Bool
    @ObservationIgnored private var listening: Listening?

    /// - Parameters:
    ///   - readMacSetting: the Mac's switch (tests pass their own).
    ///   - macChanges: where the Mac says its accessibility display options changed; `nil` doesn't listen.
    public init(
        defaults: UserDefaults = .standard,
        readMacSetting: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
        macChanges: NotificationCenter? = NSWorkspace.shared.notificationCenter
    ) {
        self.defaults = defaults
        self.readMacSetting = readMacSetting
        let own = defaults.bool(forKey: Self.key), mac = readMacSetting()
        reduceMotionInApp = own
        macReducesMotion = mac
        announced = own || mac
        guard let macChanges else { return }
        let token = macChanges.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.macSettingChanged() }
        }
        listening = Listening(center: macChanges, token: token)
    }

    /// A click on the Settings switch, which shows `reducesMotion`. While the Mac's switch is on it shows on
    /// and is locked: a click then changes nothing, and your own choice stays for when the Mac's goes off.
    public func switchClicked(toReduce reduce: Bool) {
        guard !macReducesMotion else { return }
        reduceMotionInApp = reduce
    }

    /// Reads the Mac's switch again (called when it says its options changed).
    public func macSettingChanged() {
        let now = readMacSetting()
        if now != macReducesMotion { macReducesMotion = now }
        announceIfChanged()
    }

    private func announceIfChanged() {
        guard reducesMotion != announced else { return }
        announced = reducesMotion
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

public extension View {
    /// Hands the app's Reduce Motion (the Mac's switch or PancakeNotch's own) to every view below as
    /// `accessibilityReduceMotion`, so each `@Environment(\.accessibilityReduceMotion)` follows both. Put it
    /// on the root view of every window and off-screen picture.
    func followsMotionSettings(_ settings: MotionSettings = .shared) -> some View {
        modifier(FollowsMotionSettings(settings: settings))
    }

    /// `transition` for content changing in place (rolling digits, a symbol swap), or a plain cross-fade
    /// with Reduce Motion.
    func motionContentTransition(_ transition: ContentTransition) -> some View {
        modifier(MotionContentTransition(transition: transition))
    }
}

/// Stops listening when its owner goes away (tests make their own settings and notches).
final class Listening: @unchecked Sendable {
    let center: NotificationCenter
    let token: any NSObjectProtocol

    init(center: NotificationCenter, token: any NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    deinit { center.removeObserver(token) }
}

/// Calls back on the main actor, right away, each time `object` posts `name` on the default center.
/// Listening stops when the token goes away.
@MainActor
final class NotificationToken {
    private let listening: Listening

    init(observing name: Notification.Name, from object: AnyObject, _ action: @escaping @MainActor () -> Void) {
        let center = NotificationCenter.default
        let token = center.addObserver(forName: name, object: object, queue: nil) { _ in
            MainActor.assumeIsolated { action() }
        }
        listening = Listening(center: center, token: token)
    }
}

private struct FollowsMotionSettings: ViewModifier {
    let settings: MotionSettings

    func body(content: Content) -> some View {
        // `accessibilityReduceMotion` is read-only; SwiftUI keeps the value it returns in this one.
        content.environment(\._accessibilityReduceMotion, settings.reducesMotion)
    }
}

private struct MotionContentTransition: ViewModifier {
    let transition: ContentTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .opacity : transition)
    }
}
