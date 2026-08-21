import Foundation
import Combine

@MainActor
public final class PluginRegistry: ObservableObject {
    @Published public private(set) var installed: [InstalledPlugin] = []
    @Published public private(set) var tasks: [PluginTask] = []

    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storageURL: URL) {
        self.storageURL = storageURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public convenience init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.init(storageURL: base.appendingPathComponent("PluginDeck/state.json"))
    }

    public func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let state = try? decoder.decode(State.self, from: data) else {
            return
        }
        installed = state.installed
        tasks = state.tasks
    }

    public func isInstalled(_ pluginID: String) -> Bool {
        installed.contains { $0.id == pluginID }
    }

    public func install(_ manifest: PluginManifest) {
        guard !isInstalled(manifest.id) else { return }
        var task = PluginTask(
            pluginID: manifest.id,
            pluginName: manifest.name,
            kind: .install,
            message: "正在验证插件清单"
        )
        tasks.insert(task, at: 0)

        installed.append(InstalledPlugin(manifest: manifest))
        task.status = .completed
        task.finishedAt = .now
        task.message = "插件已安装并启用"
        replaceTask(task)
        persist()
    }

    public func uninstall(_ pluginID: String) {
        guard let plugin = installed.first(where: { $0.id == pluginID }) else { return }
        var task = PluginTask(
            pluginID: pluginID,
            pluginName: plugin.manifest.name,
            kind: .uninstall,
            message: "正在移除插件"
        )
        tasks.insert(task, at: 0)
        installed.removeAll { $0.id == pluginID }
        task.status = .completed
        task.finishedAt = .now
        task.message = "插件数据已移除"
        replaceTask(task)
        persist()
    }

    public func setEnabled(_ isEnabled: Bool, pluginID: String) {
        guard let index = installed.firstIndex(where: { $0.id == pluginID }) else { return }
        installed[index].isEnabled = isEnabled
        installed[index].updatedAt = .now
        tasks.insert(
            PluginTask(
                pluginID: pluginID,
                pluginName: installed[index].manifest.name,
                kind: isEnabled ? .enable : .disable,
                status: .completed,
                finishedAt: .now,
                message: isEnabled ? "插件已启用" : "插件已停用"
            ),
            at: 0
        )
        persist()
    }

    public func clearCompletedTasks() {
        tasks.removeAll { $0.status == .completed }
        persist()
    }

    @discardableResult
    public func beginTask(
        pluginID: String,
        pluginName: String,
        kind: PluginTask.Kind,
        message: String
    ) -> UUID {
        let task = PluginTask(
            pluginID: pluginID,
            pluginName: pluginName,
            kind: kind,
            message: message
        )
        tasks.insert(task, at: 0)
        persist()
        return task.id
    }

    public func finishTask(_ id: UUID, succeeded: Bool, message: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = succeeded ? .completed : .failed
        tasks[index].finishedAt = .now
        tasks[index].message = message
        persist()
    }

    private func replaceTask(_ task: PluginTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(State(installed: installed, tasks: tasks))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            assertionFailure("Unable to persist PluginDeck state: \(error)")
        }
    }

    private struct State: Codable {
        let installed: [InstalledPlugin]
        let tasks: [PluginTask]
    }
}
