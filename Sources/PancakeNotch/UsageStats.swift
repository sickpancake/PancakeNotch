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
    /// Times the notch opened today. Reads 0 after midnight even before the next open.
    var opensToday: Int { Self.dayKey(now()) == day ? countOnDay : 0 }
    /// When PancakeNotch first ran on this Mac.
    let firstLaunch: Date

    private var day: String
    /// Opens counted on `day`.
    private var countOnDay: Int

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        let today = Self.dayKey(now())
        opensTotal = defaults.integer(forKey: Keys.opensTotal)
        let savedDay = defaults.string(forKey: Keys.day)
        countOnDay = savedDay == today ? defaults.integer(forKey: Keys.opensToday) : 0
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
            countOnDay = 0
        }
        opensTotal += 1
        countOnDay += 1
        defaults.set(opensTotal, forKey: Keys.opensTotal)
        defaults.set(countOnDay, forKey: Keys.opensToday)
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
