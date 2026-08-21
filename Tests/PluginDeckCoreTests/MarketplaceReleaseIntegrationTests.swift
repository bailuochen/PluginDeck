import Foundation
import Testing
@testable import PluginDeckCore

@Test func marketplaceReleasePackagesCanBeInstalled() async throws {
    guard ProcessInfo.processInfo.environment["PLUGINDECK_MARKETPLACE_INTEGRATION"] == "1" else {
        return
    }

    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let catalogURL = repositoryRoot.appendingPathComponent("marketplace/catalog.json")
    let catalog = try PluginCatalog.decode(Data(contentsOf: catalogURL))
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("PluginDeckMarketplaceTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let installer = PluginPackageInstaller(
        pluginsDirectory: temporaryRoot.appendingPathComponent("Plugins", isDirectory: true)
    )
    for plugin in catalog.plugins {
        let candidate = try await installer.prepareMarketplacePlugin(plugin)
        let artifact = try await installer.install(candidate)
        let executable = artifact.packageDirectory
            .appendingPathComponent(plugin.entryPoint?.executable ?? "")
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
    }
}
