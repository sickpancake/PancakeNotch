// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PancakeNotch",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "PancakeNotch",
            dependencies: ["NotchCore", "HotKey"]
        ),
        .target(name: "NotchCore"),
        .target(name: "HotKey"),
        .testTarget(
            name: "NotchCoreTests",
            dependencies: ["NotchCore"]
        ),
        .testTarget(
            name: "HotKeyTests",
            dependencies: ["HotKey"]
        ),
    ]
)
