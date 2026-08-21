import SwiftUI

struct DeveloperCenterView: View {
    private let repositoryURL = URL(string: "https://github.com/bailuochen/PluginDeck")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "开发者中心",
                    subtitle: "为 PluginDeck 构建权限透明、可独立运行的开发工具插件。"
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("插件基础约定").font(.headline)
                    requirement("plugin.json", "声明身份、兼容范围、入口、权限与发布信息")
                    requirement("JSON-RPC 2.0", "插件在独立进程中与宿主交换结构化消息")
                    requirement("SHA-256", "发布包必须提供固定下载地址与完整性校验值")
                    requirement("最小权限", "仅申请完成具体功能所需的命令、目录和网络域名")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("本地开发").font(.headline)
                    Text("仓库的 docs 目录包含插件清单规范、进程协议和生命周期说明。首个 NVM 插件同时作为参考实现。")
                        .foregroundStyle(.secondary)
                    Link(destination: repositoryURL) {
                        Label("查看 GitHub 仓库", systemImage: "arrow.up.right.square")
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("安全边界").font(.headline)
                    Text("PluginDeck 不会将第三方 Swift 动态库加载进宿主。可执行插件运行在独立子进程中；宿主只通过版本化 JSON-RPC 协议开放有限能力。")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func requirement(_ title: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
            Text(title)
                .font(.body.monospaced())
                .frame(width: 130, alignment: .leading)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}
