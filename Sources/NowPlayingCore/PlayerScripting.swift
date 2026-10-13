import AppKit

/// What AppleScript says about Music's or Spotify's current song: shuffle, repeat and whether it's an ad.
struct ScriptedPlayerReading: Equatable, Sendable {
    var title: String
    var modes: ScriptedModes
    var isAdvertisement: Bool
}

/// Talks to Music and Spotify with AppleScript while the helper shows what's playing: the helper can't
/// see Spotify's shuffle and repeat or its ads, and can't start a particular app. Replaceable in tests.
@MainActor
protocol PlayerScripting: AnyObject {
    /// Whether we may script the app, without asking the user: false = the user said no, nil = unknown
    /// (the app isn't running, or macOS would have to ask first).
    func permission(for bundleID: String, completion: @escaping @MainActor (Bool?) -> Void)
    /// Reads the current song's shuffle, repeat and ad signals; nil when the app isn't running or
    /// nothing is loaded. The first time, macOS asks the user for permission.
    func read(_ bundleID: String, completion: @escaping @MainActor (Result<ScriptedPlayerReading?, ScriptFailure>) -> Void)
    /// Changes shuffle or repeat (other commands go through the helper).
    func send(_ command: NowPlayingCommand, to bundleID: String, completion: @escaping @MainActor (Result<Void, ScriptFailure>) -> Void)
    /// Starts playback in the app, launching it if needed.
    func play(_ bundleID: String, completion: @escaping @MainActor (Result<Void, ScriptFailure>) -> Void)
}

/// `PlayerScripting` with real AppleScript, on its own script queue.
@MainActor
final class AppleScriptPlayerScripting: PlayerScripting {
    private let runner = AppleScriptRunner()

    func permission(for bundleID: String, completion: @escaping @MainActor (Bool?) -> Void) {
        runner.checkPermission(for: bundleID) { completion($0) }
    }

    func read(_ bundleID: String, completion: @escaping @MainActor (Result<ScriptedPlayerReading?, ScriptFailure>) -> Void) {
        runner.run(PlayerReadingScripts.reading(for: bundleID), parse: PlayerReadingScripts.parse) { completion($0) }
    }

    func send(_ command: NowPlayingCommand, to bundleID: String, completion: @escaping @MainActor (Result<Void, ScriptFailure>) -> Void) {
        runner.run(PlayerScripts.command(command, bundleID: bundleID)) { completion($0) }
    }

    func play(_ bundleID: String, completion: @escaping @MainActor (Result<Void, ScriptFailure>) -> Void) {
        runner.run(PlayerReadingScripts.play(bundleID)) { completion($0) }
    }
}

/// The scripts behind `AppleScriptPlayerScripting`.
enum PlayerReadingScripts {
    /// Returns `{"stopped"}` or `{"ok", name, shuffle, repeat, address, popularity, track number}`.
    /// Spotify's ad signals sit in `try` blocks: during ads some of them are missing.
    static func reading(for bundleID: String) -> String {
        let body = bundleID == ScriptablePlayers.spotify
            ? """
            if player state is stopped then return {"stopped"}
            set t to current track
            set nm to ""
            try
            set nm to name of t
            end try
            set sm to "off"
            if shuffling then set sm to "tracks"
            set r to "off"
            if repeating then set r to "playlist"
            set u to ""
            try
            set u to spotify url of t
            end try
            set p to -1
            try
            set p to popularity of t
            end try
            set n to -1
            try
            set n to track number of t
            end try
            return {"ok", nm, sm, r, u, p, n}
            """
            : """
            if player state is stopped then return {"stopped"}
            set nm to ""
            try
            set nm to name of current track
            end try
            set sm to "off"
            if shuffle enabled then
            if shuffle mode is albums then
            set sm to "albums"
            else
            set sm to "tracks"
            end if
            end if
            set r to "off"
            if song repeat is one then
            set r to "track"
            else if song repeat is all then
            set r to "playlist"
            end if
            return {"ok", nm, sm, r, "", -1, -1}
            """
        return PlayerScripts.wrap(bundleID, body) + "\nreturn {\"stopped\"}"
    }

    /// Plays in the app. Unlike the other scripts this launches it when it isn't running.
    static func play(_ bundleID: String) -> String {
        """
        tell application id "\(bundleID)"
        play
        end tell
        """
    }

    /// Reads the list `reading(for:)` returns; nil for "stopped" or anything unexpected.
    static func parse(_ descriptor: NSAppleEventDescriptor) -> ScriptedPlayerReading? {
        let items = descriptor.listItems
        guard items.first?.stringValue == "ok", items.count >= 7 else { return nil }
        func text(_ index: Int) -> String { items[index].nonMissing?.stringValue ?? "" }
        func whole(_ index: Int) -> Int? {
            guard let value = items[index].nonMissing else { return nil }
            let number = Int(value.int32Value)
            return number < 0 ? nil : number
        }
        return reading(title: text(1), shuffle: text(2), repeatMode: text(3), address: text(4),
                     popularity: whole(5), trackNumber: whole(6))
    }

    /// The same, from plain values (tested without AppleScript).
    static func reading(title: String, shuffle: String, repeatMode: String, address: String,
                      popularity: Int?, trackNumber: Int?) -> ScriptedPlayerReading {
        ScriptedPlayerReading(
            title: title,
            modes: ScriptedModes(shuffle: PlayerScripts.shuffleMode(shuffle), repeatMode: PlayerScripts.repeatMode(repeatMode)),
            // Music has no ads: it sends no address and -1 for the numbers.
            isAdvertisement: (address.isEmpty && popularity == nil && trackNumber == nil)
                ? false
                : SpotifyAd.isAd(address: address, popularity: popularity, trackNumber: trackNumber)
        )
    }
}
