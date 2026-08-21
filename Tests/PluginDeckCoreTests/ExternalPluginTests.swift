import Darwin
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

@Test func rejectsUnsafePluginPage() throws {
    let manifest = makeManifest(ui: .init(entryPoint: "../ui.html"))

    #expect(throws: PluginValidationError.unsafeUserInterface) {
        try PluginManifestValidator.validate(manifest, externalImport: true)
    }
}

@Test func actionParametersIncludePluginPayload() throws {
    let parameters = PluginActionParameters(
        pluginID: "dev.example.external",
        actionID: "terminate",
        dataDirectory: "/tmp/data",
        payload: ["port": "8080"]
    )
    let object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any]
    )
    let payload = try #require(object["payload"] as? [String: String])

    #expect(payload["port"] == "8080")
}

@Test func marketplaceManifestMatchesPackageWithoutDistribution() {
    let packaged = makeManifest()
    let catalog = PluginManifest(
        id: packaged.id,
        name: packaged.name,
        summary: packaged.summary,
        description: packaged.description,
        version: packaged.version,
        category: packaged.category,
        author: packaged.author,
        trustLevel: packaged.trustLevel,
        permissions: packaged.permissions,
        compatibility: packaged.compatibility,
        entryPoint: packaged.entryPoint,
        distribution: .init(
            downloadURL: URL(string: "https://example.com/plugin.zip"),
            sha256: String(repeating: "a", count: 64)
        ),
        icon: packaged.icon,
        actions: packaged.actions ?? []
    )

    #expect(packaged.describesSamePackage(as: catalog))
}

@Test func packagedMarketplaceManifestDoesNotRequireSelfReferentialDistribution() throws {
    let packaged = makeManifest()

    try PluginManifestValidator.validate(packaged, externalImport: true)
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

@Test func runnerDrainsLargePluginResponsesWithoutDeadlocking() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("PluginDeckLargeOutputTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let packageRoot = temporaryRoot
        .appendingPathComponent("Plugins/dev.example.external/1.0.0", isDirectory: true)
    let executable = packageRoot.appendingPathComponent("bin/tool")
    try FileManager.default.createDirectory(
        at: executable.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let script = #"""
    #!/bin/zsh
    /bin/cat >/dev/null
    detail=$(/usr/bin/head -c 200000 /dev/zero | /usr/bin/tr '\0' x)
    /usr/bin/printf '{"jsonrpc":"2.0","id":"00000000-0000-0000-0000-000000000000","result":{"message":"large","detail":"%s"}}' "$detail"
    """#
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path
    )
    let manifest = makeManifest()
    try JSONEncoder().encode(manifest).write(
        to: packageRoot.appendingPathComponent("plugin.json")
    )
    let installed = InstalledPlugin(
        manifest: manifest,
        packagePath: packageRoot.path,
        source: .local
    )
    let action = try #require(manifest.actions?.first)

    let result = try await ExternalPluginRunner().run(plugin: installed, action: action)

    #expect(result.message == "large")
    #expect(result.detail?.count == 200_000)
}

@Test func runnerTimeoutTerminatesDescendantProcesses() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("PluginDeckTimeoutTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let packageRoot = temporaryRoot
        .appendingPathComponent("Plugins/dev.example.external/1.0.0", isDirectory: true)
    let executable = packageRoot.appendingPathComponent("bin/tool")
    let childPIDFile = packageRoot.appendingPathComponent("child.pid")
    try FileManager.default.createDirectory(
        at: executable.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let script = """
    #!/bin/zsh
    /bin/cat >/dev/null
    /bin/sleep 30 &
    child_pid=$!
    echo "$child_pid" > "\(childPIDFile.path)"
    wait "$child_pid"
    """
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path
    )
    let manifest = makeManifest(timeoutSeconds: 5)
    try JSONEncoder().encode(manifest).write(
        to: packageRoot.appendingPathComponent("plugin.json")
    )
    let installed = InstalledPlugin(
        manifest: manifest,
        packagePath: packageRoot.path,
        source: .local
    )
    let action = try #require(manifest.actions?.first)

    await #expect(throws: ExternalPluginError.self) {
        try await ExternalPluginRunner().run(plugin: installed, action: action)
    }
    let childProcessID = try #require(
        Int32(String(contentsOf: childPIDFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
    )
    try await Task.sleep(for: .milliseconds(500))
    #expect(Darwin.kill(childProcessID, 0) == -1)
}

private func makeManifest(
    trustLevel: PluginManifest.TrustLevel = .community,
    entryPoint: PluginManifest.EntryPoint = .init(executable: "bin/tool"),
    ui: PluginManifest.UserInterface? = nil,
    timeoutSeconds: Int? = nil
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
        ui: ui,
        icon: "wrench",
        actions: [
            .init(
                id: "run",
                title: "Run",
                description: "Run action",
                icon: "play",
                method: "tool.run",
                timeoutSeconds: timeoutSeconds
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
