import SwiftUI

struct DiscoverVersionsView: View {
    @EnvironmentObject private var model: NVMPluginModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.isLoadingRemote && model.remoteVersions.isEmpty {
                ProgressView("正在获取 Node.js 版本…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filteredRemoteVersions.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: model.remoteSearch.isEmpty ? "没有获取到在线版本" : "没有匹配的版本"
                )
            } else {
                List(model.filteredRemoteVersions) { release in
                    remoteRow(release)
                }
                .listStyle(.inset)
                .searchable(text: $model.remoteSearch, prompt: "搜索版本、LTS、npm 或日期")
            }
        }
        .task { await model.loadRemoteVersions() }
        .onChange(of: model.remoteFilter) { _ in
            Task { await model.loadRemoteVersions() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("在线版本")
                    .font(.title2.weight(.semibold))
                Text("\(model.remoteVersions.count) 个可用版本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("版本范围", selection: $model.remoteFilter) {
                ForEach(RemoteVersionFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)

            Button {
                Task { await model.loadRemoteVersions(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("重新获取")
            .disabled(model.isLoadingRemote)
        }
        .padding(18)
    }

    private func remoteRow(_ release: RemoteNodeVersion) -> some View {
        let installed = model.isInstalled(release.version)
        let installing = model.installingVersion == release.version

        return HStack(spacing: 12) {
            Image(systemName: release.ltsName == nil ? "circle.dotted" : "seal")
                .foregroundStyle(release.ltsName == nil ? Color.secondary : Color.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(release.version.displayName)
                        .font(.system(.body, design: .monospaced, weight: .semibold))

                    if model.isNewestRemoteVersion(release) {
                        releaseBadge(release.ltsName == nil ? "最新版本" : "最新 LTS", color: .blue)
                    } else if model.isNewestPatch(release) {
                        releaseBadge("主版本最新", color: .secondary)
                    }

                    if release.isSecurityRelease {
                        Label("安全更新", systemImage: "shield.checkered")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }

                releaseMetadata(release)
            }

            Spacer()
            trailingControl(for: release, installed: installed, installing: installing)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
        }
        .frame(minHeight: 62)
        .padding(.vertical, 5)
    }

    private func metadataLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func releaseMetadata(_ release: RemoteNodeVersion) -> some View {
        ViewThatFits(in: .horizontal) {
            fullMetadataLine(release)

            VStack(alignment: .leading, spacing: 4) {
                primaryMetadataLine(release)
                secondaryMetadataLine(release)
            }
        }
        .lineLimit(1)
    }

    private func fullMetadataLine(_ release: RemoteNodeVersion) -> some View {
        HStack(spacing: 12) {
            primaryMetadataLine(release)
            secondaryMetadataLine(release)
        }
    }

    private func primaryMetadataLine(_ release: RemoteNodeVersion) -> some View {
        HStack(spacing: 12) {
            metadataLabel(
                release.ltsName.map { "LTS · \($0)" } ?? "Current",
                icon: release.ltsName == nil ? "sparkles" : "seal"
            )
            if let releaseDate = release.releaseDate {
                metadataLabel(releaseDate, icon: "calendar")
            }
            if let npmVersion = release.npmVersion {
                metadataLabel("npm \(npmVersion)", icon: "shippingbox")
            }
        }
    }

    private func secondaryMetadataLine(_ release: RemoteNodeVersion) -> some View {
        HStack(spacing: 12) {
            if let v8Version = release.v8Version {
                metadataLabel("V8 \(v8Version)", icon: "cpu")
            }
            if let architectures = release.macArchitectureSummary {
                metadataLabel(architectures, icon: "desktopcomputer")
            }
        }
    }

    @ViewBuilder
    private func trailingControl(
        for release: RemoteNodeVersion,
        installed: Bool,
        installing: Bool
    ) -> some View {
        if installed {
            Label("已安装", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if installing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 58)
        } else {
            Button {
                Task { await model.install(release.version) }
            } label: {
                Label("安装", systemImage: "arrow.down.to.line")
            }
            .disabled(model.installingVersion != nil)
        }
    }

    private func releaseBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }
}
