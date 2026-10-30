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
            let numbers = list.compactMap { ($0 as? NSNumber).flatMap { number -> Int? in
                guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue >= 0 else { return nil }
                return Int(exactly: number.doubleValue)
            } }
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
        let value: Double?
        switch values[key] {
        case .number(let number): value = number
        case .bool(let flag): value = flag ? 1 : 0
        case .string(let string): value = Double(string)
        case .numbers, nil: value = nil
        }
        return value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }

    func numbers(_ key: String) -> [Int]? {
        if case .numbers(let value) = values[key] { return value }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        switch values[key] {
        case .bool(let value): value
        case .number(let value): value.isFinite && value > 0
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
            shuffle: double("shuffleMode").flatMap { Int(exactly: $0).flatMap(ShuffleMode.init(rawValue:)) },
            repeatMode: double("repeatMode").flatMap { Int(exactly: $0).flatMap(RepeatMode.init(rawValue:)) },
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
    /// A line longer than this is garbage (artwork lines are a few hundred KB, rarely a few MB): it's
    /// dropped before decoding. Artwork over 4 MB of base64 (a 3 MB picture) isn't decoded either.
    static let maxLineLength = 6 * 1024 * 1024
    static let maxArtworkLength = 4 * 1024 * 1024

    private(set) var state = AdapterState()
    private var buffer = Data()
    /// An oversized line stays rejected until its newline, including across reads.
    private var discarding = false
    private var artwork: NSImage?
    /// Turns artwork bytes into a picture; replaceable in tests.
    var makeArtwork: (Data) -> NSImage? = ArtworkImage.downsample

    /// Feeds raw output. Returns the newest state if at least one complete line arrived, else nil.
    mutating func feed(_ data: Data, receivedAt: Date) -> NowPlayingUpdate? {
        var handled = false
        var start = data.startIndex
        while start < data.endIndex {
            let newline = data[start...].firstIndex(of: 0x0A)
            let end = newline ?? data.endIndex
            if !discarding {
                if end - start > Self.maxLineLength - buffer.count {
                    buffer = Data()
                    discarding = true
                } else {
                    buffer.append(data[start..<end])
                }
            }
            guard let newline else { break }
            if !discarding, apply(line: buffer) { handled = true }
            buffer = Data()
            discarding = false
            start = data.index(after: newline)
        }
        guard handled else { return nil }
        return NowPlayingUpdate(track: state.track(receivedAt: receivedAt), artwork: state.artworkID == nil ? nil : artwork)
    }

    /// Applies one line; false if it wasn't a data line.
    @discardableResult
    mutating func apply(line: Data) -> Bool {
        guard line.count <= Self.maxLineLength, let message = AdapterMessage(line: line) else { return false }
        state.apply(message.payload, diff: message.diff)
        // Artwork: missing from a full snapshot or null in a diff = gone; absent from a diff = unchanged.
        switch message.payload["artworkData"] {
        case let base64 as String where base64.utf8.count <= Self.maxArtworkLength:
            let id = ArtworkImage.id(for: base64, count: base64.utf8.count)
            if id != state.artworkID {
                state.artworkID = id
                artwork = Data(base64Encoded: base64).flatMap(makeArtwork)
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
