import SwiftUI

struct InstalledVersionsView: View {
    @EnvironmentObject private var model: NVMPluginModel
    @State private var pendingRemoval: NodeVersion?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.isLoading && model.state.versions.isEmpty {
                ProgressView("正在读取 NVM…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.state.versions.isEmpty {
                EmptyStateView(icon: "shippingbox", title: "没有已安装的 Node.js 版本")
            } else {
                List(model.state.versions) { version in
                    installedRow(version)
                }
                .listStyle(.inset)
            }
        }
        .alert(item: $pendingRemoval) { version in
            Alert(
                title: Text("卸载 \(version.displayName)？"),
                message: Text("这会删除该版本及其全局安装的 npm 包。"),
                primaryButton: .destructive(Text("卸载")) {
                    Task { await model.uninstall(version) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("已安装")
                    .font(.title2.weight(.semibold))
                Text("\(model.state.versions.count) 个 Node.js 版本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新")
            .disabled(model.isLoading)
        }
        .padding(18)
    }

    private func installedRow(_ version: NodeVersion) -> some View {
        let isDefault = version == model.state.defaultVersion
        let isBusy = version == model.changingVersion || version == model.uninstallingVersion

        return HStack(spacing: 12) {
            Image(systemName: isDefault ? "checkmark.circle.fill" : "shippingbox")
                .font(.system(size: 18))
                .foregroundStyle(isDefault ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(version.displayName)
                    .font(.system(.body, design: .monospaced, weight: .medium))
                Text(isDefault ? "默认版本" : "已安装")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28)
            } else {
                Button {
                    Task { await model.select(version) }
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .buttonStyle(.borderless)
                .help("设为默认版本")
                .disabled(isDefault)

                Button {
                    Task { await model.openTerminal(using: version) }
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .help("用 \(version.displayName) 打开终端")

                Button(role: .destructive) {
                    pendingRemoval = version
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isDefault ? Color.secondary : Color.red)
                .help(
                    isDefault
                        ? "默认版本不能卸载，请先设置其他默认版本"
                        : "卸载 \(version.displayName)"
                )
                .disabled(isDefault)
            }
        }
        .frame(minHeight: 52)
        .padding(.vertical, 3)
    }
}
