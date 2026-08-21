import Foundation

public enum CatalogError: LocalizedError {
    case unsupportedSchema(Int)
    case duplicatePluginID(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "不支持目录格式版本 \(version)"
        case .duplicatePluginID(let id):
            "插件目录包含重复 ID：\(id)"
        }
    }
}

public struct PluginCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let updatedAt: Date
    public let plugins: [PluginManifest]

    public init(schemaVersion: Int = 1, updatedAt: Date, plugins: [PluginManifest]) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.plugins = plugins
    }

    public static func decode(_ data: Data) throws -> PluginCatalog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(PluginCatalog.self, from: data)
        guard catalog.schemaVersion == 1 else {
            throw CatalogError.unsupportedSchema(catalog.schemaVersion)
        }

        var ids = Set<String>()
        for plugin in catalog.plugins where !ids.insert(plugin.id).inserted {
            throw CatalogError.duplicatePluginID(plugin.id)
        }
        return catalog
    }
}
