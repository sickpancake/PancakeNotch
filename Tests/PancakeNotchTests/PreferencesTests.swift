import Foundation
import Testing
@testable import PancakeNotch

@MainActor
struct PreferencesTests {
    @Test func clickOnlyDefaultsOffAndPersistsWithoutChangingDelays() throws {
        let suite = "PancakeNotch.PreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        #expect(!preferences.openOnClickOnly)
        #expect(!preferences.notchBehavior.openOnClickOnly)
        preferences.openDelayMilliseconds = 420
        preferences.openOnClickOnly = true
        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.openOnClickOnly)
        #expect(reloaded.notchBehavior.openOnClickOnly)
        #expect(reloaded.notchBehavior.openDelay == .milliseconds(420))
        #expect(reloaded.closeDelayMilliseconds == Preferences.defaultCloseDelay)
        reloaded.openOnClickOnly = false
        #expect(!Preferences(defaults: defaults).notchBehavior.openOnClickOnly)
    }
}
