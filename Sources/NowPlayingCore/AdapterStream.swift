import AppKit

/// One value the adapter reports. Only the plain kinds we use; everything else is skipped.
enum AdapterValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    /// A list of whole numbers (`enabledCommands`).
    case numbers([Int])

    /// Converts what `JSONSerialization` produced; nil for null, objects and lists of anything but numbers.
    init?(json: Any) {
        if let list = json as? [Any] {
            let numbers = list.compactMap { ($0 as? NSNumber)?.intValue }
            guard numbers.count == list.count else { return nil }
            self = .numbers(numbers)
        } else if let number = json as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        } else if let string = json as? String {
            self = .string(string)
        } else {
            return nil
        }
    }
}

/// What the adapter has told us so far about the current item: full snapshots replace it, diffs change
/// only the keys they mention (a key set to JSON null was removed).
struct AdapterState: Equatable, Sendable {
    /// The keys we read. Others (and the artwork bytes, handled separately) aren't kept.
    static let knownKeys: Set<String> = [
        "title", "artist", "album", "bundleIdentifier", "parentApplicationBundleIdentifier",
        "processIdentifier", "playing", "playbackRate", "durationMicros", "elapsedTimeMicros",
        "timestampEpochMicros", "shuffleMode", "repeatMode", "isAdvertisement", "prohibitsSkip",
        // Added by our small patch to the adapter (Vendor/mediaremote-adapter/VERSION).
        "enabledCommands",
    ]

    var values: [String: AdapterValue] = [:]
    /// Changes whenever the artwork bytes change; nil = no artwork.
    var artworkID: String?

    var isEmpty: Bool { values.isEmpty }

    /// Applies one payload. `diff == false` replaces everything.
    mutating func apply(_ payload: [String: Any], diff: Bool) {
        if !diff { values = [:] }
        for (key, raw) in payload where Self.knownKeys.contains(key) {
            if raw is NSNull {
                values[key] = nil
            } else if let value = AdapterValue(json: raw) {
                values[key] = value
            }
        }
    }

    func string(_ key: String) -> String? {
        if case .string(let value) = values[key] { return value }
        return nil
    }

    func double(_ key: String) -> Double? {
        switch values[key] {
        case .number(let value): value
        case .bool(let value): value ? 1 : 0
        case .string(let value): Double(value)
        case .numbers, nil: nil
        }
    }

    func numbers(_ key: String) -> [Int]? {
        if case .numbers(let value) = values[key] { return value }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        switch values[key] {
        case .bool(let value): value
        case .number(let value): value != 0
        default: nil
        }
    }

    /// The track this state describes; nil when nothing is playing (no title).
    /// `receivedAt` stands in for the measuring time when the adapter didn't send one.
    func track(receivedAt: Date) -> NowPlayingTrack? {
        guard let title = string("title"), !title.isEmpty else { return nil }
        let source = string("bundleIdentifier").flatMap { $0.isEmpty ? nil : $0 }
        let parent = string("parentApplicationBundleIdentifier").flatMap { $0.isEmpty ? nil : $0 }
        let rate = double("playbackRate")
        let playing = bool("playing") ?? ((rate ?? 0) > 0)
        let duration = double("durationMicros").flatMap { $0 > 0 ? $0 / 1_000_000 : nil }
        let elapsed = (double("elapsedTimeMicros") ?? 0) / 1_000_000
        let elapsedDate = double("timestampEpochMicros").map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? receivedAt
        return NowPlayingTrack(
            title: title,
            artist: string("artist") ?? "",
            album: string("album") ?? "",
            duration: duration,
            elapsed: elapsed,
            elapsedDate: elapsedDate,
            playbackRate: rate,
            isPlaying: playing,
            bundleID: parent ?? source,
            sourceBundleID: source,
            shuffle: double("shuffleMode").flatMap { ShuffleMode(rawValue: Int($0)) },
            repeatMode: double("repeatMode").flatMap { RepeatMode(rawValue: Int($0)) },
            artworkID: artworkID,
            processID: double("processIdentifier").flatMap { $0 > 0 ? Int32(exactly: $0) : nil },
            isAdvertisement: bool("isAdvertisement") == true || bool("prohibitsSkip") == true,
            enabledCommands: numbers("enabledCommands").map(Set.init)
        )
    }
}

/// One line of `mediaremote-adapter stream`: `{"type":"data","diff":<bool>,"payload":{...}}`.
struct AdapterMessage {
    var diff: Bool
    var payload: [String: Any]

    /// nil for anything that isn't a data line (or isn't JSON).
    init?(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any]
        else { return nil }
        diff = object["diff"] as? Bool ?? false
        self.payload = payload
    }
}

/// Splits the adapter's output into lines and keeps the current state, including a small copy of
/// the artwork. Runs off the main thread; not thread-safe on its own (one queue owns it).
struct AdapterStreamParser {
    /// A line longer than this is garbage (artwork lines are a few MB at most): drop it.
    static let maxLineLength = 16 * 1024 * 1024

    private(set) var state = AdapterState()
    private var buffer = Data()
    /// How much of `buffer` is known to hold no line break (artwork lines arrive in many pieces).
    private var scanned = 0
    private var artwork: NSImage?
    /// Turns artwork bytes into a picture; replaceable in tests.
    var makeArtwork: (Data) -> NSImage? = ArtworkImage.downsample

    /// Feeds raw output. Returns the newest state if at least one complete line arrived, else nil.
    mutating func feed(_ data: Data, receivedAt: Date) -> NowPlayingUpdate? {
        buffer.append(data)
        var handled = false
        var lineStart = buffer.startIndex
        var searchFrom = buffer.startIndex + scanned
        while let newline = buffer[searchFrom...].firstIndex(of: 0x0A) {
            if apply(line: buffer[lineStart..<newline]) { handled = true }
            lineStart = buffer.index(after: newline)
            searchFrom = lineStart
        }
        buffer.removeSubrange(buffer.startIndex..<lineStart)
        scanned = buffer.count
        if buffer.count > Self.maxLineLength {
            buffer = Data()
            scanned = 0
        }
        guard handled else { return nil }
        return NowPlayingUpdate(track: state.track(receivedAt: receivedAt), artwork: state.artworkID == nil ? nil : artwork)
    }

    /// Applies one line; false if it wasn't a data line.
    @discardableResult
    mutating func apply(line: Data) -> Bool {
        guard let message = AdapterMessage(line: line) else { return false }
        state.apply(message.payload, diff: message.diff)
        // Artwork: missing from a full snapshot or null in a diff = gone; absent from a diff = unchanged.
        switch message.payload["artworkData"] {
        case let base64 as String:
            let id = ArtworkImage.id(for: base64, count: base64.utf8.count)
            if id != state.artworkID {
                state.artworkID = id
                artwork = Data(base64Encoded: base64, options: .ignoreUnknownCharacters).flatMap(makeArtwork)
            }
        case nil where message.diff:
            break
        default:
            state.artworkID = nil
            artwork = nil
        }
        if state.isEmpty {
            state.artworkID = nil
            artwork = nil
        }
        return true
    }
}
