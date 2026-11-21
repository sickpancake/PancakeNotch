import AppKit
import CoreServices

/// Why a script didn't work.
enum ScriptFailure: Error, Equatable, Sendable {
    /// The user said no to "PancakeNotch wants to control Music" (Automation privacy setting, error -1743).
    case notPermitted
    case failed(code: Int)
}

/// Runs AppleScript on one private serial queue, never the main thread: the first time, macOS asks the
/// user for permission and blocks the calling thread until they answer.
///
/// `@unchecked Sendable`: the compiled scripts are only touched on `queue`.
final class AppleScriptRunner: @unchecked Sendable {
    static let notPermitted = -1743
    /// "Would need to ask the user" (AEDeterminePermissionToAutomateTarget).
    static let wouldAsk = -1744

    private let queue = DispatchQueue(label: "io.github.sickpancake.PancakeNotch.nowplaying.applescript", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]

    /// Runs `source`, turns the result into a value with `parse` (still on the script queue) and hands it
    /// to `completion` on the main thread.
    func run<Value: Sendable>(
        _ source: String,
        parse: @escaping @Sendable (NSAppleEventDescriptor) -> Value?,
        completion: @escaping @MainActor @Sendable (Result<Value?, ScriptFailure>) -> Void
    ) {
        queue.async {
            let result = self.execute(source).map(parse)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(result) }
            }
        }
    }

    /// Runs `source` and ignores the result, except for permission problems.
    func run(_ source: String, completion: @escaping @MainActor @Sendable (Result<Void, ScriptFailure>) -> Void) {
        run(source, parse: { _ in true }) { result in completion(result.map { _ in () }) }
    }

    /// Whether we may script the app, without asking the user. nil when it's unknown (not running,
    /// or macOS would have to ask first).
    func checkPermission(for bundleID: String, completion: @escaping @MainActor @Sendable (Bool?) -> Void) {
        queue.async {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            // 'core'/'getd': reading a property, the least we'd do.
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, Self.fourCC("core"), Self.fourCC("getd"), false)
            let allowed: Bool? = switch Int(status) {
            case Int(noErr): true
            case Self.notPermitted: false
            default: nil
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(allowed) }
            }
        }
    }

    private func execute(_ source: String) -> Result<NSAppleEventDescriptor, ScriptFailure> {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else if let made = NSAppleScript(source: source) {
            script = made
            // Seeking makes a new script per position: keep the cache small.
            if compiled.count >= 24 { compiled.removeAll() }
            compiled[source] = made
        } else {
            return .failure(.failed(code: -1))
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
            return .failure(code == Self.notPermitted ? .notPermitted : .failed(code: code))
        }
        return .success(result)
    }

    static func fourCC(_ code: String) -> UInt32 {
        code.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
}

extension NSAppleEventDescriptor {
    /// The items of an AppleScript list (AppleScript counts from 1); empty for anything else.
    var listItems: [NSAppleEventDescriptor] {
        guard descriptorType == AppleScriptRunner.fourCC("list") else { return [] }
        return numberOfItems > 0 ? (1...numberOfItems).compactMap { atIndex($0) } : []
    }

    /// nil for AppleScript's `missing value` (a type descriptor holding 'msng') and for null.
    var nonMissing: NSAppleEventDescriptor? {
        if descriptorType == AppleScriptRunner.fourCC("null") { return nil }
        if descriptorType == AppleScriptRunner.fourCC("type"), typeCodeValue == AppleScriptRunner.fourCC("msng") { return nil }
        return self
    }
}
