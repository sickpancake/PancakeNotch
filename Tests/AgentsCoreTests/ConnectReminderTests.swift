import FileWatching
import Foundation
import Testing
@testable import AgentsCore

/// The reminder to connect Devin when it's on this Mac (issue #78).
@MainActor
struct ConnectReminderTests {
    private let suite = "ConnectReminderTests.\(UUID().uuidString)"

    private func settings() -> AgentsSettings {
        AgentsSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    /// A fake home with `~/.config` (as most Macs have), and a reminder over it.
    private func reminder(home: URL, settings: AgentsSettings) -> ConnectReminder {
        let connector = AgentConnector(settings: settings, home: home)
        // An Applications folder of its own, so a Devin app installed on this Mac doesn't count.
        let applications = home.appending(path: "Applications-test").path
        try? FileManager.default.createDirectory(atPath: applications, withIntermediateDirectories: true)
        return ConnectReminder(settings: settings, home: home, applications: applications) { connector }
    }

    private func addDevin(_ home: URL) throws {
        try FileManager.default.createDirectory(at: home.appending(path: ".config/devin"), withIntermediateDirectories: true)
    }

    @Test func nothingToRemindAboutUntilDevinIsFound() throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appending(path: ".config"), withIntermediateDirectories: true)
        let settings = settings()
        let reminder = reminder(home: home, settings: settings)
        var asked: [AgentTool] = []
        reminder.onRemind = { asked.append($0); return true }

        reminder.check()
        #expect(reminder.tool == nil)
        #expect(reminder.isWatching)
        #expect(asked.isEmpty)

        try addDevin(home)
        reminder.check()
        #expect(reminder.tool == .devin)
        #expect(!reminder.isWatching)
        #expect(asked == [.devin])
        #expect(settings.notchRemindedTools == [.devin])

        // The strip shows once; the row and card stay until answered.
        reminder.check()
        #expect(asked == [.devin])
        #expect(reminder.tool == .devin)
    }

    @Test func devinAppearingWakesTheWatchWithoutPolling() async throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appending(path: ".config"), withIntermediateDirectories: true)
        let settings = settings()
        let reminder = reminder(home: home, settings: settings)
        var asked: [AgentTool] = []
        reminder.onRemind = { asked.append($0); return true }
        reminder.check()
        #expect(reminder.isWatching)
        // Let the watcher arm on its queue before the folder appears.
        try await Task.sleep(for: .milliseconds(100))

        try addDevin(home)
        for _ in 0..<50 where reminder.tool == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(reminder.tool == .devin)
        #expect(asked == [.devin])
        #expect(!reminder.isWatching)
    }

    @Test func installingTheDevinAppIsNoticed() async throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let reminder = reminder(home: home, settings: settings())
        reminder.check()
        #expect(reminder.tool == nil)
        try await Task.sleep(for: .milliseconds(100))

        try FileManager.default.createDirectory(at: home.appending(path: "Applications-test/Devin.app/Contents"), withIntermediateDirectories: true)
        for _ in 0..<50 where reminder.tool == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(reminder.tool == .devin)
    }

    @Test func aStripThatCouldNotShowIsTriedAgainNextTime() throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        try addDevin(home)
        let settings = settings()
        let reminder = reminder(home: home, settings: settings)
        var answer = false
        var asked = 0
        reminder.onRemind = { _ in asked += 1; return answer }

        reminder.check()
        #expect(asked == 1)
        #expect(settings.notchRemindedTools.isEmpty)
        answer = true
        reminder.check()
        #expect(asked == 2)
        #expect(settings.notchRemindedTools == [.devin])
        reminder.check()
        #expect(asked == 2)
    }

    @Test func notNowQuietsDevinForGoodButNotTheWholeOffer() throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        try addDevin(home)
        let settings = settings()
        // Dismissing the first "We found Claude Code…" card doesn't stop Devin's reminder.
        settings.offerDismissed = true
        let reminder = reminder(home: home, settings: settings)
        reminder.check()
        #expect(reminder.tool == .devin)

        reminder.notNow()
        #expect(reminder.tool == nil)
        #expect(!reminder.isWatching)
        let relaunched = self.reminder(home: home, settings: self.settings())
        var asked = 0
        relaunched.onRemind = { _ in asked += 1; return true }
        relaunched.check()
        #expect(relaunched.tool == nil)
        #expect(asked == 0)
    }

    @Test func connectedOnceMeansNoMoreRemindersEvenAfterDisconnect() throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        try addDevin(home)
        let settings = settings()
        let connector = AgentConnector(settings: settings, home: home)
        let reminder = ConnectReminder(settings: settings, home: home) { connector }
        // Connected in Agents' settings (or by hand), not from the reminder.
        try HookFile.update(AccountFinder.devinConfigFile(home: home), kind: .devin, connect: true)
        reminder.check()
        #expect(connector.state(.devin) == .connected)
        #expect(reminder.tool == nil)
        #expect(settings.connectRemindersDone.contains(.devin))

        #expect(connector.disconnect(.devin))
        #expect(connector.state(.devin) == .notConnected)
        reminder.check()
        #expect(reminder.tool == nil)
    }

    @Test func previewConnectsAndThenSaysWhatToDoNext() {
        let settings = settings()
        let reminder = ConnectReminder.preview(.devin, settings: settings)
        #expect(reminder.tool == .devin)
        #expect(reminder.connect())
        #expect(reminder.tool == nil)
        #expect(reminder.justConnected == .devin)
        #expect(settings.connectRemindersDone.contains(.devin))
        reminder.finish()
        #expect(reminder.justConnected == nil)
        #expect(!ConnectReminder.preview(nil, settings: self.settings()).connect())
    }

    @Test func watcherWatchesTheNearestFolderThatExists() throws {
        let home = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        // Neither `~/.config` nor `~/.local/share` yet: both fall back to the home folder, watched once.
        let watcher = FolderEntryWatcher(paths: [home.appending(path: ".config/devin").path,
                                                 home.appending(path: ".local/share/devin").path],
                                         queue: DispatchQueue(label: "test")) {}
        defer { watcher.stop() }
        #expect(watcher.watchedCount == 1)
    }
}
