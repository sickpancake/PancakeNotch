#if PANCAKENOTCH_INTERNAL_TESTING
import Foundation
import KeepAwakeCore
import notify

/// A pretend battery for trying Keep Awake's low-battery rules by hand on a full battery (testing builds only,
/// Package.swift). With `PANCAKENOTCH_FAKE_BATTERY=/file`, Keep Awake reads the battery from that file
/// ("battery 8" or "plugged 100") instead of IOKit. Write the file, then post `notification`
/// (`notifyutil -p <name>`), and the app reads it again: no polling.
enum FakeBattery {
    static let notification = "io.github.sickpancake.PancakeNotch.fakeBattery"

    static var path: String? { ProcessInfo.processInfo.environment["PANCAKENOTCH_FAKE_BATTERY"] }

    /// The pretend battery; plugged in at 100% until the file says otherwise.
    static func read(_ path: String) -> PowerState {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let words = text.split(whereSeparator: \.isWhitespace)
        let percent = words.count > 1 ? Int(words[1]).map { min(max($0, 0), 100) } : nil
        return PowerState(onBattery: words.first == "battery", percent: percent ?? 100)
    }

    @MainActor private static var token: Int32 = 0

    /// Calls `changed` on the main thread each time the script says the pretend battery changed.
    @MainActor static func watch(_ changed: @escaping @MainActor () -> Void) {
        notify_register_dispatch(notification, &token, .main) { _ in MainActor.assumeIsolated { changed() } }
    }
}
#endif
