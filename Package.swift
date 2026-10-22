// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PancakeNotch",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "PancakeNotch", targets: ["PancakeNotch"]),
        // The tiny hook helper the AI tools run after Connect (ADR-0037).
        .executable(name: "pancakenotch-hook", targets: ["AgentHook"]),
    ],
    dependencies: [
        // Automatic updates (ADR-0003, ADR-0005).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "PancakeNotch",
            dependencies: [
                "NotchCore", "HotKey", "ModuleShelf", "ModuleNowPlaying", "NowPlayingCore", "Learn", "Stats",
                "AgentsCore", "ModuleAgents",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
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
        // AI agents and their usage: the tools' own files, the hook socket, Connect, prices (ADR-0037). No UI.
        .target(
            name: "AgentsCore",
            dependencies: ["Stats"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "ModuleAgents",
            dependencies: ["NotchCore", "AgentsCore"]
        ),
        // C, so each hook call starts in a millisecond and has no runtime to load.
        .executableTarget(name: "AgentHook"),
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
        .testTarget(
            name: "AgentsCoreTests",
            dependencies: ["AgentsCore"]
        ),
        .testTarget(
            name: "ModuleAgentsTests",
            dependencies: ["ModuleAgents", "AgentsCore", "NotchCore"]
        ),
    ]
)
