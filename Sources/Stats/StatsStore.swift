import Foundation

/// Writes and reads the statistics database (ADR-0018). Thread-safe: every call is queued on one
/// private serial queue, so `record…` returns at once and never blocks the main thread, and a
/// `summary` asked for after a write always sees it.
///
/// Everything stays in one SQLite file on this Mac; nothing is ever sent anywhere (ADR-0016).
/// Days are local calendar days. Nothing here runs on a timer: rows are written when something
/// happens.
public final class StatsStore: Sendable {
    /// How many days of statistics are kept (and the longest range the page shows).
    public static let retentionDays = 90

    let database: Database
    let queue = DispatchQueue(label: "io.github.sickpancake.PancakeNotch.stats", qos: .utility)
    let calendar: Calendar

    /// Gregorian days in the Mac's current time zone (followed as it changes, e.g. after a flight), so
    /// day keys sort the same for every user.
    public static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    /// `~/Library/Application Support/PancakeNotch/statistics.sqlite`. Creates the folder.
    public static func defaultURL() -> URL {
        #if PANCAKENOTCH_INTERNAL_TESTING
        if let path = ProcessInfo.processInfo.environment["PANCAKENOTCH_STATS_FILE"] {
            return URL(fileURLWithPath: path)
        }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appending(path: "PancakeNotch", directoryHint: .isDirectory)
        // Only this user may look inside: it holds statistics and AI Usage history.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return folder.appending(path: "statistics.sqlite", directoryHint: .notDirectory)
    }

    /// - Parameters:
    ///   - url: the database file; nil keeps everything in memory (tests, snapshots).
    ///   - calendar: decides where days begin; the user's calendar and time zone by default.
    public init(url: URL?, calendar: Calendar = StatsStore.localCalendar) {
        database = Database(url: url)
        self.calendar = calendar
    }

    /// Waits until every queued write is in the file. Only for quitting: it blocks the caller.
    public func waitForWrites() {
        queue.sync {}
    }

    // MARK: - Recording (fire and forget)

    public func recordNotchOpen(at date: Date = .now) {
        recordCount(kind: Kind.open, at: date)
    }

    /// A module was shown in the open notch: "nowPlaying", "shelf" (more later).
    public func recordModuleShown(_ moduleID: String, at date: Date = .now) {
        recordCount(kind: Kind.module, key: moduleID, at: date)
    }

    /// Files (or other items) put on the Shelf.
    public func recordShelved(count: Int, at date: Date = .now) {
        recordCount(kind: Kind.shelved, count: count, at: date)
    }

    public func recordAirDropped(count: Int, at date: Date = .now) {
        recordCount(kind: Kind.airDropped, count: count, at: date)
    }

    /// Adds `count` to a daily counter. Modules can use their own `kind` for their own statistics
    /// and read them back with `counts(kind:days:now:)`.
    public func recordCount(kind: String, key: String = "", count: Int = 1, at date: Date = .now) {
        guard count > 0 else { return }
        let day = dayKey(date)
        queue.async { [database] in
            database.run(
                """
                INSERT INTO counters (day, kind, key, count) VALUES (?, ?, ?, ?)
                ON CONFLICT (day, kind, key) DO UPDATE SET count = count + excluded.count
                """,
                [.text(day), .text(kind), .text(key), .integer(Int64(count))]
            )
        }
    }

    /// One song listened to: `seconds` is the time it actually played, counted on the day it
    /// started. Each call counts as one play; plays shorter than a second are ignored.
    /// The caller decides what's worth a play (for example, skipped after a few seconds).
    public func recordListening(title: String, artist: String, album: String, bundleID: String?, started: Date, seconds: Double) {
        guard seconds.isFinite, seconds >= 1 else { return }
        let day = dayKey(started)
        let clamped = min(seconds, 24 * 60 * 60)
        let app: SQLValue = bundleID.map { $0.isEmpty ? .null : .text($0) } ?? .null
        queue.async { [database] in
            database.run(
                "INSERT INTO plays (day, started, seconds, title, artist, album, app) VALUES (?, ?, ?, ?, ?, ?, ?)",
                [.text(day), .real(started.timeIntervalSince1970), .real(clamped), .text(title), .text(artist), .text(album), app]
            )
        }
    }

    public func recordHealth(_ sample: HealthSample) {
        queue.async { [database] in
            database.run(
                "INSERT INTO health (time, footprint, helper, cpu) VALUES (?, ?, ?, ?)",
                [
                    .real(sample.date.timeIntervalSince1970),
                    .integer(Int64(clamping: sample.footprintBytes)),
                    .integer(Int64(clamping: sample.helperFootprintBytes)),
                    .real(sample.cpuPercent.isFinite ? sample.cpuPercent : 0),
                ]
            )
        }
    }

    // MARK: - Housekeeping

    /// Deletes everything from before the last `days` calendar days (today included), so a
    /// `summary(days:)` of the same length still sees all it shows. Call at launch.
    public func removeOld(olderThan days: Int = StatsStore.retentionDays, now: Date = .now) {
        let first = firstDay(of: max(days, 1), now: now)
        let key = dayKey(first)
        let time = first.timeIntervalSince1970
        queue.async { [database] in
            database.run("DELETE FROM counters WHERE day < ?", [.text(key)])
            database.run("DELETE FROM plays WHERE day < ?", [.text(key)])
            database.run("DELETE FROM health WHERE time < ?", [.real(time)])
            database.run("DELETE FROM ai_usage WHERE day < ?", [.text(key)])
        }
    }

    /// Deletes all statistics, and compacts the file so the old rows are really gone from disk. How far
    /// the AI tools' logs were read is kept, so cleared AI usage isn't read back in.
    public func clear() {
        queue.async { [database] in
            database.execute("DELETE FROM counters; DELETE FROM plays; DELETE FROM health; DELETE FROM ai_usage;")
            database.execute("VACUUM")
            // Empties the write-ahead log too, so no old row waits there either.
            database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    // MARK: - Reading

    /// The last `days` local calendar days, today included.
    public func summary(days: Int, now: Date = .now) async -> StatsSummary {
        let dayStarts = dayStarts(count: max(days, 1), now: now)
        let keys = dayStarts.map(dayKey)
        return await withCheckedContinuation { continuation in
            queue.async { [database] in
                continuation.resume(returning: Self.makeSummary(database, dayStarts: dayStarts, keys: keys))
            }
        }
    }

    /// A counter recorded with `recordCount(kind:…)`, summed per key over the last `days` days,
    /// largest first. `value` and `count` are the sum; `id` and `title` the key.
    public func counts(kind: String, days: Int, now: Date = .now) async -> [RankedItem] {
        let keys = dayStarts(count: max(days, 1), now: now).map(dayKey)
        return await withCheckedContinuation { continuation in
            queue.async { [database] in
                continuation.resume(returning: Self.ranked(database, kind: kind, from: keys[0], to: keys[keys.count - 1]))
            }
        }
    }

    // MARK: - Private

    private enum Kind {
        static let open = "open"
        static let module = "module"
        static let shelved = "shelved"
        static let airDropped = "airdrop"
    }

    /// How many entries the top lists keep.
    private static let topCount = 5

    /// "2026-10-11": sorts like the dates it stands for, so ranges are simple string comparisons.
    func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func firstDay(of count: Int, now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
    }

    func dayStarts(count: Int, now: Date) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().map { offset in
            calendar.date(byAdding: .day, value: -offset, to: today) ?? today
        }
    }

    /// Runs on the queue.
    private static func makeSummary(_ database: Database, dayStarts: [Date], keys: [String]) -> StatsSummary {
        let from = keys[0]
        let to = keys[keys.count - 1]
        let range: [SQLValue] = [.text(from), .text(to)]
        let index = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
        var summary = StatsSummary(
            days: dayStarts,
            listeningSecondsPerDay: Array(repeating: 0, count: keys.count),
            playsPerDay: Array(repeating: 0, count: keys.count),
            opensPerDay: Array(repeating: 0, count: keys.count)
        )

        // Listening.
        database.query(
            "SELECT day, SUM(seconds), COUNT(*) FROM plays WHERE day >= ? AND day <= ? GROUP BY day",
            range
        ) { row in
            guard let position = index[row.text(0)] else { return }
            summary.listeningSecondsPerDay[position] = row.real(1)
            summary.playsPerDay[position] = Int(row.integer(2))
        }
        summary.totalListeningSeconds = summary.listeningSecondsPerDay.reduce(0, +)
        summary.totalPlays = summary.playsPerDay.reduce(0, +)

        database.query(
            """
            SELECT title, artist, SUM(seconds) AS total, COUNT(*) FROM plays
            WHERE day >= ? AND day <= ? AND title != ''
            GROUP BY title, artist ORDER BY total DESC, title LIMIT \(topCount)
            """,
            range
        ) { row in
            let title = row.text(0)
            let artist = row.text(1)
            summary.topSongs.append(RankedItem(
                id: title + "\u{1F}" + artist,
                title: title,
                subtitle: artist.isEmpty ? nil : artist,
                value: row.real(2),
                count: Int(row.integer(3))
            ))
        }
        database.query(
            """
            SELECT artist, SUM(seconds) AS total, COUNT(*) FROM plays
            WHERE day >= ? AND day <= ? AND artist != ''
            GROUP BY artist ORDER BY total DESC, artist LIMIT \(topCount)
            """,
            range
        ) { row in
            let artist = row.text(0)
            summary.topArtists.append(RankedItem(id: artist, title: artist, value: row.real(1), count: Int(row.integer(2))))
        }
        database.query(
            """
            SELECT app, SUM(seconds) AS total, COUNT(*) FROM plays
            WHERE day >= ? AND day <= ? AND app IS NOT NULL AND app != ''
            GROUP BY app ORDER BY total DESC, app LIMIT \(topCount)
            """,
            range
        ) { row in
            let app = row.text(0)
            summary.topApps.append(RankedItem(id: app, title: app, value: row.real(1), count: Int(row.integer(2))))
        }

        // Usage.
        database.query(
            "SELECT day, kind, SUM(count) FROM counters WHERE day >= ? AND day <= ? AND kind IN (?, ?, ?) GROUP BY day, kind",
            range + [.text(Kind.open), .text(Kind.shelved), .text(Kind.airDropped)]
        ) { row in
            let count = Int(row.integer(2))
            switch row.text(1) {
            case Kind.open:
                if let position = index[row.text(0)] { summary.opensPerDay[position] = count }
            case Kind.shelved: summary.shelved += count
            case Kind.airDropped: summary.airDropped += count
            default: break
            }
        }
        summary.totalOpens = summary.opensPerDay.reduce(0, +)
        summary.moduleUses = ranked(database, kind: Kind.module, from: from, to: to)

        // App health.
        summary.health = health(database, since: dayStarts[0])
        return summary
    }

    private static func ranked(_ database: Database, kind: String, from: String, to: String) -> [RankedItem] {
        var items: [RankedItem] = []
        database.query(
            """
            SELECT key, SUM(count) AS total FROM counters
            WHERE day >= ? AND day <= ? AND kind = ?
            GROUP BY key ORDER BY total DESC, key
            """,
            [.text(from), .text(to), .text(kind)]
        ) { row in
            let count = Int(row.integer(1))
            items.append(RankedItem(id: row.text(0), title: row.text(0), value: Double(count), count: count))
        }
        return items
    }

    /// Samples since `start`, oldest first. Keeps every n-th so at most `maxHealthSamples` come
    /// back, without loading the rest into memory.
    private static func health(_ database: Database, since start: Date) -> [HealthSample] {
        let since: [SQLValue] = [.real(start.timeIntervalSince1970)]
        var total = 0
        database.query("SELECT COUNT(*) FROM health WHERE time >= ?", since) { total = Int($0.integer(0)) }
        guard total > 0 else { return [] }
        let limit = StatsSummary.maxHealthSamples
        let stride = (total + limit - 1) / limit
        var samples: [HealthSample] = []
        samples.reserveCapacity(min(total, limit))
        var position = 0
        database.query("SELECT time, footprint, helper, cpu FROM health WHERE time >= ? ORDER BY time", since) { row in
            // Count from the newest, so the latest sample is always kept.
            if (total - 1 - position) % stride == 0 {
                samples.append(HealthSample(
                    date: Date(timeIntervalSince1970: row.real(0)),
                    footprintBytes: UInt64(clamping: row.integer(1)),
                    helperFootprintBytes: UInt64(clamping: row.integer(2)),
                    cpuPercent: row.real(3)
                ))
            }
            position += 1
        }
        return samples
    }
}
