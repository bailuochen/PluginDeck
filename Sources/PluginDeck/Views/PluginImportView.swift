import AppKit
import SwiftUI
import PluginDeckCore

enum PluginImportMode: String, Identifiable {
    case local
    case git

    var id: String { rawValue }
    var title: String { self == .local ? "本地目录" : "Git 仓库" }
}

struct PluginImportView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: PluginImportMode
    let registry: PluginRegistry
    let installer: PluginPackageInstaller
    let onInstalled: (InstalledPluginArtifact) -> Void

    @State private var candidate: PluginImportCandidate?
    @State private var gitURL = ""
    @State private var isWorking = false
    @State private var confirmsRisk = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sourceSection
                    if let candidate {
                        pluginPreview(candidate.manifest)
                        riskConfirmation
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 560, idealHeight: 640)
        .alert("无法导入插件", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: mode == .local ? "folder.badge.plus" : "arrow.triangle.branch")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("从\(mode.title)导入插件")
                    .font(.title2.weight(.semibold))
                Text(mode == .local
                     ? "选择包含 plugin.json 的开发目录。"
                     : "克隆包含 plugin.json 的公开 HTTPS 仓库。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                cancel()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("关闭")
        }
        .padding(22)
    }

    @ViewBuilder
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("插件来源").font(.headline)
            if mode == .local {
                HStack {
                    Text(candidate?.origin ?? "尚未选择目录")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(candidate == nil ? .secondary : .primary)
                    Spacer()
                    Button("选择目录") { chooseDirectory() }
                }
            } else {
                HStack {
                    TextField("https://github.com/developer/plugin.git", text: $gitURL)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        inspectGitRepository()
                    } label: {
                        if isWorking && candidate == nil {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("检查仓库")
                        }
                    }
                    .disabled(isWorking || gitURL.isEmpty)
                }
                Text("首版仅支持公开 HTTPS 仓库，不读取 SSH Key 或 Git 凭据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pluginPreview(_ manifest: PluginManifest) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Divider()
            HStack(alignment: .top, spacing: 14) {
                PluginIcon(symbol: manifest.icon, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(manifest.name).font(.title3.weight(.semibold))
                    Text(manifest.summary).foregroundStyle(.secondary)
                    Text("\(manifest.id) · v\(manifest.version) · \(manifest.author.name)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("声明权限").font(.headline)
                if manifest.permissions.isEmpty {
                    Text("未声明额外权限").foregroundStyle(.secondary)
                }
                ForEach(manifest.permissions, id: \.self) { permission in
                    Label(permission.displayName, systemImage: "checkmark.circle")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("可用动作").font(.headline)
                ForEach(manifest.actions ?? []) { action in
                    HStack {
                        Image(systemName: action.icon).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                            Text(action.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var riskConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("第三方代码执行", systemImage: "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("macOS 无法按 plugin.json 的声明强制隔离任意可执行文件。该插件将以你的当前用户权限运行，可能访问声明范围之外的数据。请先审阅并信任其源代码。")
                .foregroundStyle(.secondary)
            Toggle("我信任此来源并同意运行该插件", isOn: $confirmsRisk)
                .toggleStyle(.checkbox)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }

    private var footer: some View {
        HStack {
            Button("取消") { cancel() }
            Spacer()
            Button {
                installCandidate()
            } label: {
                if isWorking && candidate != nil {
                    ProgressView().controlSize(.small)
                } else {
                    Text("导入并启用")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(candidate == nil || !confirmsRisk || isWorking)
        }
        .padding(18)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择 PluginDeck 插件目录"
        panel.prompt = "检查插件"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isWorking = true
        Task {
            do {
                candidate = try await installer.inspectLocalDirectory(url)
                confirmsRisk = false
            } catch {
                errorMessage = error.localizedDescription
                candidate = nil
            }
            isWorking = false
        }
    }

    private func inspectGitRepository() {
        guard let url = URL(string: gitURL) else {
            errorMessage = "Git 地址无效"
            return
        }
        isWorking = true
        Task {
            do {
                if let candidate { await installer.cleanup(candidate) }
                candidate = try await installer.cloneGitRepository(url)
                confirmsRisk = false
            } catch {
                errorMessage = error.localizedDescription
                candidate = nil
            }
            isWorking = false
        }
    }

    private func installCandidate() {
        guard let candidate else { return }
        isWorking = true
        Task {
            do {
                let artifact = try await installer.install(candidate)
                registry.install(
                    artifact.manifest,
                    packagePath: artifact.packageDirectory.path,
                    source: artifact.source
                )
                onInstalled(artifact)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

    private func cancel() {
        if let candidate {
            Task { await installer.cleanup(candidate) }
        }
        dismiss()
    }
}
