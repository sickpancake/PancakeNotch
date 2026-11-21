#if PANCAKENOTCH_INTERNAL_TESTING
import Foundation
import KeepAwakeCore
import notify
import Testing
@testable import PancakeNotch

/// The pretend battery for trying Keep Awake by hand (testing builds only).
@MainActor
struct FakeBatteryTests {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("fake-battery-\(UUID().uuidString)").path

    @Test func readsWhatTheScriptWrites() throws {
        try "battery 8\n".write(toFile: file, atomically: true, encoding: .utf8)
        #expect(FakeBattery.read(file) == PowerState(onBattery: true, percent: 8))
        try "plugged 8\n".write(toFile: file, atomically: true, encoding: .utf8)
        #expect(FakeBattery.read(file) == PowerState(onBattery: false, percent: 8))
        try "battery 250".write(toFile: file, atomically: true, encoding: .utf8)
        #expect(FakeBattery.read(file) == PowerState(onBattery: true, percent: 100))
        try FileManager.default.removeItem(atPath: file)
        #expect(FakeBattery.read(file) == PowerState(onBattery: false, percent: 100), "No file: plugged in and full")
    }

    @Test func hearsTheScript() async throws {
        let heard = HeardCount()
        FakeBattery.watch { heard.count += 1 }
        notify_post(FakeBattery.notification)
        for _ in 0..<200 where heard.count == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(heard.count >= 1)
    }

    final class HeardCount { var count = 0 }
}
#endif
