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

    let registry = PluginRegistry()

    init() {
        registry.load()
        loadCatalog()
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

    private func loadCatalog() {
        let url = Bundle.main.url(forResource: "catalog", withExtension: "json")
            ?? Bundle.module.url(forResource: "catalog", withExtension: "json")
        guard let url else {
            catalogError = "未找到内置插件目录"
            return
        }
        do {
            catalog = try PluginCatalog.decode(Data(contentsOf: url)).plugins
        } catch {
            catalogError = error.localizedDescription
        }
    }
}
