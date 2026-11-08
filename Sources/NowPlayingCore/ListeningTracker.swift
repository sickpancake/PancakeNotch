import Foundation

/// Measures how long each song actually plays, by the clock. A stretch starts when a song starts playing
/// and ends when it pauses, another song (or an ad) starts, nothing plays any more, or Now Playing stops.
struct ListeningTracker: Sendable {
    /// Shorter stretches (skipping through songs) aren't worth counting.
    static let minimumSeconds: TimeInterval = 5

    private struct Stretch: Sendable {
        var track: NowPlayingTrack
        var started: Date
        /// The newest artwork's width ÷ height while this song played (it often arrives after the title).
        var artworkAspect: Double?
    }

    private var stretch: Stretch?

    var isListening: Bool { stretch != nil }

    /// Tells the tracker what's shown now; returns the stretch that just ended, if it counts.
    /// - Parameter artworkAspect: the shown artwork's width divided by its height; nil without artwork.
    mutating func update(_ track: NowPlayingTrack?, artworkAspect: Double? = nil, at date: Date) -> ListeningRecord? {
        // An ad isn't listening: it ends the song's stretch and starts none.
        let track = track?.isAdvertisement == true ? nil : track
        var record: ListeningRecord?
        if let current = stretch, track?.isPlaying != true || track?.identity != current.track.identity {
            // Paused: the player says when (it may be told late, e.g. after the Mac slept).
            var end = date
            if let track, !track.isPlaying, track.identity == current.track.identity {
                end = max(current.started, min(date, track.elapsedDate))
            }
            record = flush(at: end)
        } else if let track, stretch != nil {
            // Still the same song: keep what arrived since (media type, artwork), not when it started.
            stretch?.track = track
            if let artworkAspect { stretch?.artworkAspect = artworkAspect }
        }
        if stretch == nil, let track, track.isPlaying {
            stretch = Stretch(track: track, started: date, artworkAspect: artworkAspect)
        }
        return record
    }

    /// Ends the current stretch (stop, quit); returns it if it counts.
    mutating func flush(at date: Date) -> ListeningRecord? {
        guard let current = stretch else { return nil }
        stretch = nil
        let seconds = date.timeIntervalSince(current.started)
        guard seconds >= Self.minimumSeconds else { return nil }
        let track = current.track
        return ListeningRecord(title: track.title, artist: track.artist, album: track.album,
                               bundleID: track.bundleID, started: current.started, seconds: seconds,
                               mediaType: track.mediaType, artworkAspect: current.artworkAspect)
    }
}
