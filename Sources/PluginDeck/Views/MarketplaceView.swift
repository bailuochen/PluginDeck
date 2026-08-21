import SwiftUI
import PluginDeckCore

struct MarketplaceView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importMode: PluginImportMode?
    @State private var detailPlugin: PluginManifest?

    private let columns = [
        GridItem(.adaptive(minimum: 290, maximum: 380), spacing: 14, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    PageHeader(
                        title: "插件市场",
                        subtitle: "发现经过清单校验、权限透明的开发工具插件。"
                    )
                    Spacer()
                    HStack(alignment: .top, spacing: 10) {
                        Menu {
                            Button {
                                importMode = .local
                            } label: {
                                Label("从本地目录导入", systemImage: "folder.badge.plus")
                            }
                            Button {
                                importMode = .git
                            } label: {
                                Label("从 Git 仓库导入", systemImage: "arrow.triangle.branch")
                            }
                        } label: {
                            Label("导入插件", systemImage: "square.and.arrow.down")
                        }
                        .fixedSize()

                        VStack(alignment: .trailing, spacing: 4) {
                            Button {
                                Task { await model.refreshMarketplaceCatalog() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("同步远程目录")
                            if let status = model.marketplaceStatus {
                                Text(status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                filters

                if let error = model.catalogError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else if model.filteredCatalog.isEmpty {
                    EmptyState(
                        icon: "magnifyingglass",
                        title: "没有匹配的插件",
                        message: "尝试更换搜索词或分类。"
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(model.filteredCatalog) { plugin in
                            pluginCard(plugin)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .searchable(text: $model.searchText, prompt: "搜索插件或能力")
        .sheet(item: $detailPlugin) { plugin in
            PluginDetailView(plugin: plugin)
                .environmentObject(model)
                .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 640)
        }
        .sheet(item: $importMode) { mode in
            PluginImportView(
                mode: mode,
                registry: model.registry,
                installer: model.pluginInstaller
            ) { artifact in
                model.destination = .installed
                model.selectedPlugin = artifact.manifest
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 8) {
            Button {
                model.selectedCategory = nil
            } label: {
                Text("全部")
            }
            .buttonStyle(.bordered)
            .tint(model.selectedCategory == nil ? .accentColor : .secondary)

            ForEach(PluginManifest.Category.allCases, id: \.self) { category in
                Button(category.displayName) {
                    model.selectedCategory = category
                }
                .buttonStyle(.bordered)
                .tint(model.selectedCategory == category ? .accentColor : .secondary)
            }
        }
    }

    private func pluginCard(_ plugin: PluginManifest) -> some View {
        Button {
            detailPlugin = plugin
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    PluginIcon(symbol: plugin.icon, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(plugin.name)
                                .font(.headline)
                            Spacer()
                            if plugin.releaseStatus == .planned {
                                Text("计划中")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        AuthorLabel(author: plugin.author)
                    }
                }

                Text(plugin.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 38, alignment: .topLeading)

                HStack {
                    Text(plugin.category.displayName)
                    Spacer()
                    if model.updateAvailable(for: plugin) {
                        Label("可更新", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    } else if model.registry.isInstalled(plugin.id) {
                        Label("已安装", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if plugin.releaseStatus == .available {
                        Text("查看")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
