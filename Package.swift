// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "F7TTY",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "GhosttyKit")],
    targets: [
        .target(name: "ProcessOwnership"),
        .executableTarget(
            name: "F7TTY",
            dependencies: [.product(name: "GhosttyKit", package: "GhosttyKit"), "ProcessOwnership"],
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "F7TTYTests",
            dependencies: ["F7TTY"]
        )
    ]
)
