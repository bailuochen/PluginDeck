import Foundation
import Testing
@testable import PluginDeckCore

@Test func activityDateUsesCompletionTimeWhenAvailable() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let finishedAt = Date(timeIntervalSince1970: 160)
        let completed = PluginTask(
            pluginID: "dev.example.tool",
            pluginName: "Tool",
            kind: .run,
            status: .completed,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
        let running = PluginTask(
            pluginID: "dev.example.tool",
            pluginName: "Tool",
            kind: .run,
            startedAt: startedAt
        )

        #expect(completed.activityDate == finishedAt)
        #expect(running.activityDate == startedAt)
}

@MainActor
@Test func installDisableAndUninstall() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = PluginRegistry(storageURL: directory.appendingPathComponent("state.json"))
        let manifest = makeManifest()

        registry.install(manifest)
        #expect(registry.isInstalled(manifest.id))
        #expect(registry.tasks.first?.kind == .install)

        registry.setEnabled(false, pluginID: manifest.id)
        #expect(registry.installed.first?.isEnabled == false)

        registry.uninstall(manifest.id)
        #expect(!registry.isInstalled(manifest.id))
}

@MainActor
@Test func statePersists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let first = PluginRegistry(storageURL: url)
        first.install(makeManifest())

        let second = PluginRegistry(storageURL: url)
        second.load()

        #expect(second.installed.first?.id == "dev.example.tool")
}

@MainActor
@Test func runningTasksAreRecoveredAsInterruptedOnLaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let first = PluginRegistry(storageURL: url)
        _ = first.beginTask(
            pluginID: "dev.example.tool",
            pluginName: "Tool",
            kind: .run,
            message: "Running"
        )

        let second = PluginRegistry(storageURL: url)
        second.load()

        #expect(second.tasks.first?.status == .failed)
        #expect(second.tasks.first?.finishedAt != nil)
        #expect(second.tasks.first?.message == "应用退出，任务已中断")
}

private func makeManifest() -> PluginManifest {
        PluginManifest(
            id: "dev.example.tool",
            name: "Tool",
            summary: "Summary",
            description: "Description",
            version: "1.0.0",
            category: .system,
            author: .init(name: "Example"),
            trustLevel: .community,
            permissions: [],
            compatibility: .init(
                minimumHostVersion: "0.1.0",
                minimumMacOSVersion: "13.0",
                architectures: ["arm64"]
            ),
            icon: "wrench"
        )
}
