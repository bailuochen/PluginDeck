import Foundation
import Testing
@testable import PluginDeckNVM

@Test func detectsNVMRCBeforeOtherSources() throws {
    let directory = try temporaryProject()
    defer { try? FileManager.default.removeItem(at: directory) }

    try "lts/*\n".write(
        to: directory.appendingPathComponent(".nvmrc"),
        atomically: true,
        encoding: .utf8
    )
    try "20\n".write(
        to: directory.appendingPathComponent(".node-version"),
        atomically: true,
        encoding: .utf8
    )

    #expect(
        ProjectVersionDetector.detect(in: directory.path)
            == DetectedProjectRequirement(source: .nvmrc, value: "lts/*")
    )
}

@Test func detectsNodeVersion() throws {
    let directory = try temporaryProject()
    defer { try? FileManager.default.removeItem(at: directory) }
    try "v18.20.8\n".write(
        to: directory.appendingPathComponent(".node-version"),
        atomically: true,
        encoding: .utf8
    )

    #expect(
        ProjectVersionDetector.detect(in: directory.path)
            == DetectedProjectRequirement(source: .nodeVersion, value: "v18.20.8")
    )
}

@Test func detectsPackageEngineAsAdvisorySource() throws {
    let directory = try temporaryProject()
    defer { try? FileManager.default.removeItem(at: directory) }
    try #"{"engines":{"node":">=18 <23"}}"#.write(
        to: directory.appendingPathComponent("package.json"),
        atomically: true,
        encoding: .utf8
    )

    #expect(
        ProjectVersionDetector.detect(in: directory.path)
            == DetectedProjectRequirement(source: .packageEngines, value: ">=18 <23")
    )
}

private func temporaryProject() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("NVMSwitcherTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
