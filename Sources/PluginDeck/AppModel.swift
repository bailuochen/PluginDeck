import Foundation
import PluginDeckCore

@MainActor
final class AppModel: ObservableObject {
    enum Destination: String, CaseIterable, Identifiable {
        case home
        case marketplace
        case installed
        case tasks
        case settings
        case developer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: "首页"
            case .marketplace: "插件市场"
            case .installed: "已安装"
            case .tasks: "任务中心"
            case .settings: "设置"
            case .developer: "开发者中心"
            }
        }

        var icon: String {
            switch self {
            case .home: "house"
            case .marketplace: "square.grid.2x2"
            case .installed: "shippingbox"
            case .tasks: "list.bullet.rectangle"
            case .settings: "gearshape"
            case .developer: "hammer"
            }
        }
    }

    @Published var destination: Destination? = .home
    @Published var catalog: [PluginManifest] = []
    @Published var catalogError: String?
    @Published var selectedPlugin: PluginManifest?
    @Published var searchText = ""
    @Published var selectedCategory: PluginManifest.Category?
    @Published var installingPluginID: String?
    @Published var marketplaceStatus: String?

    let registry = PluginRegistry()
    lazy var pluginInstaller = PluginPackageInstaller(pluginsDirectory: registry.pluginsDirectory)
    private let remoteCatalogURL = URL(
        string: "https://raw.githubusercontent.com/bailuochen/PluginDeck/main/marketplace/catalog.json"
    )!

    init() {
        registry.load()
        loadCatalog()
        Task { await refreshMarketplaceCatalog() }
    }

    var filteredCatalog: [PluginManifest] {
        catalog.filter { plugin in
            let matchesCategory = selectedCategory == nil || plugin.category == selectedCategory
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || plugin.name.localizedCaseInsensitiveContains(query)
                || plugin.summary.localizedCaseInsensitiveContains(query)
                || plugin.capabilities.contains { $0.localizedCaseInsensitiveContains(query) }
            return matchesCategory && matchesSearch
        }
    }

    func show(_ plugin: PluginManifest) {
        selectedPlugin = plugin
    }

    func openInstalled(_ plugin: InstalledPlugin) {
        selectedPlugin = plugin.manifest
        destination = .installed
    }

    func install(_ plugin: PluginManifest) async throws {
        guard installingPluginID == nil else { return }
        installingPluginID = plugin.id
        defer { installingPluginID = nil }

        let candidate = try await pluginInstaller.prepareMarketplacePlugin(plugin)
        let artifact = try await pluginInstaller.install(candidate)
        registry.install(
            artifact.manifest,
            packagePath: artifact.packageDirectory.path,
            source: artifact.source
        )
    }

    func updateAvailable(for plugin: PluginManifest) -> Bool {
        guard let installed = registry.installed.first(where: { $0.id == plugin.id }) else {
            return false
        }
        if installed.packagePath == nil, plugin.entryPoint?.executable.hasPrefix("builtin:") != true {
            return true
        }
        return PluginManifestValidator.compareVersions(
            plugin.version,
            installed.manifest.version
        ) > 0
    }

    func refreshMarketplaceCatalog() async {
        do {
            var components = URLComponents(url: remoteCatalogURL, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "t", value: String(Int(Date.now.timeIntervalSince1970)))
            ]
            var request = URLRequest(
                url: components?.url ?? remoteCatalogURL,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 15
            )
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return }
            let remote = try PluginCatalog.decode(data)
            var merged = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
            for plugin in remote.plugins {
                try PluginManifestValidator.validate(
                    plugin,
                    externalImport: true,
                    marketplace: true
                )
                merged.removeValue(forKey: plugin.id)
            }
            catalog = stableFeaturedOrder(remote.plugins + catalog.compactMap { merged[$0.id] })
            marketplaceStatus = "已同步远程目录"
        } catch {
            marketplaceStatus = "使用内置目录"
        }
    }

    private func loadCatalog() {
        let url = Bundle.main.url(forResource: "catalog", withExtension: "json")
            ?? Bundle.module.url(forResource: "catalog", withExtension: "json")
        guard let url else {
            catalogError = "未找到内置插件目录"
            return
        }
        do {
            catalog = stableFeaturedOrder(try PluginCatalog.decode(Data(contentsOf: url)).plugins)
        } catch {
            catalogError = error.localizedDescription
        }
    }

    private func stableFeaturedOrder(_ plugins: [PluginManifest]) -> [PluginManifest] {
        plugins.filter(\.featured) + plugins.filter { !$0.featured }
    }
}
