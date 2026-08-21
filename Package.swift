// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PluginDeck",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PluginDeck", targets: ["PluginDeck"]),
        .library(name: "PluginDeckCore", targets: ["PluginDeckCore"]),
        .library(name: "PluginDeckNVM", targets: ["PluginDeckNVM"])
    ],
    targets: [
        .target(name: "PluginDeckCore"),
        .target(
            name: "PluginDeckNVM",
            dependencies: ["PluginDeckCore"]
        ),
        .executableTarget(
            name: "PluginDeck",
            dependencies: ["PluginDeckCore", "PluginDeckNVM"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PluginDeckCoreTests",
            dependencies: ["PluginDeckCore"]
        ),
        .testTarget(
            name: "PluginDeckNVMTests",
            dependencies: ["PluginDeckNVM"]
        )
    ]
)
