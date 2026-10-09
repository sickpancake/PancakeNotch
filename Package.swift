// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PancakeNotch",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "PancakeNotch",
            dependencies: ["NotchCore"]
        ),
        .target(name: "NotchCore"),
        .testTarget(
            name: "NotchCoreTests",
            dependencies: ["NotchCore"]
        ),
    ]
)
