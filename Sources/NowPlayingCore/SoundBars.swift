import Foundation

/// How the sound bars beside the notch move (Modules page, Now Playing settings).
public enum SoundBarsStyle: String, Sendable, CaseIterable {
    /// The bars move with the playing app's real sound (needs "System Audio Recording").
    case followMusic
    /// The bars dance on their own, only while the playing app is really making sound. No permission.
    case gentle
    /// The bars never move.
    case still
}

/// What each bar shows while the bars follow the music.
public enum SoundBarsShow: String, Sendable, CaseIterable {
    /// Each bar is a slice of the sound, from bass on the left to treble on the right.
    case bands
    /// Every bar follows how loud it is, each a little differently.
    case loudness
}

/// Whether macOS lets PancakeNotch hear the playing app, as far as it has seen.
public enum SoundBarsAccess: String, Sendable {
    /// Never tried, or the user pressed Try Again.
    case unknown
    /// Sound came through.
    case allowed
    /// Only silence came through while the app was making sound: the permission is off.
    case denied
}

/// What the bars do right now. Worked out from the setting and what's going on; nothing else decides
/// whether audio is listened to.
public enum SoundBarsMode: Equatable, Sendable {
    /// The bars can't be seen: nothing runs at all.
    case off
    /// The bars stand still (the Still setting, or Reduce Motion).
    case still
    /// The bars dance by themselves while the playing app makes sound (no listening).
    case gentle
    /// The bars follow the playing app's real sound.
    case real

    /// - Parameters:
    ///   - isPractice: the pretend player of the lessons and the Modules page (silent: never listened to).
    ///   - hasSource: the playing app's process is known, so there's something to listen to.
    ///   - isVisible: the bars are on screen (compact notch, window visible, display awake).
    public static func resolve(
        style: SoundBarsStyle,
        access: SoundBarsAccess,
        isPractice: Bool,
        hasSource: Bool,
        isPlaying: Bool,
        isVisible: Bool,
        reduceMotion: Bool
    ) -> SoundBarsMode {
        guard isVisible else { return .off }
        if reduceMotion || style == .still { return .still }
        if style == .followMusic, access != .denied, !isPractice, hasSource, isPlaying { return .real }
        return .gentle
    }
}

/// The app whose sound the bars follow: the process macOS says is playing, and the app's bundle IDs
/// (a browser plays from helper processes whose IDs start with its own).
public struct SoundSourceID: Hashable, Sendable {
    public var processID: Int32?
    public var bundleIDs: [String]

    public init?(processID: Int32?, bundleIDs: [String?]) {
        var ids: [String] = []
        for case let id? in bundleIDs where !id.isEmpty && !ids.contains(id) { ids.append(id) }
        guard processID != nil || !ids.isEmpty else { return nil }
        self.processID = processID
        self.bundleIDs = ids
    }

    public init?(track: NowPlayingTrack) {
        self.init(processID: track.processID, bundleIDs: [track.bundleID, track.sourceBundleID])
    }
}
