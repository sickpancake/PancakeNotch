import Foundation
import SQLite3
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
        store.recordListening(title: "Song A", artist: "Artist 1", album: "X", bundleID: "com.spotify.client", kind: .listen, started: today, seconds: 200)
        store.recordListening(title: "Song A", artist: "Artist 1", album: "X", bundleID: "com.spotify.client", kind: .listen, started: yesterday, seconds: 200)
        store.recordListening(title: "Song B", artist: "Artist 2", album: "Y", bundleID: "com.apple.Music", kind: .listen, started: today, seconds: 300)
        store.recordListening(title: "Song C", artist: "Artist 1", album: "X", bundleID: nil, kind: .listen, started: today, seconds: 50)
        store.recordListening(title: "Too short", artist: "Artist 3", album: "Z", bundleID: "com.apple.Music", kind: .listen, started: today, seconds: 0.5)
        store.recordListening(title: "Broken", artist: "Artist 3", album: "Z", bundleID: "com.apple.Music", kind: .listen, started: today, seconds: .nan)

        let summary = await store.summary(days: 7, now: now)
        #expect(summary.listening.totalPlays == 4)
        #expect(summary.listening.totalSeconds == 750)
        #expect(summary.listening.playsPerDay.suffix(2) == [1, 3])
        #expect(summary.listening.secondsPerDay.suffix(2) == [200, 550])

        #expect(summary.listening.top.map(\.title) == ["Song A", "Song B", "Song C"])
        #expect(summary.listening.top[0].value == 400)
        #expect(summary.listening.top[0].count == 2)
        #expect(summary.listening.top[0].subtitle == "Artist 1")

        #expect(summary.listening.topCreators.map(\.title) == ["Artist 1", "Artist 2"])
        #expect(summary.listening.topCreators[0].value == 450)
        #expect(summary.listening.topCreators[0].count == 3)

        #expect(summary.listening.topApps.map(\.id) == ["com.spotify.client", "com.apple.Music"])
        #expect(summary.listening.topApps.map(\.value) == [400, 300])
    }

    @Test func listeningAndWatchingAreCountedApart() async {
        let store = makeStore()
        let now = date(2026, 10, 11, 20)
        store.recordListening(title: "Song", artist: "Band", album: "Album", bundleID: "com.spotify.client", kind: .listen, started: now, seconds: 200)
        store.recordListening(title: "Video", artist: "Channel", album: "", bundleID: "com.google.Chrome", kind: .watch, started: now, seconds: 600)
        store.recordListening(title: "Stream", artist: "Streamer", album: "", bundleID: "com.google.Chrome", kind: .watch, started: now, seconds: 900)

        let summary = await store.summary(days: 7, now: now)
        #expect(summary.listening.totalPlays == 1)
        #expect(summary.listening.totalSeconds == 200)
        #expect(summary.listening.top.map(\.title) == ["Song"])
        #expect(summary.listening.topCreators.map(\.title) == ["Band"])
        #expect(summary.listening.topApps.map(\.id) == ["com.spotify.client"])

        #expect(summary.watching.totalPlays == 2)
        #expect(summary.watching.totalSeconds == 1500)
        #expect(summary.watching.secondsPerDay.last == 1500)
        #expect(summary.watching.top.map(\.title) == ["Stream", "Video"])
        #expect(summary.watching.topCreators.map(\.title) == ["Streamer", "Channel"])
        #expect(summary.watching.topApps.map(\.id) == ["com.google.Chrome"])

        // An ad isn't counted at all.
        store.recordListening(title: "Buy now", artist: "Shop", album: "", bundleID: "com.spotify.client", kind: .ad, started: now, seconds: 30)
        let after = await store.summary(days: 7, now: now)
        #expect(after.listening == summary.listening && after.watching == summary.watching)
    }

    /// A file from before plays were sorted: browser videos move to Watching, music stays, ads go.
    @Test func olderPlaysAreSortedWhenTheFileIsUpgraded() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "StatsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "statistics.sqlite")
        let now = date(2026, 10, 11, 12)
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        let old = """
            CREATE TABLE counters (day TEXT NOT NULL, kind TEXT NOT NULL, key TEXT NOT NULL DEFAULT '',
                count INTEGER NOT NULL, PRIMARY KEY (day, kind, key)) WITHOUT ROWID;
            CREATE TABLE plays (day TEXT NOT NULL, started REAL NOT NULL, seconds REAL NOT NULL, title TEXT NOT NULL,
                artist TEXT NOT NULL, album TEXT NOT NULL, app TEXT);
            CREATE TABLE health (time REAL NOT NULL, footprint INTEGER NOT NULL, helper INTEGER NOT NULL, cpu REAL NOT NULL);
            CREATE TABLE ai_usage (account TEXT NOT NULL, id TEXT NOT NULL, day TEXT NOT NULL, model TEXT NOT NULL,
                input INTEGER NOT NULL, output INTEGER NOT NULL, cache_write INTEGER NOT NULL, cache_read INTEGER NOT NULL,
                cost REAL, PRIMARY KEY (account, id)) WITHOUT ROWID;
            CREATE TABLE ai_files (path TEXT PRIMARY KEY, size INTEGER NOT NULL, offset INTEGER NOT NULL,
                state TEXT NOT NULL DEFAULT '') WITHOUT ROWID;
            INSERT INTO plays VALUES ('2026-10-11', \(now.timeIntervalSince1970), 300, 'Hikaru edit', 'Bankai32', '', 'com.google.Chrome');
            INSERT INTO plays VALUES ('2026-10-11', \(now.timeIntervalSince1970), 200, 'A Song', 'Band', 'Album', 'com.google.Chrome');
            INSERT INTO plays VALUES ('2026-10-11', \(now.timeIntervalSince1970), 100, 'B Song', 'Band', 'B', 'com.spotify.client');
            INSERT INTO plays VALUES ('2026-10-11', \(now.timeIntervalSince1970), 30, 'Find fresh deals', 'A Shop', '', 'com.spotify.client');
            INSERT INTO plays VALUES ('2026-10-11', \(now.timeIntervalSince1970), 50, 'A Film', '', '', 'com.colliderli.iina');
            INSERT INTO plays VALUES ('2026-10-11', \(now.timeIntervalSince1970), 40, 'Mystery', '', '', NULL);
            PRAGMA user_version = 2;
            """
        #expect(sqlite3_exec(db, old, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        let store = StatsStore(url: url, calendar: calendar)
        let summary = await store.summary(days: 1, now: now)
        #expect(summary.watching.top.map(\.title) == ["Hikaru edit", "A Film"])
        #expect(summary.listening.top.map(\.title) == ["A Song", "B Song", "Mystery"])
        #expect(summary.listening.totalPlays == 3)
        #expect(summary.watching.totalPlays == 2)
        // New plays still go in after the upgrade.
        store.recordListening(title: "New", artist: "", album: "", bundleID: nil, kind: .watch, started: now, seconds: 10)
        #expect(await store.summary(days: 1, now: now).watching.totalPlays == 3)
    }

    @Test func sameTitleByDifferentArtistsIsTwoSongs() async {
        let store = makeStore()
        let now = date(2026, 10, 11)
        store.recordListening(title: "Home", artist: "One", album: "", bundleID: nil, kind: .listen, started: now, seconds: 60)
        store.recordListening(title: "Home", artist: "Two", album: "", bundleID: nil, kind: .listen, started: now, seconds: 90)
        let summary = await store.summary(days: 7, now: now)
        #expect(summary.listening.top.count == 2)
        #expect(summary.listening.top.map(\.subtitle) == ["Two", "One"])
        #expect(Set(summary.listening.top.map(\.id)).count == 2)
    }

    @Test func topListsKeepFive() async {
        let store = makeStore()
        let now = date(2026, 10, 11)
        for index in 1...8 {
            store.recordListening(title: "Song \(index)", artist: "Artist \(index)", album: "", bundleID: "app.\(index)", kind: .listen, started: now, seconds: Double(index * 10))
        }
        let summary = await store.summary(days: 7, now: now)
        #expect(summary.listening.top.count == 5)
        #expect(summary.listening.top.first?.title == "Song 8")
        #expect(summary.listening.topCreators.count == 5)
        #expect(summary.listening.topApps.count == 5)
        #expect(summary.listening.totalPlays == 8)
    }

    @Test(arguments: [7, 30, 90])
    func daysAreAlignedAndEndToday(count: Int) async {
        let store = makeStore()
        let now = date(2026, 10, 11, 18)
        let summary = await store.summary(days: count, now: now)
        #expect(summary.days.count == count)
        #expect(summary.listening.secondsPerDay.count == count)
        #expect(summary.listening.playsPerDay.count == count)
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
            store.recordListening(title: "Song", artist: "Artist", album: "", bundleID: nil, kind: .listen, started: day, seconds: 60)
            store.recordHealth(HealthSample(date: day, footprintBytes: 1, helperFootprintBytes: 0, cpuPercent: 0))
        }
        store.removeOld(olderThan: 90, now: now)

        let summary = await store.summary(days: 90, now: now)
        #expect(summary.totalOpens == 2)
        #expect(summary.listening.totalPlays == 2)
        #expect(summary.health.count == 2)
        // Nothing older is left behind either.
        let longer = await store.summary(days: 365, now: now)
        #expect(longer.totalOpens == 2)
        #expect(longer.listening.totalPlays == 2)
        #expect(longer.health.count == 2)
    }

    @Test func clearRemovesEverything() async {
        let store = makeStore()
        let now = date(2026, 10, 11)
        store.recordNotchOpen(at: now)
        store.recordModuleShown("shelf", at: now)
        store.recordShelved(count: 2, at: now)
        store.recordListening(title: "Song", artist: "Artist", album: "", bundleID: "app", kind: .listen, started: now, seconds: 60)
        store.recordHealth(HealthSample(date: now, footprintBytes: 1, helperFootprintBytes: 0, cpuPercent: 0))
        store.clear()
        let summary = await store.summary(days: 7, now: now)
        #expect(summary.totalOpens == 0)
        #expect(summary.listening.totalPlays == 0)
        #expect(summary.moduleUses.isEmpty)
        #expect(summary.shelved == 0)
        #expect(summary.listening.top.isEmpty)
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

    @Test func clearLeavesNothingOnDisk() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "StatsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "statistics.sqlite")
        let now = date(2026, 10, 11)
        let store = StatsStore(url: url, calendar: calendar)
        store.recordListening(title: "A Very Private Song", artist: "", album: "", bundleID: nil, kind: .listen, started: now, seconds: 60)
        _ = await store.summary(days: 1, now: now)
        store.clear()
        store.waitForWrites()

        // Neither the file nor its write-ahead log still holds the title.
        for path in [url.path, url.path + "-wal"] {
            let bytes = FileManager.default.contents(atPath: path) ?? Data()
            #expect(bytes.range(of: Data("A Very Private Song".utf8)) == nil, "\(path)")
        }
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
