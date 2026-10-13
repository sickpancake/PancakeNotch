import Foundation
import Testing
@testable import Stats

/// A fixed calendar and time zone, so "midnight" means the same thing on every machine.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private func makeStore() -> StatsStore {
    StatsStore(url: nil, calendar: calendar)
}

@Suite("StatsStore")
struct StatsStoreTests {
    @Test func countersAreSplitAtLocalMidnight() async {
        let store = makeStore()
        store.recordNotchOpen(at: date(2026, 10, 10, 23, 59, 30))
        store.recordNotchOpen(at: date(2026, 10, 10, 23, 59, 59))
        store.recordNotchOpen(at: date(2026, 10, 11, 0, 0, 1))
        let summary = await store.summary(days: 7, now: date(2026, 10, 11, 9))
        #expect(summary.opensPerDay.suffix(2) == [2, 1])
        #expect(summary.opensPerDay.dropLast(2).allSatisfy { $0 == 0 })
        #expect(summary.totalOpens == 3)
    }

    @Test func usageCountersAddUp() async {
        let store = makeStore()
        let now = date(2026, 10, 11)
        store.recordShelved(count: 3, at: now)
        store.recordShelved(count: 2, at: date(2026, 10, 9))
        store.recordShelved(count: 0, at: now)
        store.recordAirDropped(count: 1, at: now)
        store.recordModuleShown("shelf", at: now)
        store.recordModuleShown("nowPlaying", at: now)
        store.recordModuleShown("nowPlaying", at: date(2026, 10, 8))
        let summary = await store.summary(days: 7, now: now)
        #expect(summary.shelved == 5)
        #expect(summary.airDropped == 1)
        #expect(summary.moduleUses.map(\.id) == ["nowPlaying", "shelf"])
        #expect(summary.moduleUses.map(\.count) == [2, 1])
        #expect(summary.moduleUses.first?.value == 2)
    }

    @Test func rangeExcludesOlderDays() async {
        let store = makeStore()
        let now = date(2026, 10, 11)
        store.recordNotchOpen(at: date(2026, 10, 4, 23)) // 8th day back: outside 7 days
        store.recordNotchOpen(at: date(2026, 10, 5, 0, 30)) // first of the 7 days
        let week = await store.summary(days: 7, now: now)
        #expect(week.totalOpens == 1)
        #expect(week.opensPerDay.first == 1)
        let month = await store.summary(days: 30, now: now)
        #expect(month.totalOpens == 2)
    }

    @Test func listeningIsRankedBySecondsAndCountedPerDay() async {
        let store = makeStore()
        let now = date(2026, 10, 11, 20)
        let today = date(2026, 10, 11, 9)
        let yesterday = date(2026, 10, 10, 22)
        store.recordListening(title: "Song A", artist: "Artist 1", album: "X", bundleID: "com.spotify.client", started: today, seconds: 200)
        store.recordListening(title: "Song A", artist: "Artist 1", album: "X", bundleID: "com.spotify.client", started: yesterday, seconds: 200)
        store.recordListening(title: "Song B", artist: "Artist 2", album: "Y", bundleID: "com.apple.Music", started: today, seconds: 300)
        store.recordListening(title: "Song C", artist: "Artist 1", album: "X", bundleID: nil, started: today, seconds: 50)
        store.recordListening(title: "Too short", artist: "Artist 3", album: "Z", bundleID: "com.apple.Music", started: today, seconds: 0.5)
        store.recordListening(title: "Broken", artist: "Artist 3", album: "Z", bundleID: "com.apple.Music", started: today, seconds: .nan)

        let summary = await store.summary(days: 7, now: now)
        #expect(summary.totalPlays == 4)
        #expect(summary.totalListeningSeconds == 750)
        #expect(summary.playsPerDay.suffix(2) == [1, 3])
        #expect(summary.listeningSecondsPerDay.suffix(2) == [200, 550])

        #expect(summary.topSongs.map(\.title) == ["Song A", "Song B", "Song C"])
        #expect(summary.topSongs[0].value == 400)
        #expect(summary.topSongs[0].count == 2)
        #expect(summary.topSongs[0].subtitle == "Artist 1")

        #expect(summary.topArtists.map(\.title) == ["Artist 1", "Artist 2"])
        #expect(summary.topArtists[0].value == 450)
        #expect(summary.topArtists[0].count == 3)

        #expect(summary.topApps.map(\.id) == ["com.spotify.client", "com.apple.Music"])
        #expect(summary.topApps.map(\.value) == [400, 300])
    }

    @Test func sameTitleByDifferentArtistsIsTwoSongs() async {
        let store = makeStore()
        let now = date(2026, 10, 11)
        store.recordListening(title: "Home", artist: "One", album: "", bundleID: nil, started: now, seconds: 60)
        store.recordListening(title: "Home", artist: "Two", album: "", bundleID: nil, started: now, seconds: 90)
        let summary = await store.summary(days: 7, now: now)
        #expect(summary.topSongs.count == 2)
        #expect(summary.topSongs.map(\.subtitle) == ["Two", "One"])
        #expect(Set(summary.topSongs.map(\.id)).count == 2)
    }

    @Test func topListsKeepFive() async {
        let store = makeStore()
        let now = date(2026, 10, 11)
        for index in 1...8 {
            store.recordListening(title: "Song \(index)", artist: "Artist \(index)", album: "", bundleID: "app.\(index)", started: now, seconds: Double(index * 10))
        }
        let summary = await store.summary(days: 7, now: now)
        #expect(summary.topSongs.count == 5)
        #expect(summary.topSongs.first?.title == "Song 8")
        #expect(summary.topArtists.count == 5)
        #expect(summary.topApps.count == 5)
        #expect(summary.totalPlays == 8)
    }

    @Test(arguments: [7, 30, 90])
    func daysAreAlignedAndEndToday(count: Int) async {
        let store = makeStore()
        let now = date(2026, 10, 11, 18)
        let summary = await store.summary(days: count, now: now)
        #expect(summary.days.count == count)
        #expect(summary.listeningSecondsPerDay.count == count)
        #expect(summary.playsPerDay.count == count)
        #expect(summary.opensPerDay.count == count)
        #expect(summary.days.last == calendar.startOfDay(for: now))
        #expect(summary.days.first == calendar.date(byAdding: .day, value: -(count - 1), to: calendar.startOfDay(for: now)))
        // One per calendar day, oldest first, each at local midnight.
        for (earlier, later) in zip(summary.days, summary.days.dropFirst()) {
            #expect(calendar.dateComponents([.day], from: earlier, to: later).day == 1)
            #expect(later == calendar.startOfDay(for: later))
        }
    }

    @Test func daysAcrossDaylightSavingChange() async {
        // Clocks go back on 25 Oct 2026 in Amsterdam: that day is 25 hours long.
        let store = makeStore()
        let summary = await store.summary(days: 7, now: date(2026, 10, 28))
        #expect(summary.days.count == 7)
        #expect(Set(summary.days.map { calendar.component(.day, from: $0) }) == Set(22...28))
        #expect(summary.days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
    }

    @Test func removeOldKeepsTheLastDays() async {
        let store = makeStore()
        let now = date(2026, 10, 11)
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -89, to: now)!
        let tooOld = calendar.date(byAdding: .day, value: -90, to: now)!
        for day in [tooOld, ninetyDaysAgo, now] {
            store.recordNotchOpen(at: day)
            store.recordListening(title: "Song", artist: "Artist", album: "", bundleID: nil, started: day, seconds: 60)
            store.recordHealth(HealthSample(date: day, footprintBytes: 1, helperFootprintBytes: 0, cpuPercent: 0))
        }
        store.removeOld(olderThan: 90, now: now)

        let summary = await store.summary(days: 90, now: now)
        #expect(summary.totalOpens == 2)
        #expect(summary.totalPlays == 2)
        #expect(summary.health.count == 2)
        // Nothing older is left behind either.
        let longer = await store.summary(days: 365, now: now)
        #expect(longer.totalOpens == 2)
        #expect(longer.totalPlays == 2)
        #expect(longer.health.count == 2)
    }

    @Test func clearRemovesEverything() async {
        let store = makeStore()
        let now = date(2026, 10, 11)
        store.recordNotchOpen(at: now)
        store.recordModuleShown("shelf", at: now)
        store.recordShelved(count: 2, at: now)
        store.recordListening(title: "Song", artist: "Artist", album: "", bundleID: "app", started: now, seconds: 60)
        store.recordHealth(HealthSample(date: now, footprintBytes: 1, helperFootprintBytes: 0, cpuPercent: 0))
        store.clear()
        let summary = await store.summary(days: 7, now: now)
        #expect(summary.totalOpens == 0)
        #expect(summary.totalPlays == 0)
        #expect(summary.moduleUses.isEmpty)
        #expect(summary.shelved == 0)
        #expect(summary.topSongs.isEmpty)
        #expect(summary.health.isEmpty)
        // Still works afterwards.
        store.recordNotchOpen(at: now)
        #expect(await store.summary(days: 7, now: now).totalOpens == 1)
    }

    @Test func healthIsThinnedEvenlyAndKeepsTheNewest() async {
        let store = makeStore()
        let now = date(2026, 10, 11, 23)
        let start = calendar.startOfDay(for: now)
        let total = 1_000
        for index in 0..<total {
            store.recordHealth(HealthSample(
                date: start.addingTimeInterval(Double(index) * 60),
                footprintBytes: UInt64(index),
                helperFootprintBytes: 5,
                cpuPercent: 0.5
            ))
        }
        let summary = await store.summary(days: 1, now: now)
        #expect(summary.health.count <= StatsSummary.maxHealthSamples)
        #expect(summary.health.count >= StatsSummary.maxHealthSamples / 2)
        #expect(summary.health.last?.footprintBytes == UInt64(total - 1))
        #expect(summary.health == summary.health.sorted { $0.date < $1.date })
        #expect(summary.health.first?.helperFootprintBytes == 5)
        #expect(summary.health.first?.totalFootprintBytes == (summary.health.first?.footprintBytes ?? 0) + 5)
    }

    @Test func customCountersForModules() async {
        let store = makeStore()
        let now = date(2026, 10, 11)
        store.recordCount(kind: "weather.lookups", key: "Amsterdam", count: 2, at: now)
        store.recordCount(kind: "weather.lookups", key: "Utrecht", at: now)
        let items = await store.counts(kind: "weather.lookups", days: 7, now: now)
        #expect(items.map(\.id) == ["Amsterdam", "Utrecht"])
        #expect(items.map(\.count) == [2, 1])
        // Doesn't leak into the built-in summary.
        #expect(await store.summary(days: 7, now: now).moduleUses.isEmpty)
    }

    @Test func persistsInAFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "StatsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "statistics.sqlite")
        let now = date(2026, 10, 11)
        do {
            let store = StatsStore(url: url, calendar: calendar)
            store.recordNotchOpen(at: now)
            _ = await store.summary(days: 1, now: now) // waits for the write
        }
        let reopened = StatsStore(url: url, calendar: calendar)
        #expect(await reopened.summary(days: 1, now: now).totalOpens == 1)
    }

    @Test func aCorruptFileIsStartedOver() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "StatsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "statistics.sqlite")
        try Data(repeating: 0x42, count: 4096).write(to: url)
        let now = date(2026, 10, 11)
        let store = StatsStore(url: url, calendar: calendar)
        store.recordNotchOpen(at: now)
        #expect(await store.summary(days: 1, now: now).totalOpens == 1)
    }

    @Test func defaultURLIsInApplicationSupport() {
        let url = StatsStore.defaultURL()
        #expect(url.lastPathComponent == "statistics.sqlite")
        #expect(url.deletingLastPathComponent().lastPathComponent == "PancakeNotch")
    }
}
