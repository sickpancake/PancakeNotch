// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PancakeNotch",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "PancakeNotch",
            dependencies: ["NotchCore", "HotKey", "ModuleShelf", "ModuleNowPlaying", "NowPlayingCore", "Learn", "Stats"]
        ),
        .target(name: "NotchCore"),
        .target(name: "HotKey"),
        .target(name: "Learn"),
        // Listening, usage and app-health statistics in a local SQLite file (ADR-0018).
        .target(
            name: "Stats",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // What's playing: the mediaremote-adapter helper, the Music/Spotify fallback and the
        // practice player (ADR-0012). No UI.
        .target(name: "NowPlayingCore"),
        .target(
            name: "ModuleShelf",
            dependencies: ["NotchCore"]
        ),
        .target(
            name: "ModuleNowPlaying",
            dependencies: ["NotchCore", "NowPlayingCore"]
        ),
        .testTarget(
            name: "NotchCoreTests",
            dependencies: ["NotchCore"]
        ),
        .testTarget(
            name: "HotKeyTests",
            dependencies: ["HotKey"]
        ),
        .testTarget(
            name: "ModuleShelfTests",
            dependencies: ["ModuleShelf"]
        ),
        .testTarget(
            name: "LearnTests",
            dependencies: ["Learn"]
        ),
        .testTarget(
            name: "NowPlayingCoreTests",
            dependencies: ["NowPlayingCore"]
        ),
        .testTarget(
            name: "StatsTests",
            dependencies: ["Stats"]
        ),
    ]
)
