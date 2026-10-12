import AppKit
import NotchCore
import NowPlayingCore

/// A Now Playing that plays silent pretend songs, for the lesson and the Modules page: every button
/// works, and the user's real music is never touched (ADR-0031).
@MainActor
public final class PracticeNowPlaying {
    public let module: NowPlayingModule
    private var isClosed = false

    public init() {
        let center = NowPlayingCenter.practice()
        module = NowPlayingModule(center: center)
        center.start()
    }

    /// Stops the pretend player. Called when the page goes away; safe to call twice.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        module.onEvent = nil
        module.center.stop()
    }
}

/// Now Playing states for the off-screen snapshot (`PANCAKENOTCH_SNAPSHOT`), on the practice player.
@MainActor
public enum NowPlayingSnapshot {
    /// A module showing a pretend song, set up synchronously so the snapshot draws it straight away.
    public static func module(playing: Bool = true, elapsed: TimeInterval = 74) -> NowPlayingModule {
        let module = NowPlayingModule(center: NowPlayingCenter.practiceSnapshot(playing: playing, elapsed: elapsed))
        module.isSnapshot = true
        return module
    }

    public static func models(layout: NotchLayout) -> [NotchViewModel] {
        var rows: [NotchViewModel] = []
        func row(_ state: NotchState, _ module: NowPlayingModule, setUp: (NotchViewModel) -> Void = { _ in }) {
            let model = NotchViewModel(layout: layout, state: state)
            model.modules = [module]
            setUp(model)
            rows.append(model)
        }
        row(.compact, module(playing: true))
        row(.compact, module(playing: false))
        row(.expanded, module(playing: true))
        row(.expanded, module(playing: false, elapsed: 151))
        // Nothing playing: a practice center that has been stopped.
        let empty = NowPlayingModule(center: NowPlayingCenter.practiceSnapshot(playing: false, elapsed: 0, empty: true))
        empty.isSnapshot = true
        row(.expanded, empty)
        // A peek strip under the compact notch.
        row(.compact, module(playing: true)) { model in
            model.layout.isPeeking = true
            model.peekForSnapshot(model.modules[0])
        }
        return rows
    }
}
