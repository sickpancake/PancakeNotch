// swift-tools-version:6.0
import PackageDescription

// Switches that point the app at other folders, files or code (PANCAKENOTCH_SHELF_DIR, …_ADAPTER_DIR…)
// exist only in builds for testing: debug builds, and release builds made with
// PANCAKENOTCH_INTERNAL_TESTING=1 scripts/build-app.sh (CI's memory checks). Published builds ignore them.
let testing: [SwiftSetting] = [.define("PANCAKENOTCH_INTERNAL_TESTING", .when(configuration: .debug))]

let package = Package(
    name: "PancakeNotch",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "PancakeNotch", targets: ["PancakeNotch"]),
        // The tiny hook helper the AI tools run after Connect (ADR-0037).
        .executable(name: "pancakenotch-hook", targets: ["AgentHook"]),
        // The Shelf's conversion helper (ADR-0038): started per job, so the app never loads the media frameworks.
        .executable(name: "pancakenotch-convert", targets: ["ConvertHelper"]),
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
                "AgentsCore", "ModuleAgents", "ConvertKit", "TimerCore", "ModuleTimer",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: testing
        ),
        .target(name: "NotchCore"),
        .target(name: "HotKey"),
        .target(name: "Learn"),
        // Listening, usage and app-health statistics in a local SQLite file (ADR-0018).
        .target(
            name: "Stats",
            swiftSettings: testing,
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // What's playing: the mediaremote-adapter helper, the Music/Spotify fallback and the
        // practice player (ADR-0012). No UI.
        .target(name: "NowPlayingCore", swiftSettings: testing),
        // AI agents and their usage: the tools' own files, the hook socket, Connect, prices (ADR-0037). No UI.
        .target(
            name: "AgentsCore",
            dependencies: ["Stats"],
            swiftSettings: testing,
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "ModuleAgents",
            dependencies: ["NotchCore", "AgentsCore"]
        ),
        // C, so each hook call starts in a millisecond and has no runtime to load.
        .executableTarget(name: "AgentHook", cSettings: [.define("PANCAKENOTCH_INTERNAL_TESTING", .when(configuration: .debug))]),
        .target(
            name: "ModuleShelf",
            dependencies: ["NotchCore", "ConvertKit"],
            swiftSettings: testing
        ),
        // Convert (ADR-0038): formats, limits and the helper's messages. Foundation only, for the app.
        .target(name: "ConvertKit"),
        // The conversions themselves (ImageIO, PDFKit, AVFoundation, AppKit's text system). Helper only.
        .target(
            name: "ConvertEngine",
            dependencies: ["ConvertKit"]
        ),
        .executableTarget(
            name: "ConvertHelper",
            dependencies: ["ConvertKit", "ConvertEngine"]
        ),
        .target(
            name: "ModuleNowPlaying",
            dependencies: ["NotchCore", "NowPlayingCore"]
        ),
        // The timer and stopwatch: their state, saving, the alarm, settings and sounds (ADR-0040). No UI.
        .target(name: "TimerCore"),
        .target(
            name: "ModuleTimer",
            dependencies: ["NotchCore", "TimerCore"]
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
            dependencies: ["ModuleShelf", "ConvertKit"]
        ),
        .testTarget(
            name: "ConvertTests",
            dependencies: ["ConvertKit", "ConvertEngine"]
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
            name: "TimerTests",
            dependencies: ["TimerCore", "ModuleTimer", "NotchCore"]
        ),
        .testTarget(
            name: "ModuleAgentsTests",
            dependencies: ["ModuleAgents", "AgentsCore", "NotchCore"]
        ),
    ]
)
