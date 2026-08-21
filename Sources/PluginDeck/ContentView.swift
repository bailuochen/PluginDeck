import SwiftUI
import PluginDeckCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.destination) {
                Section {
                    sidebarItem(.home)
                    sidebarItem(.marketplace)
                    sidebarItem(.installed, badge: model.registry.installed.count)
                    sidebarItem(.tasks, badge: runningTaskCount)
                }

                Section("管理") {
                    sidebarItem(.settings)
                    sidebarItem(.developer)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("PluginDeck")
        } detail: {
            Group {
                switch model.destination ?? .home {
                case .home: DashboardView()
                case .marketplace: MarketplaceView()
                case .installed: InstalledPluginsView()
                case .tasks: TaskCenterView()
                case .settings: SettingsView()
                case .developer: DeveloperCenterView()
                }
            }
            .environmentObject(model)
        }
        .sheet(item: $model.selectedPlugin) { plugin in
            PluginDetailView(plugin: plugin)
                .environmentObject(model)
                .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 640)
        }
    }

    private var runningTaskCount: Int {
        model.registry.tasks.filter { $0.status == .running }.count
    }

    private func sidebarItem(_ destination: AppModel.Destination, badge: Int = 0) -> some View {
        NavigationLink(value: destination) {
            Label {
                HStack {
                    Text(destination.title)
                    Spacer()
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: destination.icon)
            }
        }
    }
}
