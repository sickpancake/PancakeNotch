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

/// Four sound bars in the compact notch: they dance while music plays and the ears are out, and settle
/// flat when paused. Not real audio levels (those would need a recording permission).
struct NowPlayingBarsEar: View {
    let module: NowPlayingModule
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isPlaying = module.center.track?.isPlaying ?? false
        // Only while they can be seen: in the compact notch, never while it's closed or open.
        let isMoving = isPlaying && module.notch?.state == .compact && !reduceMotion
        let barHeight = max(8, height - 17)
        Group {
            if module.isSnapshot {
                StillBars(levels: isPlaying ? [0.55, 0.95, 0.7, 0.4] : SoundBarsView.restLevels, height: barHeight)
            } else {
                SoundBarsView(isMoving: isMoving, isPlaying: isPlaying, height: barHeight, settlesSmoothly: !reduceMotion)
            }
        }
        .frame(width: SoundBarsView.width, height: barHeight)
        .opacity(module.center.track == nil ? 0.35 : 1)
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

/// The bars as Core Animation layers: the animation runs in the window server, so the app itself does
/// nothing between frames (AGENTS.md: ~0% CPU). It's removed whenever the bars can't be seen.
struct SoundBarsView: NSViewRepresentable {
    let isMoving: Bool
    let isPlaying: Bool
    let height: CGFloat
    /// Bars glide to their resting height (off with Reduce Motion: they jump).
    var settlesSmoothly = true

    static let barWidth: CGFloat = 2.5
    static let spacing: CGFloat = 2
    static let count = 4
    static var width: CGFloat { CGFloat(count) * barWidth + CGFloat(count - 1) * spacing }
    /// Heights while paused or still (a fraction of the full height).
    static let restLevels: [CGFloat] = [0.22, 0.3, 0.26, 0.2]
    /// Heights while playing but not moving (Reduce Motion).
    static let stillLevels: [CGFloat] = [0.5, 0.85, 0.65, 0.4]

    func makeNSView(context: Context) -> SoundBarsNSView {
        SoundBarsNSView()
    }

    func updateNSView(_ view: SoundBarsNSView, context: Context) {
        view.update(isMoving: isMoving, isPlaying: isPlaying, height: height, smoothly: settlesSmoothly)
    }
}

final class SoundBarsNSView: NSView {
    private var bars: [CALayer] = []
    private var isMoving = false
    private var isPlaying: Bool?
    private var barHeight: CGFloat = 0

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

    func update(isMoving: Bool, isPlaying: Bool, height: CGFloat, smoothly: Bool) {
        if height != barHeight {
            barHeight = height
            needsLayout = true
        }
        guard isMoving != self.isMoving || isPlaying != self.isPlaying else { return }
        self.isMoving = isMoving
        self.isPlaying = isPlaying
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "dance")
            let level = isPlaying ? SoundBarsView.stillLevels[index] : SoundBarsView.restLevels[index]
            // Settle to the resting height with a short implicit animation.
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setDisableActions(!smoothly)
            bar.transform = CATransform3DMakeScale(1, level, 1)
            CATransaction.commit()
            guard isMoving else { continue }
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
