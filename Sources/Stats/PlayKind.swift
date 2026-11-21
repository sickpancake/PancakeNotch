import Foundation

/// Whether a play was listened to (music, podcasts, audiobooks) or watched (videos and streams). The
/// Statistics page keeps the two apart, so a YouTube habit in Chrome doesn't pass for music taste.
public enum PlayKind: String, Sendable, CaseIterable {
    case listen
    case watch
    /// An ad the player didn't flag: not counted (`StatsStore.recordListening` drops it) and not shown.
    case ad

    /// Sorts one play by what's known about it, best clue first:
    /// 0. Spotify always names a song's or podcast's album; its ads (free plan) come without one.
    /// 1. A known music or video app decides on its own (Spotify listens, IINA watches).
    /// 2. In a web browser, a song from an album is listening (YouTube Music, Spotify or Apple Music on
    ///    the web); anything else is watching (YouTube, Twitch, Netflix give no album). Browsers don't
    ///    say reliably whether a page plays audio or video, so their media type isn't trusted.
    /// 3. Any other app: its media type if it gives one, then a wide picture (a video thumbnail, where
    ///    album covers are square) means watching. Otherwise it's listening.
    ///
    /// - Parameters:
    ///   - app: the bundle ID of the app that shows it (for a web page, the browser).
    ///   - mediaType: what the app reports to macOS, e.g. "MRMediaRemoteMediaTypeVideo"; nil when it doesn't.
    ///   - artworkAspect: the picture's width divided by its height; nil without a picture.
    public static func of(app: String?, album: String, mediaType: String? = nil, artworkAspect: Double? = nil) -> PlayKind {
        let app = app ?? ""
        let hasAlbum = !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if app == spotify, !hasAlbum { return .ad }
        if videoApps.contains(app) { return .watch }
        if listeningApps.contains(app) { return .listen }
        if isBrowser(app) {
            return hasAlbum ? .listen : .watch
        }
        if let mediaType = mediaType?.lowercased() {
            if mediaType.contains("video") || mediaType == "2" { return .watch }
            if mediaType.contains("audio") || mediaType.contains("music") || mediaType.contains("podcast")
                || mediaType == "1" { return .listen }
        }
        if let artworkAspect, artworkAspect.isFinite, artworkAspect >= wideArtwork { return .watch }
        return .listen
    }

    private static let spotify = "com.spotify.client"

    /// Wider than 5:4 is a video thumbnail (YouTube's are 16:9); album covers are square.
    static let wideArtwork = 1.25

    static func isBrowser(_ app: String) -> Bool {
        // Prefixes so betas, nightlies and web apps saved to the Dock (e.g. "com.apple.Safari.WebApp.…",
        // "com.google.Chrome.app.…") count too.
        browserPrefixes.contains { prefix in
            prefix.hasSuffix(".") ? app.hasPrefix(prefix) : app == prefix || app.hasPrefix(prefix + ".")
        }
    }

    /// A bundle ID, or (ending in ".") a whole maker's family of browsers.
    private static let browserPrefixes = [
        "com.google.Chrome", "com.apple.Safari", "com.apple.SafariTechnologyPreview", "org.mozilla.",
        "company.thebrowser.", "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.",
        "com.vivaldi.Vivaldi", "org.chromium.Chromium", "app.zen-browser.zen", "com.kagi.kagimacOS",
        "ai.perplexity.comet", "com.openai.atlas",
    ]

    /// Apps that play videos.
    private static let videoApps: Set<String> = [
        "com.apple.TV", "com.apple.QuickTimePlayerX", "com.colliderli.iina", "org.videolan.vlc", "io.mpv",
        "com.firecore.infuse", "tv.plex.desktop", "tv.plex.plex-htpc", "com.movist.MovistPro",
    ]

    /// Apps for music, podcasts and audiobooks, even when one shows a video podcast or a music video.
    private static let listeningApps: Set<String> = [
        "com.apple.Music", "com.spotify.client", "com.apple.podcasts", "com.apple.iBooksX",
        "com.tidal.desktop", "com.deezer.deezer-desktop", "com.amazon.music", "com.qobuz.QobuzDesktop",
        "com.github.th-ch.youtube-music", "app.ytmdesktop.ytmdesktop", "tv.plex.plexamp",
        "au.com.shiftyjelly.PocketCasts", "com.coppertino.Vox",
    ]
}
