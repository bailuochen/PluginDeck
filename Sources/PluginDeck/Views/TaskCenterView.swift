import SwiftUI
import PluginDeckCore

struct TaskCenterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                PageHeader(title: "任务中心", subtitle: "查看插件安装、更新与工具操作记录。")
                Spacer()
                if model.registry.tasks.contains(where: { $0.status == .completed }) {
                    Button("清除已完成") {
                        model.registry.clearCompletedTasks()
                    }
                }
            }
            .padding(28)

            Divider()

            if model.registry.tasks.isEmpty {
                EmptyState(
                    icon: "list.bullet.rectangle",
                    title: "暂无任务记录",
                    message: "插件执行的长任务与结果会统一显示在这里。"
                )
            } else {
                List(model.registry.tasks) { task in
                    HStack(alignment: .top, spacing: 12) {
                        statusIcon(task.status)
                            .font(.title3)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(task.pluginName).fontWeight(.medium)
                                Text(kindTitle(task.kind))
                                    .foregroundStyle(.secondary)
                            }
                            Text(task.message)
                                .font(.subheadline)
                                .foregroundStyle(task.status == .failed ? Color.red : Color.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(statusTitle(task.status))
                                .font(.caption.weight(.medium))
                            Text(task.startedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: PluginTask.Status) -> some View {
        switch status {
        case .running:
            ProgressView().controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "stop.circle.fill").foregroundStyle(.orange)
        }
    }

    private func statusTitle(_ status: PluginTask.Status) -> String {
        switch status {
        case .running: "进行中"
        case .completed: "已完成"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }

    private func kindTitle(_ kind: PluginTask.Kind) -> String {
        switch kind {
        case .install: "安装"
        case .uninstall: "卸载"
        case .update: "更新"
        case .enable: "启用"
        case .disable: "停用"
        }
    }
}
