import SwiftUI
import PluginDeckCore

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(
                    title: greeting,
                    subtitle: "从一个地方管理你的开发工具插件与任务。"
                )

                if model.registry.installed.isEmpty {
                    onboarding
                } else {
                    installedSection
                }

                featuredSection

                if !model.registry.tasks.isEmpty {
                    recentActivity
                }
            }
            .padding(28)
            .frame(maxWidth: 1040, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 12 { return "上午好" }
        if hour < 18 { return "下午好" }
        return "晚上好"
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("开始使用", systemImage: "sparkles")
                .font(.headline)
            Text("安装官方 NVM 插件，体验从发现、授权到执行任务的完整流程。")
                .foregroundStyle(.secondary)
            Button("浏览插件市场") {
                model.destination = .marketplace
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    }

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近使用")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach(model.registry.installed.prefix(4)) { plugin in
                    Button {
                        model.openInstalled(plugin)
                    } label: {
                        HStack(spacing: 12) {
                            PluginIcon(symbol: plugin.manifest.icon)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(plugin.manifest.name).fontWeight(.medium)
                                Text(plugin.isEnabled ? "已启用" : "已停用")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("官方插件")
                    .font(.headline)
                Spacer()
                Button("查看全部") { model.destination = .marketplace }
                    .buttonStyle(.link)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                ForEach(model.catalog.filter(\.featured)) { plugin in
                    Button { model.show(plugin) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            PluginIcon(symbol: plugin.icon)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(plugin.name).fontWeight(.semibold)
                                    Spacer()
                                    TrustBadge(level: plugin.trustLevel)
                                }
                                Text(plugin.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                    }
                    .buttonStyle(.plain)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近活动")
                .font(.headline)
            ForEach(model.registry.tasks.prefix(3)) { task in
                HStack {
                    Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "clock")
                        .foregroundStyle(task.status == .completed ? Color.green : Color.secondary)
                    Text(task.pluginName)
                    Text(task.message)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(task.startedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
