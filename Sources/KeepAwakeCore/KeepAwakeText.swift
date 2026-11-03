import Foundation

/// How Keep Awake says things, the same on the notch page, its ear, the menu bar menu and VoiceOver.
public enum KeepAwakeText {
    /// A length's button: "30 min", "1 hr", "Until I stop".
    public static func length(_ length: KeepAwakeLength) -> String {
        guard let seconds = length.seconds else { return String(localized: "Until I stop", comment: "Keep Awake length: no end") }
        return duration(seconds, style: .short)
    }

    /// A length in the menu bar menu: "30 Minutes", "1 Hour", "Until I Stop".
    public static func menuLength(_ length: KeepAwakeLength) -> String {
        guard let seconds = length.seconds else { return String(localized: "Until I Stop", comment: "Keep Awake menu: no end") }
        return duration(seconds, style: .full).capitalized
    }

    /// Time left, rounded up to the minute: "1 hr, 12 min left", "1 min left".
    public static func left(_ seconds: TimeInterval) -> String {
        let minutes = max(1, (seconds / 60).rounded(.up))
        return String(localized: "\(duration(minutes * 60, style: .short)) left", comment: "Keep Awake: time left")
    }

    /// Said by VoiceOver: "1 hour, 12 minutes".
    public static func spoken(_ seconds: TimeInterval) -> String {
        duration(max(1, (seconds / 60).rounded(.up)) * 60, style: .full)
    }

    /// An end time in the Mac's own 12/24-hour style: "3:42 PM" or "15:42".
    public static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private static func duration(_ seconds: TimeInterval, style: DateComponentsFormatter.UnitsStyle) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = style
        formatter.allowedUnits = [.hour, .minute]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: seconds) ?? ""
    }
}

/// What Keep Awake is doing, in words: a title, a detail and why.
public struct KeepAwakeStatus: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case off, holding, pausedForWork, batteryLow
    }

    public var kind: Kind
    /// "Keeping your Mac awake", "Keep Awake is off".
    public var title: String
    /// "Until 3:42 PM", "While an agent works", "Your Mac sleeps as usual".
    public var detail: String

    /// The status at `now`. The time left isn't in it (the page adds it, changing once a minute).
    @MainActor
    public init(_ center: KeepAwakeCenter) {
        if center.isHolding {
            kind = .holding
            title = String(localized: "Keeping your Mac awake", comment: "Keep Awake: on")
            if let session = center.session {
                detail = session.end.map { String(localized: "Until \(KeepAwakeText.time($0))", comment: "Keep Awake: when it ends") }
                    ?? String(localized: "Until you turn it off", comment: "Keep Awake: no end")
            } else {
                detail = Self.why(center.work)
            }
        } else if center.isEnabled, center.batteryLow {
            kind = .batteryLow
            let percent = center.power.percent ?? 0
            title = String(localized: "Battery low (\(percent)%)", comment: "Keep Awake: stopped for the battery")
            detail = String(localized: "Plug in to keep your Mac awake", comment: "Keep Awake: on a low battery")
        } else if center.pausedForWork {
            kind = .pausedForWork
            title = String(localized: "Off for now", comment: "Keep Awake: turned off while work runs")
            detail = String(localized: "Stays off until this work ends", comment: "Keep Awake: paused until the work ends")
        } else {
            kind = .off
            title = String(localized: "Keep Awake is off", comment: "Keep Awake: off")
            detail = String(localized: "Your Mac sleeps as usual", comment: "Keep Awake: off")
        }
    }

    static func why(_ work: KeepAwakeWork?) -> String {
        switch work {
        case .agents: String(localized: "While an agent works", comment: "Keep Awake: why it's on")
        case .converting: String(localized: "While a file converts", comment: "Keep Awake: why it's on")
        case .both: String(localized: "While an agent works and a file converts", comment: "Keep Awake: why it's on")
        case .finishing(let until): String(localized: "Work finished · stops at \(KeepAwakeText.time(until))", comment: "Keep Awake: the 2-minute tail")
        case nil: String(localized: "Until you turn it off", comment: "Keep Awake: no end")
        }
    }

    /// One short line for the Module Menu and the menu bar menu, or `nil` when it's off.
    @MainActor
    public static func short(_ center: KeepAwakeCenter) -> String? {
        let status = KeepAwakeStatus(center)
        switch status.kind {
        case .holding: return status.detail
        case .pausedForWork: return status.title
        case .batteryLow: return String(localized: "Battery low", comment: "Keep Awake: short status")
        case .off: return nil
        }
    }

    /// Read by VoiceOver: "Keep Awake on, until 3:42 PM, 1 hour, 12 minutes left".
    @MainActor
    public static func spoken(_ center: KeepAwakeCenter) -> String {
        let status = KeepAwakeStatus(center)
        guard status.kind == .holding else { return status.title + ", " + status.detail }
        var text = String(localized: "Keep Awake on, \(status.detail)", comment: "VoiceOver: Keep Awake's state")
        if let left = center.remaining(at: center.now) {
            text += ", " + String(localized: "\(KeepAwakeText.spoken(left)) left", comment: "VoiceOver: Keep Awake's time left")
        }
        return text
    }
}
