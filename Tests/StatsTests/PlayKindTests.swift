import Testing
@testable import Stats

@Suite("PlayKind")
struct PlayKindTests {
    @Test func musicAppsListen() {
        #expect(PlayKind.of(app: "com.apple.Music", album: "Album") == .listen)
        #expect(PlayKind.of(app: "com.apple.podcasts", album: "") == .listen)
        // A music video or video podcast in a music app is still music taste.
        #expect(PlayKind.of(app: "com.spotify.client", album: "Show", mediaType: "MRMediaRemoteMediaTypeVideo", artworkAspect: 16.0 / 9) == .listen)
    }

    /// What Spotify's free plan really reports for an ad: a title and the advertiser, no album.
    @Test func spotifyItemsWithoutAnAlbumAreAds() {
        #expect(PlayKind.of(app: "com.spotify.client", album: "") == .ad)
        #expect(PlayKind.of(app: "com.spotify.client", album: " ") == .ad)
        #expect(PlayKind.of(app: "com.spotify.client", album: "Freudian") == .listen)
        // Other apps' songs without an album are still songs.
        #expect(PlayKind.of(app: "com.apple.Music", album: "") == .listen)
    }

    @Test func videoAppsWatch() {
        #expect(PlayKind.of(app: "com.colliderli.iina", album: "") == .watch)
        #expect(PlayKind.of(app: "com.apple.TV", album: "Season 1") == .watch)
        #expect(PlayKind.of(app: "org.videolan.vlc", album: "", artworkAspect: 1) == .watch)
    }

    /// What Chrome really reports for a YouTube video: title, channel as artist, no album, no media type.
    @Test func youTubeInChromeIsWatching() {
        #expect(PlayKind.of(app: "com.google.Chrome", album: "", artworkAspect: 150.0 / 83) == .watch)
        #expect(PlayKind.of(app: "com.google.Chrome", album: "") == .watch)
        // Twitch may show the streamer's square picture: still watching.
        #expect(PlayKind.of(app: "com.google.Chrome", album: "", artworkAspect: 1) == .watch)
        // A browser saying "audio" isn't trusted.
        #expect(PlayKind.of(app: "com.apple.Safari", album: "", mediaType: "MRMediaRemoteMediaTypeMusic") == .watch)
    }

    /// YouTube Music, Spotify or Apple Music on the web name the album.
    @Test func musicInABrowserIsListening() {
        #expect(PlayKind.of(app: "com.google.Chrome", album: "Some Album", artworkAspect: 1) == .listen)
        #expect(PlayKind.of(app: "org.mozilla.firefox", album: "Album") == .listen)
        #expect(PlayKind.of(app: "com.google.Chrome", album: "   ") == .watch)
    }

    @Test func browserFamiliesAreRecognised() {
        for app in ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.app.abcdef", "com.apple.Safari",
                    "com.apple.Safari.WebApp.1234", "com.apple.SafariTechnologyPreview", "org.mozilla.firefox",
                    "org.mozilla.nightly", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser"] {
            #expect(PlayKind.isBrowser(app), "\(app)")
        }
        for app in ["com.google.Chromeish", "com.spotify.client", "com.apple.Music", ""] {
            #expect(!PlayKind.isBrowser(app), "\(app)")
        }
    }

    @Test func otherAppsUseWhatTheySay() {
        #expect(PlayKind.of(app: "com.example.player", album: "", mediaType: "MRMediaRemoteMediaTypeVideo") == .watch)
        #expect(PlayKind.of(app: "com.example.player", album: "", mediaType: "2") == .watch)
        #expect(PlayKind.of(app: "com.example.player", album: "", mediaType: "MRMediaRemoteMediaTypeMusic", artworkAspect: 2) == .listen)
        // No word from the app: a wide thumbnail means a video, a square cover a song.
        #expect(PlayKind.of(app: "com.example.player", album: "", artworkAspect: 16.0 / 9) == .watch)
        #expect(PlayKind.of(app: "com.example.player", album: "", artworkAspect: 1) == .listen)
        #expect(PlayKind.of(app: "com.example.player", album: "", artworkAspect: .infinity) == .listen)
        #expect(PlayKind.of(app: nil, album: "") == .listen)
    }
}
