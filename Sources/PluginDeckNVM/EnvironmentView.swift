import SwiftUI

struct EnvironmentView: View {
    @EnvironmentObject private var model: NVMPluginModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            List {
                Section("健康检查") {
                    if model.isCheckingHealth && model.healthChecks.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在检查…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(model.healthChecks) { check in
                            healthRow(check)
                        }
                    }
                }

                Section("环境") {
                    valueRow("NVM 数据目录", value: model.state.nvmDirectory)
                    valueRow("NVM 加载脚本", value: model.state.nvmScript)
                    valueRow("默认版本", value: model.state.defaultVersion?.displayName ?? "未设置")
                    valueRow("系统架构", value: architecture)
                    valueRow("Shell", value: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
                }

                Section("操作") {
                    Button {
                        Task { await model.chooseCustomNVMDirectory() }
                    } label: {
                        Label("选择自定义 NVM 目录", systemImage: "folder.badge.gearshape")
                    }

                    if model.customNVMDirectory != nil {
                        Button {
                            Task { await model.clearCustomNVMDirectory() }
                        } label: {
                            Label("恢复自动检测", systemImage: "arrow.uturn.backward")
                        }
                    }

                    Button(action: model.revealNVMDirectory) {
                        Label("在访达中打开 NVM 目录", systemImage: "folder")
                    }
                    .disabled(model.state.nvmDirectory.isEmpty)

                    Button(action: model.copyShellConfiguration) {
                        Label("复制 Shell 初始化配置", systemImage: "doc.on.doc")
                    }
                    .disabled(model.state.nvmScript.isEmpty)
                }
            }
            .listStyle(.inset)
        }
        .task { await model.loadHealthChecks() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("环境")
                    .font(.title2.weight(.semibold))
                Text("NVM、Shell 与 Terminal 状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task {
                    await model.refresh()
                    await model.loadHealthChecks()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("重新检测")
            .disabled(model.isLoading || model.isCheckingHealth)
        }
        .padding(18)
    }

    private func healthRow(_ check: HealthCheck) -> some View {
        HStack(spacing: 11) {
            Image(systemName: healthIcon(check.level))
                .foregroundStyle(healthColor(check.level))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.body.weight(.medium))
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if check.fixCommand != nil {
                Button {
                    model.copyHealthFix(check)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("复制修复命令")
            }
        }
        .padding(.vertical, 4)
    }

    private func valueRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value.isEmpty ? "未检测到" : value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: 390, alignment: .trailing)
        }
    }

    private func healthIcon(_ level: HealthLevel) -> String {
        switch level {
        case .good: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        }
    }

    private func healthColor(_ level: HealthLevel) -> Color {
        switch level {
        case .good: .green
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }

    private var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "未知"
        #endif
    }
}
