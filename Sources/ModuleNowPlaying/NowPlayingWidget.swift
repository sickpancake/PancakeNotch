import NotchCore
import NowPlayingCore
import SwiftUI

extension NowPlayingModule {
    /// Now Playing on Home (ADR-0042). It only reads what the center already knows, so sitting on Home
    /// never starts the Music or Spotify permission question; that stays with the module's own page.
    public func homeWidget(_ kind: HomeWidgetKind, size: HomeWidgetSize, context: HomeWidgetContext) -> AnyView? {
        guard kind == .nowPlaying else { return nil }
        return AnyView(NowPlayingWidget(module: self, size: size, context: context))
    }
}

/// Small: the song's art (or a note) and its title. Medium: art, title and artist, play/pause.
/// Large: art, title, artist, the progress, and back/play/next. Nothing playing keeps the same shape.
struct NowPlayingWidget: View {
    let module: NowPlayingModule
    let size: HomeWidgetSize
    let context: HomeWidgetContext

    private var track: NowPlayingTrack? { module.center.track }

    var body: some View {
        switch size {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }

    private var small: some View {
        // Two rows: the art with the artist (or "Paused"), then the song's title.
        HomeSmallFace(caption: subtitle) {
            art(size: 14, corner: 4)
        } value: {
            Text(track?.title ?? String(localized: "Not playing", comment: "Home widget: Small Now Playing with no song"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(track == nil ? 0.6 : 1))
                .truncationMode(.tail)
                .minimumScaleFactor(1) // a long title is cut off, not shrunk
                .id(track?.title ?? "nothing")
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: track?.title)
        }
        .accessibilityElement(children: .combine)
    }

    private var medium: some View {
        let artSize = context.contentSize.height
        return HStack(spacing: 10) {
            art(size: artSize, corner: 8)
            titles(titleSize: 12.5, artistSize: 11, showsArtist: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let track {
                playPause(track, size: 15)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                art(size: 46, corner: 9)
                titles(titleSize: 12.5, artistSize: 11, showsArtist: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 4)
            if let track {
                progress(track)
                Spacer(minLength: 2)
                controls(track)
            } else {
                HomeWidgetEmptyLine(String(localized: "Play something and it shows here."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func art(size: CGFloat, corner: CGFloat) -> some View {
        Group {
            if track == nil, size < 24 {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: size, height: size, alignment: .leading)
            } else {
                ArtworkImage(image: track == nil ? nil : module.center.artwork, artworkID: track?.artworkID,
                             size: size, cornerRadius: corner, isAdvertisement: track?.isAdvertisement ?? false)
            }
        }
        .accessibilityHidden(true)
    }

    private func titles(titleSize: CGFloat, artistSize: CGFloat, showsArtist: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(track?.title ?? String(localized: "Nothing playing"))
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(.white.opacity(track == nil ? 0.6 : 1))
            if showsArtist, let line = subtitle {
                Text(line)
                    .font(.system(size: artistSize))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .id(track.map { "\($0.title)|\($0.artist)" } ?? "nothing")
        .transition(.opacity.combined(with: .offset(y: 3)))
        .animation(.easeInOut(duration: 0.3), value: track?.title)
        .accessibilityElement(children: .combine)
    }

    /// The artist, or "Paused" for a paused song without one.
    private var subtitle: String? {
        guard let track else { return nil }
        if !track.isPlaying { return track.artist.isEmpty ? String(localized: "Paused") : String(localized: "Paused · \(track.artist)") }
        return track.artist.isEmpty ? nil : track.artist
    }

    private func playPause(_ track: NowPlayingTrack, size: CGFloat) -> some View {
        TransportButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: size,
                        label: track.isPlaying ? String(localized: "Pause") : String(localized: "Play")) {
            module.playPause()
        }
    }

    /// A thin bar with the time on each side; it moves once a second only while Home shows a playing song.
    private func progress(_ track: NowPlayingTrack) -> some View {
        let isStill = !track.isPlaying || !context.isLive
        return TimelineView(.animation(minimumInterval: 1, paused: isStill)) { timeline in
            let elapsed = context.isSnapshot ? track.elapsed : track.elapsed(at: isStill ? .now : timeline.date)
            HStack(spacing: 6) {
                Text(NowPlayingTime.format(elapsed))
                if let duration = track.duration, duration > 0 {
                    GeometryReader { proxy in
                        Capsule().fill(.white.opacity(0.15))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.92))
                                    .frame(width: proxy.size.width * min(1, max(0, elapsed / duration)))
                                    .animation(isStill ? nil : .linear(duration: 1), value: elapsed)
                            }
                    }
                    .frame(height: 3)
                    Text(NowPlayingTime.format(duration))
                } else {
                    Capsule().fill(.white.opacity(0.12)).frame(height: 3)
                    Text("Live")
                }
            }
            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(NowPlayingTime.format(elapsed)) played"))
        }
    }

    private func controls(_ track: NowPlayingTrack) -> some View {
        let abilities = module.center.abilities
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            TransportButton(symbol: "backward.fill", size: 11, label: String(localized: "Previous"),
                            isEnabled: abilities.canSkipBack, disabledReason: abilities.skipBlockedReason) {
                module.skip(forward: false)
            }
            playPause(track, size: 15)
            TransportButton(symbol: "forward.fill", size: 11, label: String(localized: "Next"),
                            isEnabled: abilities.canSkipForward, disabledReason: abilities.skipBlockedReason) {
                module.skip(forward: true)
            }
            Spacer(minLength: 0)
        }
    }
}
