import Foundation
import Testing
@testable import PluginDeckCore

@Test func decodesValidCatalog() throws {
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "updatedAt": "2026-08-21T00:00:00Z",
              "plugins": [{
                "schemaVersion": 1,
                "id": "dev.example.tool",
                "name": "Tool",
                "summary": "Summary",
                "description": "Description",
                "version": "1.0.0",
                "category": "system",
                "author": {"name": "Example"},
                "trustLevel": "community",
                "releaseStatus": "available",
                "permissions": ["file.read"],
                "networkDomains": [],
                "compatibility": {
                  "minimumHostVersion": "0.1.0",
                  "minimumMacOSVersion": "13.0",
                  "architectures": ["arm64"]
                },
                "distribution": {},
                "icon": "wrench",
                "featured": false,
                "capabilities": []
              }]
            }
            """.utf8
        )

        let catalog = try PluginCatalog.decode(data)

    #expect(catalog.plugins.count == 1)
    #expect(catalog.plugins[0].id == "dev.example.tool")
    #expect(catalog.plugins[0].permissions == [.fileRead])
}

@Test func rejectsDuplicatePluginIDs() throws {
        let manifest = PluginManifest(
            id: "dev.example.duplicate",
            name: "Duplicate",
            summary: "Summary",
            description: "Description",
            version: "1.0.0",
            category: .system,
            author: .init(name: "Example"),
            trustLevel: .community,
            permissions: [],
            compatibility: .init(
                minimumHostVersion: "0.1.0",
                minimumMacOSVersion: "13.0",
                architectures: ["arm64"]
            ),
            icon: "wrench"
        )
        let catalog = PluginCatalog(updatedAt: .now, plugins: [manifest, manifest])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

    #expect(throws: CatalogError.self) {
        try PluginCatalog.decode(encoder.encode(catalog))
    }
}
