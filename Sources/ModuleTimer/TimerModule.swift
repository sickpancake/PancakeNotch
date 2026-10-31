import AppKit
import NotchCore
import Observation
import SwiftUI
import TimerCore

/// The Timer in the notch (ADR-0040): a timer and a stopwatch, like a phone's. While one runs or waits it
/// takes the second ear with a draining ring and the time; a timer that ends plays a sound and opens the
/// notch on its Done card, and its ear says Done until it's stopped.
@MainActor
@Observable
public final class TimerModule: NotchModule {
    public let center: TimerCenter
    public let settings: TimerSettings

    @ObservationIgnored public private(set) weak var notch: NotchViewModel?

    /// The page the open notch shows when Timer and Stopwatch aren't side by side.
    var mode: TimerMode = .timer
    /// The wheels' time before Start. It's the center's, so it stays when the notch closes and Home's copy
    /// shows the same (TimerWheels.tla, WheelsKeepYourTime).
    var wheelSeconds: TimeInterval {
        get { center.customSeconds }
        set { center.customSeconds = newValue }
    }
    /// The wheel being typed into, if any: it keeps the notch open.
    var editing: TimerWheelUnit?
    /// Digits typed into the editing wheel so far.
    var typed = ""
    /// The timer finished while the open notch showed another module: a "Timer done" strip shows once
    /// it closes, unless the Done card was seen first (TimerAlarm.tla, PeekOnlyIfMissed).
    private(set) var peekPending = false
    /// The display is asleep: nothing ticks.
    private(set) var isDisplayAsleep = false
    /// Rendering off-screen: no ticking.
    @ObservationIgnored public var isSnapshot = false
    /// Whether this copy rings and opens the notch. Home's live copy shares the center but stays quiet.
    @ObservationIgnored private let presents: Bool
    /// Presets shown before the user's own (a practice timer's 10 seconds).
    @ObservationIgnored let extraPresets: [TimerPreset]
    @ObservationIgnored private var displayObservers: [any NSObjectProtocol] = []
    /// While typing: a click in another app, or switching apps, ends it (TimerWheels.tla, TypingOnlyWithKeys).
    @ObservationIgnored private var clickAwayMonitor: Any?
    @ObservationIgnored private var appSwitchObserver: (any NSObjectProtocol)?
    /// An old observation may already have queued its callback when this copy is reattached.
    @ObservationIgnored private var observationGeneration = 0

    public init(center: TimerCenter, settings: TimerSettings, presents: Bool = true, extraPresets: [TimerPreset] = []) {
        self.center = center
        self.settings = settings
        self.presents = presents
        self.extraPresets = extraPresets
        mode = Self.bestMode(center)
    }

    // MARK: NotchModule

    public var moduleID: String { "timer" }
    public var title: String { String(localized: "Timer", comment: "Module name") }
    public var symbol: String { "timer" }

    public var menuStatus: String? {
        let timer = center.timer
        switch timer.phase {
        case .running(let end): return String(localized: "Ends \(TimerText.time(end))", comment: "Module Menu status")
        case .paused: return String(localized: "Paused", comment: "Module Menu status: the timer")
        case .done: return String(localized: "Done", comment: "Module Menu status: the timer finished")
        case .idle: break
        }
        if center.stopwatch.isRunning { return String(localized: "Stopwatch running", comment: "Module Menu status") }
        if center.stopwatch.isStopped { return String(localized: "Stopwatch stopped", comment: "Module Menu status") }
        return nil
    }

    /// An ear while a timer or stopwatch runs or waits (unless the ear is off), and always while a timer
    /// is done, so a missed alarm stays in sight until it's stopped.
    public var isActive: Bool {
        center.timer.isDone || (settings.earPlacement != .off && center.hasActivity)
    }

    /// Opening the notch while a timer is done lands on its Done card.
    public var wantsFocus: Bool { center.timer.isDone }
    /// A finished timer takes #2 whatever the setting, so Done always has an ear.
    public var prefersSecondEar: Bool { settings.earPlacement == .second || center.timer.isDone }
    public var opensFromEar: Bool { true }
    public var holdsOpen: Bool { editing != nil }

    public var accessibilityStatus: String? {
        let now = center.now
        let timer = center.timer
        switch timer.phase {
        case .running: return String(localized: "Timer, \(TimerText.spoken(timer.remaining(at: now).rounded(.up))) left")
        // Rounded up, as the countdown shows it.
        case .paused: return String(localized: "Timer paused, \(TimerText.spoken(timer.remaining(at: now).rounded(.up))) left")
        case .done: return String(localized: "Timer done")
        case .idle: break
        }
        let elapsed = TimerText.spoken(center.stopwatch.elapsed(at: now).rounded(.down))
        if center.stopwatch.isRunning { return String(localized: "Stopwatch, \(elapsed)") }
        if center.stopwatch.isStopped { return String(localized: "Stopwatch stopped at \(elapsed)") }
        return nil
    }

    public func attach(to notch: NotchViewModel?) {
        observationGeneration += 1
        if self.notch !== notch { endEditing() }
        self.notch = notch
        guard notch != nil else {
            if presents { center.onFinish = nil }
            stopWatchingDisplay()
            endEditing()
            return
        }
        if presents { center.onFinish = { [weak self] in self?.timerFinished() } }
        watchDisplay()
        observe()
        notch?.activityChanged()
    }

    public func expandedView(layout: NotchLayout) -> AnyView {
        AnyView(TimerView(module: self, layout: TimerLayout(layout)))
    }

    public func compactEars(layout: NotchLayout) -> CompactEars? {
        let height = layout.geometry.compactHeight
        let width = layout.compactEarWidth
        return CompactEars(
            main: AnyView(TimerEar(module: self, role: .shared, width: width, height: height)),
            extra: AnyView(TimerEar(module: self, role: .companion, width: width, height: height)),
            soloMain: AnyView(TimerEar(module: self, role: .solo, width: width, height: height))
        )
    }

    public func peekView(layout: NotchLayout) -> AnyView? {
        center.timer.isDone ? AnyView(TimerPeek(module: self)) : nil
    }

    public func notchDidOpen() {
        mode = Self.bestMode(center)
        // The Done card is on screen: the finish has been seen.
        if center.timer.isDone, mode == .timer || settings.sideBySide { peekPending = false }
    }

    public func notchDidClose() {
        endEditing()
    }

    public func userSwitchedAway() {
        endEditing()
    }

    /// Key presses no longer reach the notch (another window took them): typing ends.
    public func keyFocusLost() {
        endEditing()
    }

    /// Whichever one runs; with both or neither, the one used last. A finished timer always wins.
    static func bestMode(_ center: TimerCenter) -> TimerMode {
        let timerBusy = !center.timer.isIdle, stopwatchBusy = !center.stopwatch.isIdle
        if center.timer.isDone { return .timer }
        if timerBusy != stopwatchBusy { return timerBusy ? .timer : .stopwatch }
        return center.lastMode
    }

    // MARK: Following the center

    /// Re-checks the ear whenever the timer, stopwatch or ear setting changes. Observation only.
    private func observe() {
        let generation = observationGeneration
        withObservationTracking {
            _ = isActive
            _ = settings.earPlacement
            _ = notch?.state
            _ = center.timer.isIdle
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.notch != nil, self.observationGeneration == generation else { return }
                // A timer started elsewhere (Home's copy shares the center): the wheels are gone, so typing
                // ends (TimerWheels.tla, TypingOnlyOnScreen).
                if !self.center.timer.isIdle { self.endEditing() }
                self.notch?.activityChanged()
                self.showPendingPeek()
                self.observe()
            }
        }
    }

    /// The notch closed after a finish it was showing another module for: tell once, under the notch.
    /// Stopped or restarted first in the app window (Home's copy shares the center), there's nothing to
    /// tell, and a strip already showing goes (TimerAlarm.tla, PeekTruthful).
    private func showPendingPeek() {
        guard let notch else { return }
        guard center.timer.isDone else {
            peekPending = false
            notch.endPeek(of: self)
            return
        }
        guard peekPending, notch.state != .expanded else { return }
        peekPending = false
        notch.peek(self, for: .seconds(4))
    }

    /// The timer just ran out (once per finish): sound, a tap, VoiceOver, and the Done card where it can
    /// be seen (TimerAlarm.tla). Open on this module: it shows in place. Open on another: a peek when it
    /// closes. Closed: it opens, over a full-screen app only if the setting says so.
    private func timerFinished() {
        TimerSound.play(settings.sound)
        if settings.hapticOnDone {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: String(localized: "Timer finished"), .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
        guard let notch else { return }
        notch.activityChanged()
        if notch.state == .expanded {
            if notch.selectedModule === self, !notch.showsMenu {
                endEditing()
                mode = .timer
            } else {
                peekPending = true
            }
        } else {
            notch.requestAttention(from: self, revealsInFullScreen: settings.fullScreenAlert == .showNotch)
        }
    }

    // MARK: Actions

    /// The presets the Timer page offers.
    var presets: [TimerPreset] { extraPresets + settings.presets }

    /// Runs a control's action: using the notch keeps the alert's close from shutting it.
    func user(_ action: () -> Void) {
        notch?.userInteracted()
        action()
    }

    func showMode(_ mode: TimerMode) {
        notch?.userInteracted()
        guard self.mode != mode else { return }
        endEditing()
        self.mode = mode
        // Reopening with nothing running comes back to the page last looked at.
        center.lastMode = mode
        center.onEvent?(.modeShown(mode))
        if mode == .timer, center.timer.isDone { peekPending = false }
    }

    func startPreset(_ preset: TimerPreset) {
        notch?.userInteracted()
        endEditing()
        center.startTimer(seconds: preset.seconds)
    }

    func startWheels() {
        notch?.userInteracted()
        commitTyping()
        endEditing()
        guard wheelSeconds >= 1 else { return }
        center.startCustom(seconds: wheelSeconds)
    }

    func stopTimer() {
        notch?.userInteracted()
        peekPending = false
        center.stopTimer()
    }

    func addMinute() {
        notch?.userInteracted()
        peekPending = false
        center.addMinute()
    }

    func repeatTimer() {
        notch?.userInteracted()
        peekPending = false
        center.repeatTimer()
    }

    /// Space: the main button of what's on screen.
    func primaryAction(_ mode: TimerMode) {
        notch?.userInteracted()
        switch mode {
        case .timer:
            switch center.timer.phase {
            case .idle: startWheels()
            case .running: center.pauseTimer()
            case .paused: center.resumeTimer()
            case .done: stopTimer()
            }
        case .stopwatch:
            if center.stopwatch.isRunning { center.stopStopwatch() } else { center.startStopwatch() }
        }
    }

    // MARK: Wheels

    /// Turns a wheel by `steps` (scroll, drag, arrow keys), wrapping like a real wheel. Turning another
    /// wheel than the one being typed into ends typing, so the next digit can't land on a wheel the hand left.
    func turn(_ unit: TimerWheelUnit, by steps: Int) {
        notch?.userInteracted()
        if editing == unit { commitTyping() } else { endEditing() }
        // A partial scroll already moved the hand to this wheel, even before it passes a number.
        guard steps != 0 else { return }
        wheelSeconds = unit.turned(wheelSeconds, by: steps)
    }

    /// A click on a wheel: type into it. The notch takes the keyboard so the digits reach it.
    func beginEditing(_ unit: TimerWheelUnit) {
        notch?.userInteracted()
        if editing != nil { commitTyping() }
        editing = unit
        typed = ""
        notch?.requestKeyFocus?()
        watchClicksAway()
    }

    func endEditing() {
        guard editing != nil else { return }
        commitTyping()
        editing = nil
        stopWatchingClicksAway()
        notch?.holdReleased()
    }

    private func watchClicksAway() {
        guard clickAwayMonitor == nil else { return }
        clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.endEditing() }
        }
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.endEditing() }
        }
    }

    private func stopWatchingClicksAway() {
        if let clickAwayMonitor { NSEvent.removeMonitor(clickAwayMonitor) }
        clickAwayMonitor = nil
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        appSwitchObserver = nil
    }

    private func commitTyping() {
        guard let editing, let value = Int(typed) else {
            typed = ""
            return
        }
        wheelSeconds = editing.setting(wheelSeconds, to: value)
        typed = ""
    }

    /// Keys while the notch has the keyboard. Typing into a wheel: digits, Delete, Tab, arrows, Return
    /// starts, Esc cancels the digits and stops typing. Otherwise: Space start/pause, L lap, R reset, Tab
    /// Timer ↔ Stopwatch (side by side: Space for the timer, S for the stopwatch), Return on the Done card
    /// stops it; a held key counts once. Alerts don't take keyboard focus from another app.
    /// ⌘, ⌥ and ⌃ shortcuts always pass.
    public func handleKey(_ event: NSEvent) -> Bool {
        // ⌘, ⌥ and ⌃ shortcuts aren't the Timer's (⌥L isn't a lap).
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        if let editing, center.timer.isIdle {
            return handleEditingKey(event, unit: editing)
        }
        // A held key is one press: holding L doesn't fire a lap 30 times a second, nor Space start/stop.
        if event.isARepeat {
            return [49, 36, 76, 48].contains(event.keyCode) || ["l", "r", "s"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "")
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        // Side by side, Space is the timer's and S the stopwatch's.
        let visible: TimerMode = settings.sideBySide ? .timer : mode
        switch event.keyCode {
        case 49: // Space
            primaryAction(visible)
            return true
        case 36, 76: // Return
            guard center.timer.isDone else { return false }
            stopTimer()
            return true
        case 48: // Tab
            guard !settings.sideBySide else { return false }
            showMode(mode == .timer ? .stopwatch : .timer)
            return true
        default:
            break
        }
        let stopwatchKeys = settings.sideBySide || mode == .stopwatch
        if key == "s", settings.sideBySide {
            primaryAction(.stopwatch)
            return true
        }
        if key == "l", stopwatchKeys, center.stopwatch.canLap {
            center.lap()
            return true
        }
        if key == "r", stopwatchKeys, center.stopwatch.isStopped {
            center.resetStopwatch()
            return true
        }
        return false
    }

    private func handleEditingKey(_ event: NSEvent, unit: TimerWheelUnit) -> Bool {
        let characters = event.charactersIgnoringModifiers ?? ""
        switch event.keyCode {
        case 53: // Esc: cancel the digits being typed, like leaving a text field with Esc
            typed = ""
            endEditing()
        case 36, 76: // Return
            startWheels()
        case 48: // Tab
            commitTyping()
            let all = TimerWheelUnit.allCases
            let index = all.firstIndex(of: unit) ?? 0
            let step = event.modifierFlags.contains(.shift) ? -1 : 1
            editing = all[(index + step + all.count) % all.count]
        case 51, 117: // Delete
            typed = String(typed.dropLast())
        case 126: // Up
            turn(unit, by: 1)
        case 125: // Down
            turn(unit, by: -1)
        default:
            guard characters.count == 1, let digit = characters.first, digit.isASCII, digit.isNumber else { return true }
            typed = typed.count >= 2 ? String(digit) : typed + String(digit)
            // Two digits fill a wheel: on to the next one, like typing a time.
            if typed.count == 2 {
                commitTyping()
                if let next = TimerWheelUnit(rawValue: unit.rawValue + 1) { editing = next }
            }
        }
        return true
    }

    /// The wheels' time with the digits being typed counted in: what Start would start.
    var pendingWheelSeconds: TimeInterval {
        guard let editing, let value = Int(typed) else { return wheelSeconds }
        return editing.setting(wheelSeconds, to: value)
    }

    /// Start starts something: the wheels (with any typed digits) say at least a second.
    var canStartWheels: Bool { pendingWheelSeconds >= 1 }

    /// The typed digits, or nil: the wheel shows them instead of its value while typing.
    func typedValue(for unit: TimerWheelUnit) -> String? {
        editing == unit && !typed.isEmpty ? typed : nil
    }

    /// The number a wheel shows, typed digits counted in: its neighbours are one less and one more
    /// (TimerWheels.tla, NeighboursFollowFace).
    func shownValue(for unit: TimerWheelUnit) -> Int {
        unit.value(of: pendingWheelSeconds)
    }

    /// A click elsewhere in the app window ends typing in a practice notch.
    public func clickedOutsidePreview() {
        endEditing()
    }

    // MARK: Display sleep

    private func watchDisplay() {
        guard displayObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        displayObservers = [
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isDisplayAsleep = true }
            },
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isDisplayAsleep = false }
            },
        ]
    }

    private func stopWatchingDisplay() {
        displayObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        displayObservers = []
        isDisplayAsleep = false
    }

    /// Whether the ear may tick now: shown (compact, awake, on screen) and something counts.
    var earTicks: Bool {
        !isSnapshot && !isDisplayAsleep && notch?.isOnScreen == true && notch?.state == .compact && notch?.earsAsleep == false
            && (center.timer.isRunning || (center.timer.isIdle && center.stopwatch.isRunning))
    }

    /// Practice and live pages also stop updating when their host window is hidden or covered.
    var pageTicks: Bool { !isSnapshot && !isDisplayAsleep && notch?.isOnScreen == true }
}

/// A wheel in the timer's custom time: hours, minutes or seconds.
enum TimerWheelUnit: Int, CaseIterable, Identifiable {
    case hours, minutes, seconds

    var id: Int { rawValue }
    var range: Int { self == .hours ? 24 : 60 }
    private var size: Int { self == .hours ? 3600 : self == .minutes ? 60 : 1 }

    func value(of total: TimeInterval) -> Int {
        let whole = Int(total.rounded())
        return self == .hours ? whole / 3600 : self == .minutes ? whole / 60 % 60 : whole % 60
    }

    /// Turns this wheel, wrapping (59 → 0), leaving the others alone.
    func turned(_ total: TimeInterval, by steps: Int) -> TimeInterval {
        let current = value(of: total)
        return total + TimeInterval((wrapped(current + steps) - current) * size)
    }

    /// A value on this wheel, wrapped round: 60 minutes is 0, -1 is 59.
    func wrapped(_ value: Int) -> Int {
        (value % range + range) % range
    }

    /// Sets this wheel to a typed value, clamped (75 minutes → 59).
    func setting(_ total: TimeInterval, to typed: Int) -> TimeInterval {
        let next = min(max(typed, 0), range - 1)
        return total + TimeInterval((next - value(of: total)) * size)
    }

    var label: String {
        switch self {
        case .hours: String(localized: "h", comment: "Timer wheel unit: hours")
        case .minutes: String(localized: "min", comment: "Timer wheel unit: minutes")
        case .seconds: String(localized: "s", comment: "Timer wheel unit: seconds")
        }
    }

    var spokenName: String {
        switch self {
        case .hours: String(localized: "Hours")
        case .minutes: String(localized: "Minutes")
        case .seconds: String(localized: "Seconds")
        }
    }
}

public extension TimerModule {
    /// A practice timer for the app window (Modules, Notch settings, the lesson): its own throwaway timer
    /// and stopwatch, the user's settings, and a 10-second preset to see Done without waiting.
    static func practice() -> TimerModule {
        let settings = TimerSettings.user ?? TimerSettings(defaults: UserDefaults(suiteName: "PracticeTimer") ?? .standard)
        let quick = TimerPreset(id: UUID(), seconds: 10, name: String(localized: "Try it", comment: "Practice timer preset name"))
        return TimerModule(center: TimerCenter(), settings: settings, extraPresets: [quick])
    }
}
