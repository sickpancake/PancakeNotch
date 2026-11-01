import AudioToolbox
import Foundation

/// The Timer's alert sounds: macOS's own (/System/Library/Sounds), played once at the Mac's alert volume
/// (Sound settings › Alert volume), through the alert device (ADR-0040).
@MainActor
public enum TimerSound {
    static let folder = "/System/Library/Sounds"

    /// The sounds on this Mac, by name, sorted ("Basso", "Blow", … "Tink").
    public static func available() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return files.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
    }

    /// The file for a sound name, if this Mac has it.
    static func url(for name: String) -> URL? {
        guard !name.isEmpty, !name.contains("/") else { return nil }
        let path = "\(folder)/\(name).aiff"
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    /// The sounds loaded so far, kept: each is small and loading takes a moment.
    private static var loaded: [String: SystemSoundID] = [:]

    /// Plays `name` once; "" (No sound) or an unknown name plays nothing.
    public static func play(_ name: String) {
        guard let id = soundID(for: name) else { return }
        AudioServicesPlayAlertSoundWithCompletion(id, nil)
    }

    private static func soundID(for name: String) -> SystemSoundID? {
        if let id = loaded[name] { return id }
        guard let url = url(for: name) else { return nil }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else { return nil }
        loaded[name] = id
        return id
    }
}
