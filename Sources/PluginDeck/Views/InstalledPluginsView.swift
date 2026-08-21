import SwiftUI
import PluginDeckCore
import PluginDeckNVM

struct InstalledPluginsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedID: String?

    private var selectedPlugin: InstalledPlugin? {
        model.registry.installed.first { $0.id == selectedID }
    }

    var body: some View {
        if model.registry.installed.isEmpty {
            EmptyState(
                icon: "shippingbox",
                title: "还没有安装插件",
                message: "从插件市场安装第一个开发工具插件。",
                actionTitle: "打开插件市场",
                action: { model.destination = .marketplace }
            )
        } else {
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("已安装")
                            .font(.title3.weight(.semibold))
                        Spacer()
                    }
                    .padding(16)
                    Divider()

                    List(model.registry.installed, selection: $selectedID) { plugin in
                        HStack(spacing: 10) {
                            PluginIcon(symbol: plugin.manifest.icon, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plugin.manifest.name)
                                Text(plugin.isEnabled ? "已启用" : "已停用")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(plugin.id)
                        .contextMenu {
                            Button(plugin.isEnabled ? "停用" : "启用") {
                                model.registry.setEnabled(!plugin.isEnabled, pluginID: plugin.id)
                            }
                            Divider()
                            Button("卸载", role: .destructive) {
                                model.registry.uninstall(plugin.id)
                                selectedID = model.registry.installed.first?.id
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 230, idealWidth: 260, maxWidth: 320)

                Group {
                    if let plugin = selectedPlugin {
                        if !plugin.isEnabled {
                            disabledView(plugin)
                        } else if plugin.packagePath != nil,
                                  !(plugin.manifest.actions ?? []).isEmpty {
                            ExternalPluginWorkspaceView(plugin: plugin, registry: model.registry)
                        } else if plugin.id == "dev.plugindeck.nvm" {
                            NVMPluginWorkspaceView(registry: model.registry)
                        } else {
                            genericWorkspace(plugin)
                        }
                    } else {
                        EmptyState(
                            icon: "cursorarrow.click",
                            title: "选择一个插件",
                            message: "选择左侧插件以打开它的工作区。"
                        )
                    }
                }
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                if selectedID == nil {
                    selectedID = model.registry.installed.first?.id
                }
            }
        }
    }

    private func disabledView(_ plugin: InstalledPlugin) -> some View {
        EmptyState(
            icon: "pause.circle",
            title: "\(plugin.manifest.name) 已停用",
            message: "启用插件后才能使用它的工作区。",
            actionTitle: "启用插件",
            action: { model.registry.setEnabled(true, pluginID: plugin.id) }
        )
    }

    private func genericWorkspace(_ plugin: InstalledPlugin) -> some View {
        EmptyState(
            icon: plugin.manifest.icon,
            title: plugin.manifest.name,
            message: "插件入口尚未提供可呈现的工作区。"
        )
    }
}
