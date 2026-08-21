import SwiftUI
import PluginDeckCore

struct ExternalPluginWorkspaceView: View {
    let plugin: InstalledPlugin
    let registry: PluginRegistry

    @State private var runningActionID: String?
    @State private var pendingAction: PluginManifest.Action?
    @State private var result: PluginActionResult?
    @State private var errorMessage: String?
    private let runner = ExternalPluginRunner()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            securityNotice
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            Divider()
            workspace
        }
        .confirmationDialog(
            pendingAction?.title ?? "确认执行",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            )
        ) {
            Button("执行") {
                guard let action = pendingAction else { return }
                pendingAction = nil
                run(action)
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: {
            Text(pendingAction?.description ?? "")
        }
    }

    @ViewBuilder
    private var workspace: some View {
        if plugin.manifest.ui != nil {
            ExternalPluginWebView(plugin: plugin, registry: registry)
                .id("\(plugin.id)-\(plugin.manifest.version)-\(plugin.packagePath ?? "")")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    actionsSection
                    if let result {
                        resultSection(result)
                    }
                    if let errorMessage {
                        errorSection(errorMessage)
                    }
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            PluginIcon(symbol: plugin.manifest.icon, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(plugin.manifest.name)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    Text("v\(plugin.manifest.version)")
                    Text(plugin.source?.displayName ?? "外部插件")
                    Text(plugin.manifest.author.name)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let repositoryURL = plugin.manifest.repositoryURL {
                Link(destination: repositoryURL) {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("查看源代码")
            }
        }
        .padding(18)
    }

    private var securityNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield")
                .foregroundStyle(.orange)
            Text("这是社区可执行插件。PluginDeck 会用单独进程和结构化协议运行它，但 macOS 不会强制限制它只能访问清单声明的资源。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("插件动作").font(.headline)
            ForEach(plugin.manifest.actions ?? []) { action in
                HStack(spacing: 13) {
                    Image(systemName: action.icon)
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.title).fontWeight(.medium)
                        Text(action.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if action.requiresConfirmation {
                            pendingAction = action
                        } else {
                            run(action)
                        }
                    } label: {
                        if runningActionID == action.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("运行", systemImage: "play.fill")
                        }
                    }
                    .disabled(runningActionID != nil)
                }
                .padding(.vertical, 10)
                Divider()
            }
        }
    }

    private func resultSection(_ result: PluginActionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(result.title ?? "执行完成", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(result.message)
            if let detail = result.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func errorSection(_ message: String) -> some View {
        Label(message, systemImage: "xmark.circle.fill")
            .foregroundStyle(.red)
            .textSelection(.enabled)
    }

    private func run(_ action: PluginManifest.Action) {
        runningActionID = action.id
        result = nil
        errorMessage = nil
        let taskID = registry.beginTask(
            pluginID: plugin.id,
            pluginName: plugin.manifest.name,
            kind: .run,
            message: action.title
        )
        Task {
            do {
                let response = try await runner.run(plugin: plugin, action: action)
                result = response
                registry.finishTask(taskID, succeeded: true, message: response.message)
            } catch {
                errorMessage = error.localizedDescription
                registry.finishTask(taskID, succeeded: false, message: error.localizedDescription)
            }
            runningActionID = nil
        }
    }
}
