import Foundation
import os
import SQLite3

/// A value bound to a `?` in a statement.
enum SQLValue {
    case text(String)
    case real(Double)
    case integer(Int64)
    case null
}

/// One result row while a query steps through it. Only valid inside the `query` callback.
struct SQLRow {
    fileprivate let statement: OpaquePointer

    func text(_ column: Int32) -> String {
        guard let raw = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: raw)
    }

    func optionalText(_ column: Int32) -> String? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : text(column)
    }

    func real(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func integer(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
}

/// A small wrapper around the system SQLite library (no third-party wrapper, ADR-0018).
///
/// Not thread-safe by itself: `StatsStore` only touches it from its private serial queue, which is
/// why it's marked `@unchecked Sendable`. The file is opened lazily on that queue, so creating a
/// store on the main thread never waits on the disk.
final class Database: @unchecked Sendable {
    /// Bumped when the tables change; `migrate()` brings older files up to date.
    static let schemaVersion: Int64 = 2

    private let url: URL?
    private var handle: OpaquePointer?
    private var didOpen = false
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "stats")

    init(url: URL?) {
        self.url = url
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    /// The open connection, or nil when even an in-memory database couldn't be made.
    private var connection: OpaquePointer? {
        if !didOpen {
            didOpen = true
            handle = openBest()
        }
        return handle
    }

    /// Opens the file. Only a damaged file is set aside (renamed, never deleted) and started over; any
    /// other problem (disk full, another copy of the app busy with it) keeps statistics in memory for
    /// this run and leaves the file alone.
    private func openBest() -> OpaquePointer? {
        if let url {
            var code: Int32 = SQLITE_OK
            if let db = open(path: url.path, code: &code) { return db }
            if code == SQLITE_CORRUPT || code == SQLITE_NOTADB {
                logger.error("Statistics file damaged (\(code)), setting it aside and starting over")
                let aside = url.path + ".damaged"
                try? FileManager.default.removeItem(atPath: aside)
                try? FileManager.default.moveItem(atPath: url.path, toPath: aside)
                for suffix in ["-journal", "-wal", "-shm"] {
                    try? FileManager.default.removeItem(atPath: url.path + suffix)
                }
                if let db = open(path: url.path, code: &code) { return db }
            }
            logger.error("Statistics file can't be opened (\(code)), keeping statistics in memory for now")
        }
        var code: Int32 = SQLITE_OK
        return open(path: ":memory:", code: &code)
    }

    private func open(path: String, code: inout Int32) -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        code = sqlite3_open_v2(path, &db, flags, nil)
        guard code == SQLITE_OK, let db else {
            if let db { sqlite3_close_v2(db) }
            return nil
        }
        // Another copy of the app (a development build) may be writing: wait a moment instead of failing.
        sqlite3_busy_timeout(db, 2000)
        // A small page cache (256 KiB instead of 2 MiB): the tables are tiny and memory counts (ADR-0006).
        guard exec(db, "PRAGMA cache_size = -256"), migrate(db) else {
            code = sqlite3_extended_errcode(db) & 0xFF
            sqlite3_close_v2(db)
            return nil
        }
        // Write-ahead logging: each write appends to a small log instead of creating, syncing and
        // deleting a journal file. A power cut can lose the last moments of statistics, not the file.
        _ = exec(db, "PRAGMA journal_mode = WAL")
        _ = exec(db, "PRAGMA synchronous = NORMAL")
        _ = exec(db, "PRAGMA journal_size_limit = 1048576")
        return db
    }

    private func migrate(_ db: OpaquePointer) -> Bool {
        var version: Int64 = 0
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
           sqlite3_step(statement) == SQLITE_ROW {
            version = sqlite3_column_int64(statement, 0)
        }
        sqlite3_finalize(statement)
        if version >= Self.schemaVersion { return true }
        // Version 1: daily counters, plays and health samples.
        if version < 1, !exec(db, """
            BEGIN;
            CREATE TABLE IF NOT EXISTS counters (
                day TEXT NOT NULL,
                kind TEXT NOT NULL,
                key TEXT NOT NULL DEFAULT '',
                count INTEGER NOT NULL,
                PRIMARY KEY (day, kind, key)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS plays (
                day TEXT NOT NULL,
                started REAL NOT NULL,
                seconds REAL NOT NULL,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                album TEXT NOT NULL,
                app TEXT
            );
            CREATE INDEX IF NOT EXISTS plays_day ON plays (day);
            CREATE TABLE IF NOT EXISTS health (
                time REAL NOT NULL,
                footprint INTEGER NOT NULL,
                helper INTEGER NOT NULL,
                cpu REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS health_time ON health (time);
            PRAGMA user_version = 1;
            COMMIT;
            """) { return false }
        // Version 2: AI token counts per message (ADR-0037) and how far each AI tool's log has been read.
        // `cost` is NULL for models without a known price.
        return exec(db, """
            BEGIN;
            CREATE TABLE IF NOT EXISTS ai_usage (
                account TEXT NOT NULL,
                id TEXT NOT NULL,
                day TEXT NOT NULL,
                model TEXT NOT NULL,
                input INTEGER NOT NULL,
                output INTEGER NOT NULL,
                cache_write INTEGER NOT NULL,
                cache_read INTEGER NOT NULL,
                cost REAL,
                PRIMARY KEY (account, id)
            ) WITHOUT ROWID;
            CREATE INDEX IF NOT EXISTS ai_usage_day ON ai_usage (day, account);
            CREATE TABLE IF NOT EXISTS ai_files (
                path TEXT PRIMARY KEY,
                size INTEGER NOT NULL,
                offset INTEGER NOT NULL,
                state TEXT NOT NULL DEFAULT ''
            ) WITHOUT ROWID;
            PRAGMA user_version = 2;
            COMMIT;
            """)
    }

    private func exec(_ db: OpaquePointer, _ sql: String) -> Bool {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            logger.error("SQLite: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        return true
    }

    /// Runs one or more statements without parameters.
    @discardableResult
    func execute(_ sql: String) -> Bool {
        guard let db = connection else { return false }
        return exec(db, sql)
    }

    /// Runs a statement that returns no rows.
    @discardableResult
    func run(_ sql: String, _ values: [SQLValue] = []) -> Bool {
        withStatement(sql, values) { statement in
            sqlite3_step(statement) == SQLITE_DONE
        } ?? false
    }

    /// Steps through every row of a query.
    func query(_ sql: String, _ values: [SQLValue] = [], row: (SQLRow) -> Void) {
        _ = withStatement(sql, values) { statement in
            while sqlite3_step(statement) == SQLITE_ROW {
                row(SQLRow(statement: statement))
            }
        }
    }

    private func withStatement<T>(_ sql: String, _ values: [SQLValue], _ body: (OpaquePointer) -> T) -> T? {
        guard let db = connection else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            logger.error("SQLite prepare: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            return nil
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
            case .real(let number): sqlite3_bind_double(statement, index, number)
            case .integer(let number): sqlite3_bind_int64(statement, index, number)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return body(statement)
    }
}

/// Tells SQLite to copy bound text, since Swift's temporary C string goes away after the call.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
