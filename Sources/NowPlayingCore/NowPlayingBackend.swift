import AppKit

/// A source of "what's playing": the mediaremote-adapter helper with its Music/Spotify fallback
/// (`NowPlayingCenter.live`), or the pretend player of the lessons (`PracticePlayer`).
///
/// Backends live on the main thread and report through the two callbacks; `NowPlayingCenter`
/// sets them before calling `start()`.
@MainActor
public protocol NowPlayingBackend: AnyObject {
    /// A new state of the player: the whole track (not just what changed), or nil when nothing is playing.
    var onUpdate: ((NowPlayingUpdate) -> Void)? { get set }
    var onConnectionChange: ((NowPlayingConnection) -> Void)? { get set }
    func start()
    func stop()
    func send(_ command: NowPlayingCommand)
    /// The long-running helper process, if there is one (its memory counts towards ours).
    var processID: pid_t? { get }
}

/// A backend that can start playback when nothing is playing, preferring the app that played last.
@MainActor
public protocol NowPlayingResumable: AnyObject {
    func resume(preferring bundleID: String?)
}

/// A backend that controls apps with AppleScript and can find out it isn't allowed to (Automation privacy setting).
@MainActor
public protocol NowPlayingAutomationReporting: AnyObject {
    var onAutomationPermissionChange: ((_ needsPermission: Bool) -> Void)? { get set }
}

/// One report from a backend.
public struct NowPlayingUpdate: @unchecked Sendable {
    /// nil = nothing is playing.
    public var track: NowPlayingTrack?
    /// At most 256 px. nil = unchanged when `track.artworkID` is unchanged, otherwise no artwork.
    /// (Made off the main thread and never changed afterwards, hence `@unchecked Sendable`.)
    public var artwork: NSImage?

    public init(track: NowPlayingTrack?, artwork: NSImage? = nil) {
        self.track = track
        self.artwork = artwork
    }
}
