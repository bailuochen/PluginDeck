import Foundation
import Testing
@testable import PluginDeckCore

@Test func rejectsOfficialTrustForDirectImport() throws {
    let manifest = makeManifest(trustLevel: .official)

    #expect(throws: PluginValidationError.invalidTrustLevel) {
        try PluginManifestValidator.validate(manifest, externalImport: true)
    }
}

@Test func rejectsUnsafeEntryPoint() throws {
    let manifest = makeManifest(entryPoint: .init(executable: "../escape"))

    #expect(throws: PluginValidationError.unsafeEntryPoint) {
        try PluginManifestValidator.validate(manifest, externalImport: true)
    }
}

@Test func importsAndRunsExamplePlugin() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("PluginDeckExternalTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = repositoryRoot.appendingPathComponent("examples/hello-plugin", isDirectory: true)
    let installer = PluginPackageInstaller(
        pluginsDirectory: temporaryRoot.appendingPathComponent("Plugins", isDirectory: true)
    )

    let candidate = try await installer.inspectLocalDirectory(source)
    let artifact = try await installer.install(candidate)
    let installed = InstalledPlugin(
        manifest: artifact.manifest,
        packagePath: artifact.packageDirectory.path,
        source: artifact.source
    )
    let action = try #require(installed.manifest.actions?.first { $0.id == "hello" })
    let result = try await ExternalPluginRunner().run(plugin: installed, action: action)

    #expect(result.title == "Hello from a plugin")
    #expect(result.message.contains("JSON-RPC"))
    #expect(FileManager.default.fileExists(atPath: artifact.packageDirectory.path))
}

private func makeManifest(
    trustLevel: PluginManifest.TrustLevel = .community,
    entryPoint: PluginManifest.EntryPoint = .init(executable: "bin/tool")
) -> PluginManifest {
    PluginManifest(
        id: "dev.example.external",
        name: "External",
        summary: "Summary",
        description: "Description",
        version: "1.0.0",
        category: .system,
        author: .init(name: "Developer"),
        trustLevel: trustLevel,
        permissions: [.shell],
        compatibility: .init(
            minimumHostVersion: "0.3.0",
            minimumMacOSVersion: "13.0",
            architectures: [currentArchitecture]
        ),
        entryPoint: entryPoint,
        icon: "wrench",
        actions: [
            .init(
                id: "run",
                title: "Run",
                description: "Run action",
                icon: "play",
                method: "tool.run"
            )
        ]
    )
}

private var currentArchitecture: String {
    #if arch(arm64)
    "arm64"
    #else
    "x86_64"
    #endif
}
