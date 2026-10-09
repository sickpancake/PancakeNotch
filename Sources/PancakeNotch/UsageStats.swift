import Foundation
import Observation

/// Small usage counters for the Home page. Stored only on this Mac, in `UserDefaults`.
@MainActor
@Observable
final class UsageStats {
    private let defaults: UserDefaults
    private let now: () -> Date

    /// Times the notch opened, ever.
    private(set) var opensTotal: Int
    /// Times the notch opened today.
    private(set) var opensToday: Int
    /// When PancakeNotch first ran on this Mac.
    let firstLaunch: Date

    private var day: String

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        let today = Self.dayKey(now())
        opensTotal = defaults.integer(forKey: Keys.opensTotal)
        let savedDay = defaults.string(forKey: Keys.day)
        opensToday = savedDay == today ? defaults.integer(forKey: Keys.opensToday) : 0
        day = today
        if let saved = defaults.object(forKey: Keys.firstLaunch) as? Date {
            firstLaunch = saved
        } else {
            firstLaunch = now()
            defaults.set(firstLaunch, forKey: Keys.firstLaunch)
        }
    }

    func recordOpen() {
        let today = Self.dayKey(now())
        if today != day {
            day = today
            opensToday = 0
        }
        opensTotal += 1
        opensToday += 1
        defaults.set(opensTotal, forKey: Keys.opensTotal)
        defaults.set(opensToday, forKey: Keys.opensToday)
        defaults.set(day, forKey: Keys.day)
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private enum Keys {
        static let opensTotal = "stats.opensTotal"
        static let opensToday = "stats.opensToday"
        static let day = "stats.day"
        static let firstLaunch = "stats.firstLaunch"
    }
}
