import Foundation

/// Follows the real accounts for `UsageCenter`: account folders, limits and the token history.
@MainActor
final class LiveUsageSources {
    private unowned let center: UsageCenter

    init(center: UsageCenter) {
        self.center = center
    }

    func start() {}
    func stop() {}
    func setVisible(_ visible: Bool) {}
    func refreshAccounts() {}
    func refreshTotals(accountIDs: [String], days: Int) {}
    func daily(days: Int, accountIDs: [String]) async -> [DailyUsage] { [] }
}
