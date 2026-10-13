import AppKit
import NotchCore
import NowPlayingCore
import SwiftUI

/// The open Now Playing panel: the player while a song is loaded, a way to start music when nothing
/// is, and a calm placeholder when PancakeNotch can't see what's playing (ADR-0012). Every state keeps
/// the same shape (artwork square left, column right), so changing between them doesn't jump.
struct NowPlayingView: View {
    let module: NowPlayingModule
    let layout: NowPlayingLayout

    var body: some View {
        let center = module.center
        VStack(spacing: 0) {
            band
                .frame(height: layout.bandHeight)
                .padding(.horizontal, NowPlayingLayout.sidePadding)
            Group {
                if let track = center.track {
                    NowPlayingPlayer(module: module, track: track, layout: layout)
                } else if case .unavailable(let reason) = center.connection {
                    NowPlayingUnavailable(module: module, reason: reason, layout: layout)
                } else {
                    NowPlayingNothing(module: module, layout: layout)
                }
            }
            .padding(.top, layout.contentTop - layout.bandHeight)
            .padding(.horizontal, NowPlayingLayout.sidePadding)
            Spacer(minLength: 0)
        }
        .frame(width: layout.body.width, height: layout.body.height, alignment: .top)
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.25), value: center.track == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Now Playing"))
    }

    /// Beside the notch: nothing on the left (the module tabs live there), the playing app on the right.
    private var band: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Color.clear.frame(width: layout.notchWidth)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if module.center.needsAutomationPermission || module.center.isAutomationDenied(module.center.track?.bundleID) {
                    PermissionPill()
                } else if let bundleID = module.center.track?.bundleID {
                    SourceAppPill(bundleID: bundleID, isPractice: module.center.connection == .practice) {
                        module.openApp()
                    }
                }
            }
            .frame(width: layout.bandSideWidth)
        }
    }
}

// MARK: Player

private struct NowPlayingPlayer: View {
    let module: NowPlayingModule
    let track: NowPlayingTrack
    let layout: NowPlayingLayout

    var body: some View {
        HStack(alignment: .top, spacing: NowPlayingLayout.columnGap) {
            ArtworkButton(module: module, track: track, size: layout.artworkSize)
            VStack(alignment: .leading, spacing: 0) {
                SongTitle(track: track)
                Spacer(minLength: 6)
                ProgressRow(module: module, track: track)
                ControlsRow(module: module, track: track)
                    .padding(.top, 8)
            }
            .frame(width: layout.columnWidth, height: layout.artworkSize, alignment: .topLeading)
        }
    }
}

/// The song and who it's by. A new song cross-fades in.
private struct SongTitle: View {
    let track: NowPlayingTrack
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(track.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.top, 4)
        .id(track.identity)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 3)))
        .animation(.easeInOut(duration: 0.3), value: track.identity)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The album art: click it to bring the playing app forward. Hovering hints at that.
private struct ArtworkButton: View {
    let module: NowPlayingModule
    let track: NowPlayingTrack
    let size: CGFloat
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            module.openApp()
        } label: {
            ArtworkImage(image: module.center.artwork, artworkID: track.artworkID, size: size, cornerRadius: 14,
                         isAdvertisement: track.isAdvertisement)
                .overlay {
                    if isHovered {
                        ZStack {
                            Color.black.opacity(0.35)
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        .transition(.opacity)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let note = module.artworkNote {
                        Text(note)
                            .font(.system(size: 10, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .frame(width: size - 10)
                            .background(.black.opacity(0.75), in: .rect(cornerRadius: 8, style: .continuous))
                            .padding(.bottom, 5)
                            .transition(.opacity)
                    }
                }
                .scaleEffect(isHovered && !reduceMotion ? 1.03 : 1)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .help(Text("Open the app that's playing"))
        .accessibilityLabel(track.isAdvertisement ? Text("Album art, ad") : Text("Album art"))
        .accessibilityHint(Text("Opens the app that's playing."))
    }
}

/// The artwork, or a soft placeholder note. Changing songs cross-fades. During an ad it says so: a small
/// "Ad" label on the picture, or "Ad" instead of the note when there's no picture.
struct ArtworkImage: View {
    let image: NSImage?
    let artworkID: String?
    let size: CGFloat
    let cornerRadius: CGFloat
    var isAdvertisement = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .id(artworkID ?? "artwork")
                    .transition(.opacity)
            } else {
                ArtworkPlaceholder(size: size, text: isAdvertisement ? String(localized: "Ad", comment: "Stands for advertisement, where album art would be") : nil)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .overlay(alignment: .topLeading) {
            if isAdvertisement, image != nil, size >= 40 {
                AdBadge()
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: artworkID)
        .accessibilityHidden(true)
    }
}

/// Grey squares with a note (or a short word, like "Ad"), where album art would be.
struct ArtworkPlaceholder: View {
    let size: CGFloat
    var text: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let text {
                Text(text)
                    .font(.system(size: size * 0.26, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.32, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

/// A small "Ad" label on the artwork while an ad plays.
private struct AdBadge: View {
    var body: some View {
        Text("Ad", comment: "Label on the artwork while an advertisement plays")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(.white.opacity(0.9), in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .accessibilityHidden(true)
    }
}

/// Elapsed time, the progress bar you can drag, and the time left (or the length: click to switch).
private struct ProgressRow: View {
    let module: NowPlayingModule
    let track: NowPlayingTrack

    var body: some View {
        // One view tree whatever happens (switching trees mid-drag would cancel the drag): the clock
        // ticks once a second only while the open notch shows a playing song that isn't being dragged.
        let isStill = !track.isPlaying || module.scrubTime != nil || module.isSnapshot
        TimelineView(.animation(minimumInterval: 1, paused: isStill)) { context in
            row(elapsed: module.scrubTime ?? track.elapsed(at: isStill ? .now : context.date))
        }
    }

    private func row(elapsed: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Text(NowPlayingTime.format(elapsed))
                .frame(width: 40, alignment: .leading)
            if let duration = track.duration, duration > 0 {
                let abilities = module.center.abilities
                ProgressScrubber(module: module, elapsed: elapsed, duration: duration, rate: track.playbackRate,
                                 canSeek: abilities.canSeek, blockedReason: abilities.seekBlockedReason)
                Button {
                    module.toggleTimeDisplay()
                } label: {
                    Text(module.settings.showsRemainingTime
                        ? NowPlayingTime.format(duration - elapsed, negative: true)
                        : NowPlayingTime.format(duration))
                        .frame(width: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text(module.settings.showsRemainingTime ? String(localized: "Show the song's length") : String(localized: "Show the time left")))
                .accessibilityLabel(Text(module.settings.showsRemainingTime
                    ? String(localized: "\(NowPlayingTime.spoken(duration - elapsed)) left")
                    : String(localized: "Length \(NowPlayingTime.spoken(duration))")))
                .accessibilityHint(Text("Switches between the time left and the song's length."))
            } else {
                Capsule().fill(.white.opacity(0.12)).frame(height: 4)
                    .accessibilityHidden(true)
                Text("Live")
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.55))
    }
}

/// A slim bar that thickens under the pointer; drag or click anywhere on it to jump there. When the
/// player refuses jumps (an ad), it only shows the progress.
///
/// It glides between the once-a-second steps of a playing song, but snaps for anything else: a jump
/// back, or the player correcting itself (e.g. after refusing a skip). Sliding there would show the
/// position running ahead and back.
private struct ProgressScrubber: View {
    let module: NowPlayingModule
    let elapsed: TimeInterval
    let duration: TimeInterval
    let rate: Double
    let canSeek: Bool
    let blockedReason: String
    @State private var isHovered = false
    /// The position drawn last, to tell a normal step from a jump.
    @State private var lastElapsed: TimeInterval?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A normal step forward: no more than a second and a half of playing (at the song's speed).
    static func glides(from previous: TimeInterval?, to elapsed: TimeInterval, rate: Double) -> Bool {
        guard let previous else { return false }
        let step = elapsed - previous
        return step >= 0 && step <= 1.5 * max(1, rate)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = min(max(elapsed / duration, 0), 1)
            let isActive = canSeek && (isHovered || module.scrubTime != nil)
            let height: CGFloat = isActive ? 6 : 4
            let glide: Animation? = module.scrubTime == nil && !reduceMotion && Self.glides(from: lastElapsed, to: elapsed, rate: rate)
                ? .linear(duration: 1) : nil
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(height: height)
                Capsule()
                    .fill(.white.opacity(0.92))
                    .frame(width: max(height, width * fraction), height: height)
                    // Glides between the once-a-second ticks while playing.
                    .animation(glide, value: fraction)
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: width * fraction - 6)
                    .opacity(isActive ? 1 : 0)
                    .animation(glide, value: fraction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        module.scrubTime = duration * min(max(drag.location.x / max(width, 1), 0), 1)
                    }
                    .onEnded { drag in
                        let time = duration * min(max(drag.location.x / max(width, 1), 0), 1)
                        module.seek(to: time)
                        // Keep showing where it was dropped until the player reports the jump.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            module.scrubTime = nil
                        }
                    },
                including: canSeek ? .all : .none
            )
            .animation(.easeOut(duration: 0.15), value: isActive)
        }
        .frame(height: 16)
        .onHover { isHovered = $0 }
        .onAppear { lastElapsed = elapsed }
        .onChange(of: elapsed) { _, value in lastElapsed = value }
        .help(canSeek ? Text("") : Text(blockedReason))
        .accessibilityElement()
        .accessibilityLabel(Text("Song position"))
        .accessibilityValue(Text("\(NowPlayingTime.spoken(elapsed)) of \(NowPlayingTime.spoken(duration))"))
        .accessibilityHint(canSeek ? Text("") : Text(blockedReason))
        .accessibilityAdjustableAction { direction in
            guard canSeek else { return }
            switch direction {
            case .increment: module.seek(to: min(duration, elapsed + 10))
            case .decrement: module.seek(to: elapsed - 10)
            @unknown default: break
            }
        }
    }
}

/// Shuffle, back, play/pause, forward, repeat. Shuffle and repeat show only when they really work for
/// this app (`PlayerAbilities`); otherwise both sides stay empty alike, so the middle three stay centred.
/// Back and forward dim when the player refuses them (an ad); play/pause always works.
private struct ControlsRow: View {
    let module: NowPlayingModule
    let track: NowPlayingTrack

    var body: some View {
        let abilities = module.center.abilities
        HStack(spacing: 6) {
            ModeButton(
                symbol: "shuffle",
                isOn: (abilities.shuffle ?? .off) != .off,
                isAvailable: abilities.canShuffle,
                label: abilities.shuffle.map { $0 == .off ? String(localized: "Shuffle, off") : String(localized: "Shuffle, on") } ?? ""
            ) { module.cycleShuffle() }
            Spacer(minLength: 0)
            TransportButton(symbol: "backward.fill", size: 15, label: String(localized: "Previous"),
                            isEnabled: abilities.canSkipBack, disabledReason: abilities.skipBlockedReason) {
                module.skip(forward: false)
            }
            TransportButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 22, label: track.isPlaying ? String(localized: "Pause") : String(localized: "Play")) {
                module.playPause()
            }
            .frame(width: 44)
            TransportButton(symbol: "forward.fill", size: 15, label: String(localized: "Next"),
                            isEnabled: abilities.canSkipForward, disabledReason: abilities.skipBlockedReason) {
                module.skip(forward: true)
            }
            Spacer(minLength: 0)
            ModeButton(
                symbol: abilities.repeatMode == .track ? "repeat.1" : "repeat",
                isOn: (abilities.repeatMode ?? .off) != .off,
                isAvailable: abilities.canRepeat,
                label: repeatLabel(abilities.repeatMode)
            ) { module.cycleRepeat() }
        }
        .frame(height: 34)
    }

    private func repeatLabel(_ mode: RepeatMode?) -> String {
        switch mode {
        case .off: String(localized: "Repeat, off")
        case .playlist: String(localized: "Repeat, all songs")
        case .track: String(localized: "Repeat, this song")
        case nil: ""
        }
    }
}

/// Back, play/pause or forward. Dimmed (not hidden, so the row doesn't move) when the player refuses
/// it, with the reason as its tooltip and VoiceOver hint.
private struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    var isEnabled = true
    var disabledReason = ""
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + 20, height: size + 14)
                .background(.white.opacity(isHovered && isEnabled ? 0.1 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
        .onHover { isHovered = $0 }
        .help(Text(isEnabled ? label : disabledReason))
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text(isEnabled ? "" : disabledReason))
    }
}

/// Shuffle or repeat: dim when off, white on a soft circle when on.
private struct ModeButton: View {
    let symbol: String
    let isOn: Bool
    let isAvailable: Bool
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isOn ? 1 : isHovered ? 0.8 : 0.45))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                .background(.white.opacity(isOn ? 0.16 : isHovered ? 0.08 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
        .opacity(isAvailable ? 1 : 0)
        .disabled(!isAvailable)
        .accessibilityHidden(!isAvailable)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

/// Buttons shrink a touch while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: Nothing playing

/// No song loaded: start the last app again (only where that really works), or open an app.
///
/// "Resume" shows only for the practice player and for Music or Spotify (told to play with AppleScript);
/// when they refused the Automation permission it becomes the way to allow it. "Open" opens the last
/// player (or Music), and its ▾ lists the other media apps on this Mac.
private struct NowPlayingNothing: View {
    let module: NowPlayingModule
    let layout: NowPlayingLayout

    var body: some View {
        let center = module.center
        let resume = center.resumeOption
        let mainApp = center.connection == .practice
            ? nil
            : MediaApps.mainApp(lastPlayer: center.lastPlayerBundleID, isInstalled: InstalledApps.isInstalled)
        HStack(alignment: .center, spacing: NowPlayingLayout.columnGap) {
            ArtworkPlaceholder(size: layout.artworkSize)
                .frame(width: layout.artworkSize, height: layout.artworkSize)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .opacity(0.7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing playing")
                    .font(.system(size: 15, weight: .semibold))
                Text(center.connection == .limited
                    ? String(localized: "Play something in Music or Spotify and it shows up here.")
                    : String(localized: "Play something in any app and it shows up here."))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    switch resume {
                    case .practice?:
                        NotchPill(title: String(localized: "Play"), symbol: "play.fill", prominent: true) { module.resume() }
                    case .app(let bundleID)?:
                        let name = PlayerApp(bundleID: bundleID)?.name ?? bundleID
                        NotchPill(title: String(localized: "Resume \(name)"), symbol: "play.fill", prominent: true) { module.resume() }
                            .help(Text("Plays \(name) again"))
                    case .needsPermission(let bundleID)?:
                        let name = PlayerApp(bundleID: bundleID)?.name ?? bundleID
                        NotchPill(title: String(localized: "Allow control"), symbol: "lock", prominent: true) {
                            NowPlayingPermissions.openAutomationSettings()
                        }
                        .help(Text("PancakeNotch needs permission to control \(name). Opens System Settings."))
                        .accessibilityHint(Text("PancakeNotch needs permission to control \(name). Opens System Settings."))
                    case nil:
                        EmptyView()
                    }
                    if let mainApp {
                        OpenAppButton(module: module, bundleID: mainApp, prominent: resume == nil)
                    }
                }
                .padding(.top, 8)
            }
            .frame(width: layout.columnWidth, alignment: .leading)
        }
        .frame(height: layout.artworkSize)
        // Look the apps up again each time this shows (one quick lookup per app, never per redraw):
        // an app installed or removed since then shows up right.
        .onAppear {
            InstalledApps.forget()
            PlayerApp.forgetMissing()
        }
    }
}

/// "Open <app>" with a ▾ attached: the main part opens the app, the ▾ lists other media apps.
/// One capsule, like `NotchPill`. The ▾ is left out when there's no other app to offer.
private struct OpenAppButton: View {
    let module: NowPlayingModule
    let bundleID: String
    let prominent: Bool
    @State private var hovered: Part?

    private enum Part { case main, menu }

    var body: some View {
        let name = PlayerApp(bundleID: bundleID)?.name ?? bundleID
        let others = MediaApps.menuApps(seen: module.center.seenApps, main: bundleID, isInstalled: InstalledApps.isInstalled)
        HStack(spacing: 0) {
            Button {
                module.openApp(bundleID)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 9.5, weight: .bold))
                    Text("Open \(name)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.leading, 11)
                .padding(.trailing, others.isEmpty ? 11 : 8)
                .frame(height: 24)
                .background(highlight(.main))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .onHover { hovered = $0 ? .main : (hovered == .main ? nil : hovered) }
            .help(Text("Open \(name)"))
            .accessibilityLabel(Text("Open \(name)"))

            if !others.isEmpty {
                Rectangle()
                    .fill(prominent ? Color.black.opacity(0.2) : Color.white.opacity(0.2))
                    .frame(width: 1, height: 14)
                    .accessibilityHidden(true)
                Button {
                    // After this click is handled: the menu runs its own event loop until it closes.
                    Task { @MainActor in NowPlayingAppMenu.show(others, for: module) }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .frame(width: 22, height: 24)
                        .background(highlight(.menu))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .onHover { hovered = $0 ? .menu : (hovered == .menu ? nil : hovered) }
                .help(Text("Open another app"))
                .accessibilityLabel(Text("More apps"))
            }
        }
        .foregroundStyle(prominent ? .black : .white)
        .background(prominent ? Color.white : Color.white.opacity(0.13), in: Capsule())
        .clipShape(Capsule())
    }

    private func highlight(_ part: Part) -> Color {
        guard hovered == part else { return .clear }
        return prominent ? .black.opacity(0.1) : .white.opacity(0.08)
    }
}

/// The ▾ menu of `OpenAppButton`: a system menu (dark, grey app icons), which keeps the notch open
/// while it's showing.
@MainActor
enum NowPlayingAppMenu {
    static func show(_ bundleIDs: [String], for module: NowPlayingModule) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = NSAppearance(named: .darkAqua)
        let target = MenuTarget { module.openApp($0) }
        for bundleID in bundleIDs {
            guard let app = PlayerApp(bundleID: bundleID) else { continue }
            let item = NSMenuItem(title: app.name, action: #selector(MenuTarget.choose(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = bundleID
            item.image = app.grayIcon
            item.setAccessibilityLabel(String(localized: "Open \(app.name)"))
            menu.addItem(item)
        }
        guard !menu.items.isEmpty else { return }
        module.setAppMenuOpen(true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        module.setAppMenuOpen(false)
        withExtendedLifetime(target) {}
    }

    /// Receives the menu's choice (menu items need an Objective-C target).
    private final class MenuTarget: NSObject {
        let open: @MainActor (String) -> Void

        init(open: @escaping @MainActor (String) -> Void) {
            self.open = open
        }

        @MainActor @objc func choose(_ sender: NSMenuItem) {
            guard let bundleID = sender.representedObject as? String else { return }
            open(bundleID)
        }
    }
}

// MARK: Not connected

/// PancakeNotch can't see what's playing (both ways in failed): a blurred stand-in and why (ADR-0012).
private struct NowPlayingUnavailable: View {
    let module: NowPlayingModule
    let reason: String
    let layout: NowPlayingLayout

    var body: some View {
        HStack(alignment: .center, spacing: NowPlayingLayout.columnGap) {
            ZStack {
                ArtworkPlaceholder(size: layout.artworkSize)
                    .blur(radius: 10)
                Image(systemName: "music.note.list")
                    .font(.system(size: layout.artworkSize * 0.28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(width: layout.artworkSize, height: layout.artworkSize)
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(reason)
                    .font(.system(size: 15, weight: .semibold))
                Text("PancakeNotch can't see what's playing on this Mac right now.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    NotchPill(title: String(localized: "Try Again"), symbol: "arrow.clockwise", prominent: true) {
                        module.center.retryConnection()
                    }
                    if module.center.needsAutomationPermission {
                        NotchPill(title: String(localized: "Allow in Settings"), symbol: "lock.open") {
                            NowPlayingPermissions.openAutomationSettings()
                        }
                    }
                }
                .padding(.top, 8)
            }
            .frame(width: layout.columnWidth, alignment: .leading)
        }
        .frame(height: layout.artworkSize)
    }
}

// MARK: Small parts

/// A capsule button for the notch: white with black text when it's the main action.
struct NotchPill: View {
    let title: String
    var symbol: String?
    var prominent = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9.5, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(prominent ? .black : .white)
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background(prominent ? .white.opacity(isHovered ? 0.88 : 1) : .white.opacity(isHovered ? 0.2 : 0.13), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
    }
}

/// The playing app's icon (in grey, like everything but album art) and name; click to open it.
private struct SourceAppPill: View {
    let bundleID: String
    let isPractice: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let app = PlayerApp(bundleID: bundleID)
        Button(action: action) {
            HStack(spacing: 5) {
                if isPractice {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                } else if let icon = app?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 14, height: 14)
                        .grayscale(1)
                }
                Text(isPractice ? String(localized: "Practice player") : app?.name ?? bundleID)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(isHovered ? 0.95 : 0.6))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(.white.opacity(isHovered ? 0.12 : 0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text("Open \(app?.name ?? bundleID)"))
        .accessibilityLabel(Text(isPractice ? String(localized: "Playing in the practice player") : String(localized: "Playing in \(app?.name ?? bundleID)")))
        .accessibilityHint(Text("Opens the app."))
    }
}

/// The Music/Spotify fallback needs the Automation permission: a way to it.
private struct PermissionPill: View {
    var body: some View {
        NotchPill(title: String(localized: "Allow control"), symbol: "lock") {
            NowPlayingPermissions.openAutomationSettings()
        }
        .help(Text("PancakeNotch needs permission to control Music and Spotify. Opens System Settings."))
    }
}

/// A playing app's name and icon, looked up once per app (also remembering apps that aren't installed).
struct PlayerApp {
    let name: String
    let icon: NSImage?
    private let bundleID: String

    @MainActor private static var cache: [String: PlayerApp] = [:]
    @MainActor private static var missing: Set<String> = []
    @MainActor private static var grayIcons: [String: NSImage] = [:]

    @MainActor
    init?(bundleID: String) {
        if let cached = Self.cache[bundleID] {
            self = cached
            return
        }
        guard !Self.missing.contains(bundleID) else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            Self.missing.insert(bundleID)
            return nil
        }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 28, height: 28)
        self.name = name
        self.icon = icon
        self.bundleID = bundleID
        Self.cache[bundleID] = self
    }

    /// Forgets the apps found missing (the "Open" menu looks again when it shows).
    @MainActor
    static func forgetMissing() {
        missing = []
    }

    /// The icon in grey (everything but album art is monochrome), 16 pt, for menus.
    @MainActor
    var grayIcon: NSImage? {
        if let cached = Self.grayIcons[bundleID] { return cached }
        guard let icon else { return nil }
        let gray = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            icon.draw(in: rect)
            // Take the colour out, then put the icon's own transparency back.
            NSColor.gray.setFill()
            rect.fill(using: .saturation)
            icon.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        Self.grayIcons[bundleID] = gray
        return gray
    }
}

/// Opens System Settings at the Automation privacy page (the Music/Spotify fallback).
enum NowPlayingPermissions {
    @MainActor
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
