import Foundation
import Testing
@testable import PluginDeckCore

@Test func marketplaceCatalogIsValid() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = repositoryRoot.appendingPathComponent("marketplace/catalog.json")
    let catalog = try PluginCatalog.decode(Data(contentsOf: url))

    for plugin in catalog.plugins {
        try PluginManifestValidator.validate(
            plugin,
            externalImport: true,
            marketplace: true
        )
    }
}
