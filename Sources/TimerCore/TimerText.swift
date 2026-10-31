import Foundation

/// How the Timer writes times: the countdown, the stopwatch, presets, end times and what VoiceOver says.
public enum TimerText {
    /// A countdown: "0:42", "4:59", "12:00", "1:04:59". Shows a second until it's really over, like a
    /// phone: 0.3 s left is "0:01", not "0:00".
    public static func countdown(_ seconds: TimeInterval) -> String {
        clock(Int(max(0, seconds).rounded(.up)))
    }

    /// A stopwatch in the ear: whole seconds, "0:42", "12:05", "1:02:03".
    public static func elapsed(_ seconds: TimeInterval) -> String {
        clock(Int(max(0, seconds).rounded(.down)))
    }

    /// A stopwatch in the open notch: "00:12.34", "12:05.10", "1:02:03.45".
    public static func precise(_ seconds: TimeInterval) -> String {
        // A hair over, so a lap of exactly 0.29 s (28.999… hundredths in binary) still shows 0.29.
        let hundredths = Int((max(0, seconds) * 100 + 1e-6).rounded(.down))
        let whole = hundredths / 100
        let fraction = String(format: "%02d", hundredths % 100)
        let hours = whole / 3600, minutes = whole / 60 % 60, secs = whole % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) + ".\(fraction)" }
        return String(format: "%02d:%02d", minutes, secs) + ".\(fraction)"
    }

    static func clock(_ total: Int) -> String {
        let hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }

    /// A preset's button: "5 min", "1 h", "1 h 30 min", "45 s", "2 min 30 s".
    public static func length(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: max(1, seconds.rounded())) ?? "\(Int(seconds)) s"
    }

    /// Said by VoiceOver: "4 minutes, 59 seconds".
    public static func spoken(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .dropAll
        let text = formatter.string(from: max(0, seconds.rounded())) ?? ""
        // Under half a second the formatter drops every unit and says nothing.
        if text.isEmpty {
            formatter.allowedUnits = [.second]
            formatter.zeroFormattingBehavior = .default
            return formatter.string(from: 0) ?? ""
        }
        return text
    }

    /// An end time in the Mac's own 12/24-hour style: "3:42 PM" or "15:42".
    public static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// The end time without AM/PM, for the tiny ear: "3:42" or "15:42".
    public static func shortTime(_ date: Date) -> String {
        let format = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "H:mm"
        let formatter = DateFormatter()
        formatter.dateFormat = format.replacingOccurrences(of: "a", with: "").trimmingCharacters(in: .whitespaces)
        return formatter.string(from: date)
    }

    /// A preset's label: its name and length ("Tea · 3 min"), or the length alone.
    public static func preset(_ preset: TimerPreset) -> String {
        preset.name.isEmpty ? length(preset.seconds) : "\(preset.name) · \(length(preset.seconds))"
    }
}
