import SwiftUI

struct SettingsView: View {
    @AppStorage("automaticallyCheckUpdates") private var automaticallyCheckUpdates = true
    @AppStorage("preferredTerminal") private var preferredTerminal = "Terminal"

    var body: some View {
        Form {
            Section("更新") {
                Toggle("自动检查宿主与插件更新", isOn: $automaticallyCheckUpdates)
                Text("第三方插件不会静默更新；新增权限时必须再次确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("终端") {
                Picker("首选终端", selection: $preferredTerminal) {
                    Text("Terminal").tag("Terminal")
                    Text("iTerm2").tag("iTerm2")
                }
                .pickerStyle(.menu)
            }

            Section("数据") {
                LabeledContent("插件目录", value: "~/Library/Application Support/PluginDeck/Plugins")
                LabeledContent("插件数据", value: "~/Library/Application Support/PluginDeck/PluginData")
                LabeledContent("任务与日志", value: "~/Library/Application Support/PluginDeck")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }
}
