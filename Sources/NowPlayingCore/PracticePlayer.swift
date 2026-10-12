import AppKit

/// The pretend player of the lessons and the Modules page: three silent made-up songs where every
/// control works at once, without touching the user's real music (ADR-0031).
@MainActor
final class PracticePlayer: NowPlayingBackend, NowPlayingResumable {
    struct Song: Sendable {
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
    }

    static let bundleID = "io.github.sickpancake.PancakeNotch.practice"

    static let songs: [Song] = [
        Song(title: String(localized: "Pancake Sunrise", comment: "Made-up song title in the practice player"),
             artist: String(localized: "The Flipsides", comment: "Made-up artist in the practice player"),
             album: String(localized: "Breakfast Club", comment: "Made-up album in the practice player"),
             duration: 192),
        Song(title: String(localized: "Golden Edges", comment: "Made-up song title in the practice player"),
             artist: String(localized: "Maple & Co.", comment: "Made-up artist in the practice player"),
             album: String(localized: "Stack", comment: "Made-up album in the practice player"),
             duration: 168),
        Song(title: String(localized: "Night Owl", comment: "Made-up song title in the practice player"),
             artist: String(localized: "Syrup Static", comment: "Made-up artist in the practice player"),
             album: String(localized: "After Hours", comment: "Made-up album in the practice player"),
             duration: 220),
    ]

    var onUpdate: ((NowPlayingUpdate) -> Void)?
    var onConnectionChange: ((NowPlayingConnection) -> Void)?
    var processID: pid_t? { nil }

    private(set) var index = 0
    private var elapsed: TimeInterval = 0
    private var elapsedDate: Date
    private(set) var isPlaying = false
    private var shuffle: ShuffleMode = .off
    private var repeatMode: RepeatMode = .off
    private var isRunning = false
    /// The one wait until the song ends (cancelled by every command).
    private var endTask: Task<Void, Never>?
    private let now: () -> Date
    private let songs: [Song]

    init(songs: [Song] = PracticePlayer.songs, now: @escaping () -> Date = Date.init) {
        self.songs = songs
        self.now = now
        elapsedDate = now()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        onConnectionChange?(.practice)
        isPlaying = true
        elapsedDate = now()
        changed()
    }

    func stop() {
        isRunning = false
        isPlaying = false
        endTask?.cancel()
        endTask = nil
    }

    func send(_ command: NowPlayingCommand) {
        guard isRunning else { return }
        settle()
        switch command {
        case .play: isPlaying = true
        case .pause: isPlaying = false
        case .togglePlayPause: isPlaying.toggle()
        case .next: move(by: 1)
        case .previous:
            // Like real players: back to the start first, then the song before.
            if elapsed > 3 { elapsed = 0 } else { move(by: -1) }
        case .seek(let time): elapsed = min(max(0, time), songs[index].duration)
        case .setShuffle(let mode): shuffle = mode
        case .setRepeat(let mode): repeatMode = mode
        }
        changed()
    }

    func resume(preferring bundleID: String?) {
        send(.play)
    }

    // MARK: Private

    /// Brings `elapsed` up to now.
    private func settle() {
        let date = now()
        if isPlaying { elapsed = min(songs[index].duration, elapsed + date.timeIntervalSince(elapsedDate)) }
        elapsedDate = date
    }

    private func move(by step: Int) {
        if shuffle != .off, songs.count > 1, step > 0 {
            var next = index
            while next == index { next = Int.random(in: songs.indices) }
            index = next
        } else {
            index = (index + step + songs.count) % songs.count
        }
        elapsed = 0
    }

    private func changed() {
        publish()
        scheduleEnd()
    }

    private func publish() {
        let song = songs[index]
        let track = NowPlayingTrack(
            title: song.title, artist: song.artist, album: song.album, duration: song.duration,
            elapsed: elapsed, elapsedDate: elapsedDate, isPlaying: isPlaying, bundleID: Self.bundleID,
            shuffle: shuffle, repeatMode: repeatMode, artworkID: "practice-\(index % PracticeArtwork.count)"
        )
        onUpdate?(NowPlayingUpdate(track: track, artwork: PracticeArtwork.image(for: index)))
    }

    /// Waits until the song ends, then plays the next (or the same one again with repeat one).
    private func scheduleEnd() {
        endTask?.cancel()
        endTask = nil
        guard isRunning, isPlaying else { return }
        let remaining = max(0.05, songs[index].duration - elapsed)
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.songEnded()
        }
    }

    private func songEnded() {
        settle()
        if repeatMode == .track {
            elapsed = 0
        } else {
            move(by: 1)
        }
        elapsedDate = now()
        changed()
    }
}

/// Album covers for the practice songs: soft abstract pictures drawn with Core Graphics. Album art is
/// the one place colour is allowed (ADR-0029), so these are colourful, like real covers.
enum PracticeArtwork {
    static let count = 3
    static let size = 256

    @MainActor private static var cache: [Int: NSImage] = [:]

    @MainActor
    static func image(for index: Int) -> NSImage? {
        let key = index % count
        if let cached = cache[key] { return cached }
        guard let image = draw(key) else { return nil }
        cache[key] = image
        return image
    }

    private static func draw(_ index: Int) -> NSImage? {
        let side = CGFloat(size)
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            CGColor(red: r, green: g, blue: b, alpha: a)
        }
        func gradient(_ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
            guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil) else { return }
            context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        switch index {
        case 0:
            // "Pancake Sunrise": a warm sky, a big sun and soft hills.
            gradient([color(1, 0.55, 0.36), color(0.98, 0.78, 0.48), color(1, 0.92, 0.75)],
                     from: CGPoint(x: 0, y: side), to: CGPoint(x: 0, y: side * 0.25))
            context.setFillColor(color(1, 0.97, 0.88, 0.95))
            context.fillEllipse(in: CGRect(x: side * 0.28, y: side * 0.34, width: side * 0.44, height: side * 0.44))
            for (offset, shade) in [(0.36, 0.52), (0.24, 0.42), (0.12, 0.32)] {
                context.setFillColor(color(0.85, CGFloat(shade), 0.3))
                context.fillEllipse(in: CGRect(x: -side * 0.3, y: -side * 0.9 + side * offset, width: side * 1.6, height: side))
            }
        case 1:
            // "Golden Edges": amber rings on a deep brown.
            gradient([color(0.3, 0.16, 0.08), color(0.55, 0.3, 0.1)], from: .zero, to: CGPoint(x: side, y: side))
            let centre = CGPoint(x: side * 0.62, y: side * 0.42)
            for ring in stride(from: 9, through: 1, by: -1) {
                let radius = side * 0.09 * CGFloat(ring)
                let warmth = 0.45 + 0.06 * CGFloat(9 - ring)
                context.setFillColor(color(1, warmth, 0.2 + 0.03 * CGFloat(9 - ring), ring % 2 == 0 ? 0.9 : 0.75))
                context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            }
        default:
            // "Night Owl": a deep blue night, a moon and a few stars.
            gradient([color(0.06, 0.07, 0.25), color(0.28, 0.16, 0.45)], from: CGPoint(x: 0, y: side), to: .zero)
            context.setFillColor(color(0.97, 0.95, 0.85))
            context.fillEllipse(in: CGRect(x: side * 0.52, y: side * 0.56, width: side * 0.28, height: side * 0.28))
            context.setFillColor(color(0.13, 0.1, 0.33))
            context.fillEllipse(in: CGRect(x: side * 0.6, y: side * 0.6, width: side * 0.26, height: side * 0.26))
            context.setFillColor(color(1, 1, 1, 0.85))
            let stars: [(CGFloat, CGFloat, CGFloat)] = [(0.15, 0.8, 4), (0.32, 0.66, 3), (0.22, 0.48, 2.5), (0.42, 0.86, 2.5), (0.85, 0.3, 3), (0.12, 0.25, 2)]
            for (x, y, r) in stars {
                context.fillEllipse(in: CGRect(x: side * x - r, y: side * y - r, width: r * 2, height: r * 2))
            }
            context.setFillColor(color(0.05, 0.05, 0.16, 0.9))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side * 0.16))
        }
        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: size, height: size))
    }
}
