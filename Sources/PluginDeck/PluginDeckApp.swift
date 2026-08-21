import SwiftUI
import PluginDeckCore

@main
struct PluginDeckApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 620, height: 420)
        }
    }
}
