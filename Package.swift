// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PluginDeck",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PluginDeck", targets: ["PluginDeck"]),
        .library(name: "PluginDeckCore", targets: ["PluginDeckCore"])
    ],
    targets: [
        .target(name: "PluginDeckCore"),
        .executableTarget(
            name: "PluginDeck",
            dependencies: ["PluginDeckCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PluginDeckCoreTests",
            dependencies: ["PluginDeckCore"]
        )
    ]
)
