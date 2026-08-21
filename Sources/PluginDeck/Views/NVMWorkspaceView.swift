import SwiftUI
import PluginDeckCore

struct NVMWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @State private var snapshot: NVMBridge.Snapshot?
    @State private var installVersion = "lts/*"
    @State private var isWorking = false
    @State private var operationOutput = ""
    @State private var pendingUninstall: String?
    private let bridge = NVMBridge()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    PageHeader(title: "NVM", subtitle: "管理本机 Node.js 版本与默认环境。")
                    Spacer()
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新")
                    .disabled(isWorking)
                }

                if let snapshot {
                    if snapshot.isInstalled {
                        environment(snapshot)
                        installSection
                        versionsSection(snapshot)
                    } else {
                        missingNVM(snapshot)
                    }
                } else {
                    ProgressView("正在检测 NVM")
                        .frame(maxWidth: .infinity, minHeight: 300)
                }

                if !operationOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近输出").font(.headline)
                        ScrollView(.horizontal) {
                            Text(operationOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .task { await refresh() }
        .confirmationDialog(
            "卸载 Node.js \(pendingUninstall ?? "")？",
            isPresented: Binding(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }
            )
        ) {
            Button("卸载", role: .destructive) {
                guard let version = pendingUninstall else { return }
                pendingUninstall = nil
                Task { await uninstall(version) }
            }
        } message: {
            Text("这会调用 nvm uninstall。不会卸载 NVM 本身。")
        }
    }

    private func environment(_ snapshot: NVMBridge.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("环境").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                statusRow("NVM", "已检测", color: .green)
                statusRow("当前终端版本", snapshot.currentVersion ?? "未启用", color: .secondary)
                statusRow("新终端默认版本", snapshot.defaultVersion ?? "未设置", color: .secondary)
                statusRow("目录", snapshot.directory, color: .secondary)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    }

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("安装 Node.js").font(.headline)
            HStack {
                TextField("版本，例如 22、lts/*、20.18.0", text: $installVersion)
                    .textFieldStyle(.roundedBorder)
                Button("安装") {
                    Task { await install() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || installVersion.isEmpty)
            }
            Text("安装由 NVM 执行，完整结果会记录到任务中心。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func versionsSection(_ snapshot: NVMBridge.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已安装版本").font(.headline)
            if snapshot.installedVersions.isEmpty {
                Text("暂无已安装版本")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
                ForEach(snapshot.installedVersions, id: \.self) { version in
                    HStack {
                        Image(systemName: version == snapshot.defaultVersion ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(version == snapshot.defaultVersion ? Color.green : Color.secondary)
                        Text(version).font(.body.monospaced())
                        if version == snapshot.defaultVersion {
                            Text("默认").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("设为默认") {
                            Task { await setDefault(version) }
                        }
                        .disabled(isWorking || version == snapshot.defaultVersion)
                        Button(role: .destructive) {
                            pendingUninstall = version
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("卸载 \(version)")
                        .disabled(isWorking || version == snapshot.currentVersion)
                    }
                    .padding(.vertical, 7)
                    Divider()
                }
            }
        }
    }

    private func missingNVM(_ snapshot: NVMBridge.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("未检测到 NVM", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text("PluginDeck 不会擅自修改你的 shell 配置。请先按 NVM 官方文档完成安装，然后返回刷新。")
                .foregroundStyle(.secondary)
            Link("打开 NVM 安装文档", destination: URL(string: "https://github.com/nvm-sh/nvm#installing-and-updating")!)
            Text("检测目录：\(snapshot.directory)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    }

    private func statusRow(_ title: String, _ value: String, color: Color) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).foregroundStyle(color).textSelection(.enabled)
        }
    }

    private func refresh() async {
        snapshot = await bridge.snapshot()
    }

    private func install() async {
        await perform(kind: .install, message: "安装 Node.js \(installVersion)") {
            await bridge.install(version: installVersion)
        }
    }

    private func uninstall(_ version: String) async {
        await perform(kind: .uninstall, message: "卸载 Node.js \(version)") {
            await bridge.uninstall(version: version)
        }
    }

    private func setDefault(_ version: String) async {
        await perform(kind: .update, message: "设置默认版本 \(version)") {
            await bridge.setDefault(version: version)
        }
    }

    private func perform(
        kind: PluginTask.Kind,
        message: String,
        operation: () async -> NVMBridge.CommandResult
    ) async {
        isWorking = true
        let taskID = model.registry.beginTask(
            pluginID: "dev.plugindeck.nvm",
            pluginName: "NVM",
            kind: kind,
            message: message
        )
        let result = await operation()
        operationOutput = [result.output, result.error].filter { !$0.isEmpty }.joined(separator: "\n")
        let succeeded = result.exitCode == 0
        model.registry.finishTask(
            taskID,
            succeeded: succeeded,
            message: succeeded ? "\(message)完成" : "\(message)失败"
        )
        await refresh()
        isWorking = false
    }
}
