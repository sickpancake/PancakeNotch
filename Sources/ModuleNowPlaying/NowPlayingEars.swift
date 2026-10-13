import AppKit
import NotchCore
import NowPlayingCore
import QuartzCore
import SwiftUI

/// The album art in the compact notch. Paused, it dims and shows a pause sign; a new album cross-fades.
struct NowPlayingArtEar: View {
    let module: NowPlayingModule
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let track = module.center.track
        let size = max(14, height - 11)
        let isPaused = track.map { !$0.isPlaying } ?? false
        ArtworkImage(image: track == nil ? nil : module.center.artwork, artworkID: track?.artworkID, size: size, cornerRadius: 6)
            .opacity(track == nil ? 0.5 : isPaused ? 0.45 : 1)
            .overlay {
                if isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.75), value: isPaused)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(module.accessibilityStatus ?? String(localized: "Nothing playing")))
    }
}

/// Four sound bars in the compact notch. How they move is a setting (Modules page): following the
/// playing app's real sound, dancing gently while it makes sound (the default), or standing still.
/// They only ever move while they can be seen.
struct NowPlayingBarsEar: View {
    let module: NowPlayingModule
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let track = module.center.track
        let isPlaying = track?.isPlaying ?? false
        let isPractice = module.center.connection == .practice
        // The practice players keep throwaway settings: their bars show the user's choice instead.
        let choice = isPractice ? (NowPlayingSettings.user ?? module.settings) : module.settings
        let barHeight = max(8, height - 17)
        Group {
            if module.isSnapshot {
                StillBars(levels: isPlaying ? [0.55, 0.95, 0.7, 0.4] : SoundBarsView.restLevels, height: barHeight)
            } else {
                SoundBarsView(
                    configuration: SoundBarsConfiguration(
                        style: choice.soundBars,
                        show: choice.soundBarsShow,
                        access: choice.soundBarsAccess,
                        isPractice: isPractice,
                        // The pretend player makes no sound: nothing to listen to.
                        source: isPractice ? nil : track.flatMap(SoundSourceID.init(track:)),
                        isPlaying: isPlaying,
                        // Only in the compact notch, never while it's closed or open.
                        isShown: module.notch?.state == .compact,
                        reduceMotion: reduceMotion,
                        height: barHeight
                    ),
                    settings: isPractice ? nil : module.settings
                )
            }
        }
        .frame(width: SoundBarsView.width, height: barHeight)
        .opacity(track == nil ? 0.35 : 1)
        .accessibilityHidden(true)
    }
}

/// Bars drawn in SwiftUI, for off-screen snapshots (which can't draw Core Animation layers).
private struct StillBars: View {
    let levels: [CGFloat]
    let height: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: SoundBarsView.spacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: SoundBarsView.barWidth, height: max(SoundBarsView.barWidth, height * level))
            }
        }
    }
}

/// Everything the bars need to know to decide what to do.
struct SoundBarsConfiguration: Equatable {
    var style: SoundBarsStyle
    var show: SoundBarsShow
    var access: SoundBarsAccess
    var isPractice: Bool
    var source: SoundSourceID?
    var isPlaying: Bool
    var isShown: Bool
    var reduceMotion: Bool
    var height: CGFloat
}

/// The bars as Core Animation layers. Gentle motion runs in the window server, so the app itself does
/// nothing between frames (AGENTS.md: ~0% CPU). Following the music, the levels arrive about 30 times
/// a second while the bars can be seen and the song plays. Everything stops when they can't be seen.
struct SoundBarsView: NSViewRepresentable {
    let configuration: SoundBarsConfiguration
    /// Where "allowed" or "not allowed" is remembered (nil for the practice player).
    let settings: NowPlayingSettings?

    static let barWidth: CGFloat = 2.5
    static let spacing: CGFloat = 2
    static let count = 4
    static var width: CGFloat { CGFloat(count) * barWidth + CGFloat(count - 1) * spacing }
    /// Heights while paused or silent (a fraction of the full height).
    static let restLevels: [CGFloat] = [0.22, 0.3, 0.26, 0.2]
    /// Heights while playing but not moving (Still, Reduce Motion).
    static let stillLevels: [CGFloat] = [0.5, 0.85, 0.65, 0.4]
    /// The lowest a bar goes while following the music, so it never disappears.
    static let minimumLevel: CGFloat = 0.16

    func makeNSView(context: Context) -> SoundBarsNSView {
        SoundBarsNSView()
    }

    func updateNSView(_ view: SoundBarsNSView, context: Context) {
        view.update(configuration, settings: settings)
    }

    static func dismantleNSView(_ view: SoundBarsNSView, coordinator: ()) {
        view.stopListening()
    }
}

final class SoundBarsNSView: NSView {
    /// What the bars look like right now.
    enum Pose: Equatable {
        case rest, still, dance, levels
    }

    private var bars: [CALayer] = []
    private var pose: Pose?
    private var barHeight: CGFloat = 0
    private var configuration: SoundBarsConfiguration?
    private weak var settings: NowPlayingSettings?
    private lazy var link: SoundBarsLink = {
        let link = SoundBarsAudio.shared.makeLink()
        link.onChange = { [weak self] in self?.refresh() }
        link.onLevels = { [weak self] levels in self?.show(levels) }
        return link
    }()
    private var occlusionObserver: NSObjectProtocol?
    private var sleepObservers: [NSObjectProtocol] = []
    private var screensAsleep = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<SoundBarsView.count {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            bar.cornerRadius = SoundBarsView.barWidth / 2
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: SoundBarsView.barWidth, height: barHeight)
            bar.position = CGPoint(x: CGFloat(index) * (SoundBarsView.barWidth + SoundBarsView.spacing) + SoundBarsView.barWidth / 2,
                                   y: bounds.midY)
        }
        CATransaction.commit()
    }

    func update(_ configuration: SoundBarsConfiguration, settings: NowPlayingSettings?) {
        if configuration.height != barHeight {
            barHeight = configuration.height
            needsLayout = true
        }
        self.configuration = configuration
        self.settings = settings
        refresh()
    }

    /// The view is going away: nothing may keep running for it.
    func stopListening() {
        configuration = nil
        link.cancel()
        removeObservers()
    }

    // MARK: Being seen

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            if sleepObservers.isEmpty {
                let workspace = NSWorkspace.shared.notificationCenter
                sleepObservers = [
                    workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.screensAsleep = true; self?.refresh() }
                    },
                    workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.screensAsleep = false; self?.refresh() }
                    },
                ]
            }
        } else {
            removeObservers()
        }
        refresh()
    }

    private func removeObservers() {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        for observer in sleepObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        sleepObservers = []
    }

    private var isOnScreen: Bool {
        guard let window, !screensAsleep else { return false }
        return window.occlusionState.contains(.visible)
    }

    // MARK: Deciding

    /// Works out the mode, starts or stops the listening it needs, and shows the right pose.
    private func refresh() {
        guard let configuration else {
            link.cancel()
            return
        }
        let mode = SoundBarsMode.resolve(
            style: configuration.style,
            access: configuration.access,
            isPractice: configuration.isPractice,
            hasSource: configuration.source != nil,
            isPlaying: configuration.isPlaying,
            isVisible: configuration.isShown && isOnScreen,
            reduceMotion: configuration.reduceMotion
        )
        switch mode {
        case .off, .still:
            link.cancel()
        case .gentle:
            link.follow(configuration.source, wantsLevels: false, settings: settings)
        case .real:
            link.follow(configuration.source, wantsLevels: true, settings: settings)
        }
        let isPlaying = configuration.isPlaying
        // Gentle motion only while the app really makes sound (nil = can't tell: go by "playing").
        let gentle: Pose = isPlaying && link.isRunningOutput != false ? .dance : .rest
        let pose: Pose = switch mode {
        case .off, .still: isPlaying ? .still : .rest
        case .gentle: gentle
        case .real:
            switch link.hearing {
            case .notHearing, .unavailable: gentle
            case .off, .waiting, .hearing: .levels
            }
        }
        apply(pose, smoothly: !configuration.reduceMotion)
    }

    // MARK: Drawing

    private func apply(_ pose: Pose, smoothly: Bool) {
        guard pose != self.pose else { return }
        self.pose = pose
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "dance")
            guard pose != .levels else { continue }
            let level = pose == .rest ? SoundBarsView.restLevels[index] : SoundBarsView.stillLevels[index]
            // Settle to the resting height with a short implicit animation.
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setDisableActions(!smoothly)
            bar.transform = CATransform3DMakeScale(1, level, 1)
            CATransaction.commit()
            guard pose == .dance else { continue }
            let dance = CABasicAnimation(keyPath: "transform.scale.y")
            dance.fromValue = [0.25, 0.35, 0.3, 0.2][index]
            dance.toValue = [0.9, 1.0, 0.8, 0.95][index]
            dance.duration = [0.42, 0.55, 0.36, 0.48][index]
            dance.autoreverses = true
            dance.repeatCount = .infinity
            dance.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dance.beginTime = CACurrentMediaTime() + [0, 0.12, 0.05, 0.2][index]
            dance.fillMode = .backwards
            bar.add(dance, forKey: "dance")
        }
    }

    /// New levels from the music. A very short linear glide between them, so 30 updates a second look fluid.
    private func show(_ levels: SoundLevels) {
        guard pose == .levels, let configuration else { return }
        let values = levels.bars(configuration.show)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.05)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for (index, bar) in bars.enumerated() {
            let level = SoundBarsView.minimumLevel + (1 - SoundBarsView.minimumLevel) * CGFloat(values[index])
            bar.transform = CATransform3DMakeScale(1, level, 1)
        }
        CATransaction.commit()
    }
}

/// The strip under the compact notch when a new song starts (if switched on in settings): tiny art,
/// the title and the artist.
struct NowPlayingPeek: View {
    let module: NowPlayingModule

    var body: some View {
        if let track = module.center.track {
            HStack(spacing: 6) {
                ArtworkImage(image: module.center.artwork, artworkID: track.artworkID, size: 14, cornerRadius: 3.5)
                Text(track.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Now playing: \(track.title)"))
        }
    }
}
