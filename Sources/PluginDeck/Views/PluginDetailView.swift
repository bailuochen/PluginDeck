import SwiftUI
import PluginDeckCore

struct PluginDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let plugin: PluginManifest
    @State private var confirmsPermissions = false
    @State private var installError: String?

    private var installed: InstalledPlugin? {
        model.registry.installed.first { $0.id == plugin.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                PluginIcon(symbol: plugin.icon, size: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(plugin.name)
                        .font(.title2.weight(.semibold))
                    Text(plugin.summary)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        TrustBadge(level: plugin.trustLevel)
                        Text("v\(plugin.version)")
                        Text(plugin.author.name)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("关于") {
                        Text(plugin.description)
                            .foregroundStyle(.secondary)
                    }

                    section("主要能力") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(plugin.capabilities, id: \.self) { capability in
                                Label(capability, systemImage: "checkmark")
                            }
                        }
                    }

                    section("权限") {
                        VStack(alignment: .leading, spacing: 10) {
                            if plugin.trustLevel == .community {
                                Label(
                                    "社区插件会以当前 macOS 用户权限运行，请仅安装你信任的源代码。",
                                    systemImage: "exclamationmark.shield"
                                )
                                .foregroundStyle(.orange)
                            }
                            if plugin.permissions.isEmpty {
                                Text("此插件不申请额外权限")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(plugin.permissions, id: \.self) { permission in
                                HStack(alignment: .firstTextBaseline) {
                                    Image(systemName: permissionIcon(permission))
                                        .frame(width: 18)
                                        .foregroundStyle(.secondary)
                                    Text(permission.displayName)
                                }
                            }
                            if !plugin.networkDomains.isEmpty {
                                Text("允许联网：\(plugin.networkDomains.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    section("兼容性与来源") {
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                            detailRow("macOS", "\(plugin.compatibility.minimumMacOSVersion)+")
                            detailRow("宿主版本", "\(plugin.compatibility.minimumHostVersion)+")
                            detailRow("架构", plugin.compatibility.architectures.joined(separator: ", "))
                            if let repositoryURL = plugin.repositoryURL {
                                GridRow {
                                    Text("源代码").foregroundStyle(.secondary)
                                    Link(repositoryURL.host ?? repositoryURL.absoluteString, destination: repositoryURL)
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                if let installed {
                    Text("已安装 v\(installed.manifest.version)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("卸载", role: .destructive) {
                        model.registry.uninstall(plugin.id)
                        dismiss()
                    }
                    Button("打开插件") {
                        model.destination = .installed
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else if plugin.releaseStatus == .planned {
                    Label("该插件正在规划中", systemImage: "clock")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("关闭") { dismiss() }
                } else {
                    Toggle("我已了解上述权限", isOn: $confirmsPermissions)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Button {
                        Task {
                            do {
                                try await model.install(plugin)
                                model.destination = .installed
                                dismiss()
                            } catch {
                                installError = error.localizedDescription
                            }
                        }
                    } label: {
                        if model.installingPluginID == plugin.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("安装插件")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        model.installingPluginID != nil
                            || (!confirmsPermissions && !plugin.permissions.isEmpty)
                    )
                }
            }
            .padding(18)
        }
        .alert("安装失败", isPresented: Binding(
            get: { installError != nil },
            set: { if !$0 { installError = nil } }
        )) {
            Button("好") { installError = nil }
        } message: {
            Text(installError ?? "未知错误")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func permissionIcon(_ permission: PluginManifest.Permission) -> String {
        switch permission {
        case .network: "network"
        case .shell: "terminal"
        case .fileRead: "doc.text.magnifyingglass"
        case .fileWrite: "square.and.pencil"
        case .processRead: "waveform.path.ecg"
        }
    }
}
