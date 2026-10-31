import Foundation
import Testing
@testable import AgentsCore

struct LimitResetTrackerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func limits(_ used: Double, end: Date, kind: UsageLimit.Kind = .session) -> AccountLimits {
        AccountLimits(state: .available, limits: [UsageLimit(kind: kind, usedPercent: used, resetsAt: end, window: nil)])
    }

    @Test func onlyUsedWindowsAnnounceAndOnlyOnce() {
        for used in [0.0, 0.5, 1.0, 80.0, 100.0] {
            var tracker = LimitResetTracker()
            let end = now.addingTimeInterval(10)
            #expect(tracker.observe(accountID: "a", limits: limits(used, end: end), now: now).isEmpty)
            let resets = tracker.check(now: end)
            #expect(resets.count == (used >= 1 ? 1 : 0))
            #expect(resets.first?.leftBefore == (used >= 1 ? 100 - used : nil))
            #expect(tracker.check(now: end.addingTimeInterval(5)).isEmpty)
            #expect(tracker.observe(accountID: "a", limits: limits(used, end: end), now: end).isEmpty)
        }
    }

    @Test func movingToANewWindowKeepsTheOldUsageAndStaleReadsCannotRollBack() {
        var tracker = LimitResetTracker()
        let end = now.addingTimeInterval(10)
        _ = tracker.observe(accountID: "a", limits: limits(95, end: end), now: now)
        let resets = tracker.observe(accountID: "a", limits: limits(2, end: end.addingTimeInterval(18_000)), now: end)
        #expect(resets.count == 1)
        #expect(resets.first?.leftBefore == 5)
        #expect(tracker.observe(accountID: "a", limits: limits(100, end: end), now: end).isEmpty)
        #expect(tracker.nextEnd(after: end) == end.addingTimeInterval(18_000))
    }

    @Test func timestampJitterAndClockRollbackDoNotRepeatAReset() {
        var tracker = LimitResetTracker()
        let end = now.addingTimeInterval(100)
        _ = tracker.observe(accountID: "a", limits: limits(40, end: end), now: now)
        #expect(tracker.observe(accountID: "a", limits: limits(60, end: end.addingTimeInterval(10)), now: now).isEmpty)
        #expect(tracker.check(now: end).isEmpty)
        #expect(tracker.check(now: end.addingTimeInterval(10)).count == 1)
        #expect(tracker.check(now: now).isEmpty)
        #expect(tracker.check(now: end.addingTimeInterval(30)).isEmpty)
    }

    @Test func aFullMinuteOfJitterIsStillTheSameWindowAndAPayPerTokenAccountStopsTracking() {
        var tracker = LimitResetTracker()
        let end = now.addingTimeInterval(100)
        _ = tracker.observe(accountID: "a", limits: limits(95, end: end), now: now)
        #expect(tracker.observe(accountID: "a", limits: limits(95, end: end.addingTimeInterval(60)), now: end).isEmpty)
        #expect(tracker.check(now: end.addingTimeInterval(60)).count == 1)
        #expect(tracker.observe(accountID: "a", limits: AccountLimits(state: .noLimits), now: end).isEmpty)
        #expect(tracker.windows.isEmpty)
        #expect(tracker.check(now: end.addingTimeInterval(1000)).isEmpty)
    }

    @Test func earlyRolloverPreservesTheOldUsedWindowUntilItsDeadline() {
        var tracker = LimitResetTracker()
        let end = now.addingTimeInterval(100)
        _ = tracker.observe(accountID: "a", limits: limits(95, end: end), now: now)
        #expect(tracker.observe(accountID: "a", limits: limits(0, end: end.addingTimeInterval(18_000)), now: now.addingTimeInterval(99)).isEmpty)
        #expect(tracker.nextEnd(after: now) == end)
        #expect(tracker.check(now: end).first?.leftBefore == 5)
        #expect(tracker.check(now: end).isEmpty)
    }

    @Test func firstReadAfterResetCatchesUpAndAllKindsAreCovered() {
        var tracker = LimitResetTracker()
        let kinds: [UsageLimit.Kind] = [.session, .weekly, .weeklyModel("Opus"), .weeklyModel("Sonnet")]
        for kind in kinds {
            let reset = tracker.observe(accountID: "a", limits: limits(50, end: now, kind: kind), now: now)
            #expect(reset.map(\.kind) == [kind])
        }
        #expect(Set(tracker.windows.keys).count == 4)
        tracker.keep(accountIDs: [])
        #expect(tracker.nextEnd(after: now) == nil)
    }
}

@MainActor
struct LimitResetDeliveryTests {
    func setup() -> (UsageCenter, UserDefaults, AgentAccount) {
        let defaults = UserDefaults(suiteName: "ResetTests.\(UUID().uuidString)")!
        defaults.set(true, forKey: "aiUsage.enabled")
        let settings = AgentsSettings(defaults: defaults)
        settings.warnsNearLimit = false
        let center = UsageCenter(settings: settings, stats: nil)
        let account = AgentAccount(tool: .claude, folder: URL(fileURLWithPath: "/tmp/reset-work"), plan: "Max", name: "Work")
        center.setAccounts([account])
        return (center, defaults, account)
    }
    func used(_ end: Date, kind: UsageLimit.Kind = .session) -> AccountLimits {
        AccountLimits(state: .available, limits: [UsageLimit(kind: kind, usedPercent: 92, resetsAt: end, window: nil)])
    }

    @Test func switchDefaultsOnAndPersistsItsChoice() {
        let (center, defaults, _) = setup()
        #expect(center.settings.peeksOnReset)
        center.settings.peeksOnReset = false
        #expect(!AgentsSettings(defaults: defaults).peeksOnReset)
        center.stop()
    }

    @Test func groupingWaitsOneMinuteAndSeparatesLaterResets() throws {
        let (center, _, account) = setup()
        defer { center.stop() }
        let now = Date()
        let other = AgentAccount(tool: .codex, folder: URL(fileURLWithPath: "/tmp/reset-home"), plan: "Plus", name: "Home")
        center.setAccounts([account, other])
        center.setLimits(used(now.addingTimeInterval(-65)), for: account.id)
        center.setLimits(used(now.addingTimeInterval(-10), kind: .weekly), for: other.id)
        let notice = try #require(center.nextResetNotice(now: now))
        #expect(notice.limitCount == 2 && notice.accounts.count == 2)
        center.resetNoticeStarted(notice)
        #expect(center.nextResetNotice(now: now) == nil)

        center.setLimits(used(now.addingTimeInterval(3600)), for: account.id)
        center.setLimits(used(now.addingTimeInterval(3661), kind: .weekly), for: other.id)
        center.timeMayHaveChanged(now: now.addingTimeInterval(3700))
        let first = try #require(center.nextResetNotice(now: now.addingTimeInterval(3700)))
        #expect(first.limitCount == 1)
        center.resetNoticeStarted(first)
        #expect(center.nextResetNotice(now: now.addingTimeInterval(3700)) == nil)
        #expect(center.nextResetNotice(now: now.addingTimeInterval(3730))?.items.first?.account.id == other.id)
    }

    @Test func freshnessIsCheckedAtDisplayAndFutureEventsWait() {
        let (center, _, account) = setup()
        defer { center.stop() }
        let now = Date()
        center.setLimits(used(now.addingTimeInterval(-60)), for: account.id)
        #expect(center.nextResetNotice(now: now.addingTimeInterval(-100)) == nil)
        #expect(center.nextResetNotice(now: now.addingTimeInterval(1740)) != nil)
        #expect(center.nextResetNotice(now: now.addingTimeInterval(1741)) == nil)
        #expect(center.pendingResets.isEmpty)
    }

    @Test func disablingEitherSwitchDiscardsWaitingResets() {
        for moduleOff in [false, true] {
            let (center, _, account) = setup()
            let end = Date().addingTimeInterval(-90)
            center.setLimits(used(end), for: account.id)
            #expect(!center.pendingResets.isEmpty)
            if moduleOff { center.settings.usageEnabled = false } else { center.settings.peeksOnReset = false }
            center.settings.usageEnabled = true
            center.settings.peeksOnReset = true
            #expect(center.nextResetNotice() == nil)
            center.timeMayHaveChanged()
            #expect(center.nextResetNotice() == nil)
            center.stop()
        }
    }

    @Test func quittingAcrossResetRecoversOldWindowEvenWhenToolAlreadyRolledForward() throws {
        let (first, defaults, account) = setup()
        let now = Date()
        first.setLimits(used(now.addingTimeInterval(-90)), for: account.id)
        first.stop() // Not displayed yet.
        let second = UsageCenter(settings: AgentsSettings(defaults: defaults), stats: nil)
        defer { second.stop() }
        second.setAccounts([account])
        second.setLimits(used(now.addingTimeInterval(18_000)), for: account.id)
        let notice = try #require(second.nextResetNotice())
        #expect(notice.items.first?.reset.endedAt == now.addingTimeInterval(-90))
        second.resetNoticeStarted(notice)
        let third = UsageCenter(settings: AgentsSettings(defaults: defaults), stats: nil)
        defer { third.stop() }
        third.setAccounts([account])
        third.setLimits(used(now.addingTimeInterval(-90)), for: account.id)
        #expect(third.nextResetNotice() == nil)
    }

    @Test func repeatedTimestampCorrectionsDelayDeliveryWithoutCreatingANewReset() throws {
        let (center, defaults, account) = setup()
        defer { center.stop() }
        let now = Date()
        let original = now.addingTimeInterval(-200)
        center.setLimits(used(original), for: account.id)
        for delta in [55.0, 110, 165, 220] {
            center.setLimits(used(original.addingTimeInterval(delta)), for: account.id)
        }
        #expect(center.nextResetNotice(now: now) == nil)
        center.timeMayHaveChanged(now: now.addingTimeInterval(100))
        let notice = try #require(center.nextResetNotice(now: now.addingTimeInterval(100)))
        #expect(notice.limitCount == 1)
        #expect(notice.items.first?.reset.identityAt == original)
        #expect(notice.items.first?.reset.endedAt == original.addingTimeInterval(220))
        center.resetNoticeStarted(notice)
        center.setLimits(used(original.addingTimeInterval(275)), for: account.id)
        center.timeMayHaveChanged(now: now.addingTimeInterval(200))
        #expect(center.nextResetNotice(now: now.addingTimeInterval(200)) == nil)
        let restarted = UsageCenter(settings: AgentsSettings(defaults: defaults), stats: nil)
        defer { restarted.stop() }
        restarted.setAccounts([account])
        restarted.timeMayHaveChanged(now: now.addingTimeInterval(200))
        #expect(restarted.nextResetNotice(now: now.addingTimeInterval(200)) == nil)
    }

    @Test func pendingResetSurvivesRolloverThenQuitWhileNotchWasBusy() throws {
        let (first, defaults, account) = setup()
        let now = Date()
        first.setLimits(used(now.addingTimeInterval(-90)), for: account.id)
        first.setLimits(used(now.addingTimeInterval(18_000)), for: account.id)
        first.stop()
        let second = UsageCenter(settings: AgentsSettings(defaults: defaults), stats: nil)
        defer { second.stop() }
        second.setAccounts([account])
        second.setLimits(used(now.addingTimeInterval(18_000)), for: account.id)
        let notice = try #require(second.nextResetNotice())
        #expect(notice.items.first?.reset.endedAt == now.addingTimeInterval(-90))
        second.resetNoticeStarted(notice)
        let third = UsageCenter(settings: AgentsSettings(defaults: defaults), stats: nil)
        defer { third.stop() }
        third.setAccounts([account])
        #expect(third.nextResetNotice() == nil)
    }

    @Test func turningBackOnSettlesElapsedWindowsBeforeALateWake() {
        let (center, _, account) = setup()
        defer { center.stop() }
        center.settings.peeksOnReset = false
        let end = Date().addingTimeInterval(0.02)
        center.setLimits(used(end), for: account.id)
        // No reset callback is needed: the preference change itself must settle the elapsed window.
        Thread.sleep(forTimeInterval: 0.06)
        center.settings.peeksOnReset = true
        center.timeMayHaveChanged(now: end.addingTimeInterval(90))
        #expect(center.nextResetNotice(now: end.addingTimeInterval(90)) == nil)
    }

    @Test func accountRemovalDropsItsWaitingReset() {
        let (center, _, account) = setup()
        defer { center.stop() }
        center.setLimits(used(Date().addingTimeInterval(-90)), for: account.id)
        center.setAccounts([])
        #expect(center.nextResetNotice() == nil)
    }
}

@MainActor
struct ResetEnableBoundaryTests {
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    func fixture() -> (UsageCenter, AgentsSettings, UserDefaults, Clock, AgentAccount) {
        let defaults = UserDefaults(suiteName: "ResetBoundary.\(UUID().uuidString)")!
        defaults.set(true, forKey: "aiUsage.enabled") // Already enabled before this launch.
        let clock = Clock()
        let settings = AgentsSettings(defaults: defaults, now: { clock.now })
        settings.warnsNearLimit = false
        let center = UsageCenter(settings: settings, stats: nil)
        let account = AgentAccount(tool: .claude, folder: URL(fileURLWithPath: "/tmp/reset-boundary"), plan: "Pro")
        center.setAccounts([account])
        return (center, settings, defaults, clock, account)
    }

    func used(_ end: Date, kind: UsageLimit.Kind = .session) -> AccountLimits {
        AccountLimits(state: .available, limits: [UsageLimit(kind: kind, usedPercent: 80, resetsAt: end, window: nil)])
    }

    @Test(arguments: [false, true])
    func firstFileAfterTurningBackOnDoesNotReviveAnOffTimeReset(moduleSwitch: Bool) {
        let (center, settings, _, clock, account) = fixture()
        defer { center.stop() }
        if moduleSwitch { settings.usageEnabled = false } else { settings.peeksOnReset = false }
        let endedWhileOff = clock.now.addingTimeInterval(10)
        clock.now += 20
        if moduleSwitch { settings.usageEnabled = true } else { settings.peeksOnReset = true }
        center.setLimits(used(endedWhileOff), for: account.id, now: clock.now)
        #expect(center.pendingResets.isEmpty)
        #expect(center.nextResetNotice(now: clock.now.addingTimeInterval(60)) == nil)
        // A later, enabled window is still announced normally.
        let nextEnd = clock.now.addingTimeInterval(300)
        center.setLimits(used(nextEnd), for: account.id, now: clock.now)
        center.timeMayHaveChanged(now: nextEnd)
        #expect(center.nextResetNotice(now: nextEnd.addingTimeInterval(60))?.limitCount == 1)
    }

    @Test func enableBoundarySurvivesRelaunchAndOlderFirstReads() {
        let (center, settings, defaults, clock, account) = fixture()
        settings.peeksOnReset = false
        let endedWhileOff = clock.now.addingTimeInterval(10)
        clock.now += 20
        settings.peeksOnReset = true
        center.stop()
        let restored = AgentsSettings(defaults: defaults, now: { clock.now })
        #expect(restored.resetNoticesEnabledAfter == clock.now)
        let restarted = UsageCenter(settings: restored, stats: nil)
        defer { restarted.stop() }
        restarted.setAccounts([account])
        restarted.setLimits(used(endedWhileOff), for: account.id, now: clock.now)
        #expect(restarted.nextResetNotice(now: clock.now.addingTimeInterval(60)) == nil)
    }

    @Test func enabledBoundaryNeverMovesBackwardWithTheClock() {
        let (center, settings, _, clock, _) = fixture()
        defer { center.stop() }
        settings.peeksOnReset = false
        settings.peeksOnReset = true
        let firstBoundary = settings.resetNoticesEnabledAfter
        clock.now -= 3600
        settings.peeksOnReset = false
        settings.peeksOnReset = true
        #expect(settings.resetNoticesEnabledAfter == firstBoundary)
    }

    @Test func displayedWatermarkSurvivesFutureReadAndRollback() throws {
        let (center, settings, defaults, clock, account) = fixture()
        defer { center.stop() }
        let end = clock.now.addingTimeInterval(-90)
        center.setLimits(used(end), for: account.id, now: clock.now)
        let notice = try #require(center.nextResetNotice(now: clock.now))
        center.resetNoticeStarted(notice)
        let key = try #require(notice.items.first?.reset.key)
        let watermark = settings.handledResets[key]
        clock.now += 3 * 86_400
        let future = UsageCenter(settings: AgentsSettings(defaults: defaults, now: { clock.now }), stats: nil)
        future.setAccounts([account])
        future.setLimits(used(end), for: account.id, now: clock.now)
        #expect(future.settings.handledResets[key] == watermark)
        future.stop()
        clock.now = end.addingTimeInterval(70)
        let rolledBack = UsageCenter(settings: AgentsSettings(defaults: defaults, now: { clock.now }), stats: nil)
        defer { rolledBack.stop() }
        rolledBack.setAccounts([account])
        rolledBack.setLimits(used(end), for: account.id, now: clock.now)
        #expect(rolledBack.nextResetNotice(now: clock.now) == nil)
    }
}
