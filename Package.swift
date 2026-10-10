// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PancakeNotch",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "PancakeNotch",
            dependencies: ["NotchCore", "HotKey", "ModuleShelf"]
        ),
        .target(name: "NotchCore"),
        .target(name: "HotKey"),
        .target(
            name: "ModuleShelf",
            dependencies: ["NotchCore"]
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
    ]
)
