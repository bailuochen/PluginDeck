import Foundation
import Testing
@testable import PluginDeckNVM

@Test func retriesTransientNVMVersionLookupFailureOnce() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let script = """
    nvm() {
      attempts_file="$NVM_DIR/install-attempts"
      attempts=0
      if [ -f "$attempts_file" ]; then
        attempts=$(cat "$attempts_file")
      fi
      attempts=$((attempts + 1))
      echo "$attempts" > "$attempts_file"

      if [ "$attempts" -eq 1 ]; then
        echo "Version '$2' not found - try \\`nvm ls-remote\\` to browse available versions."
        return 3
      fi
      echo "Now using node $2"
    }
    """
    try script.write(
        to: directory.appendingPathComponent("nvm.sh"),
        atomically: true,
        encoding: .utf8
    )

    let collector = TestOutputCollector()
    let service = NVMService(customDirectory: directory.path)
    try await service.install(NodeVersion(rawValue: "v24.19.0")) { chunk in
        collector.append(chunk)
    }

    let attempts = try String(
        contentsOf: directory.appendingPathComponent("install-attempts"),
        encoding: .utf8
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(attempts == "2")
    #expect(collector.outputSnapshot().contains("正在重试"))
    #expect(collector.outputSnapshot().contains("Now using node v24.19.0"))
}

@Test func resumesInstallAfterDownloadStopsProducingOutput() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let script = """
    nvm() {
      attempts_file="$NVM_DIR/install-attempts"
      attempts=0
      if [ -f "$attempts_file" ]; then
        attempts=$(cat "$attempts_file")
      fi
      attempts=$((attempts + 1))
      echo "$attempts" > "$attempts_file"

      if [ "$attempts" -eq 1 ]; then
        echo "Downloading https://nodejs.org/node.tar.xz..."
        echo "######## 11.0%"
        /bin/sleep 30
      else
        echo "Now using node $2"
      fi
    }
    """
    try script.write(
        to: directory.appendingPathComponent("nvm.sh"),
        atomically: true,
        encoding: .utf8
    )

    let collector = TestOutputCollector()
    let service = NVMService(
        customDirectory: directory.path,
        installInactivityTimeout: 0.2
    )
    try await service.install(NodeVersion(rawValue: "v14.17.0")) { chunk in
        collector.append(chunk)
    }

    let attempts = try String(
        contentsOf: directory.appendingPathComponent("install-attempts"),
        encoding: .utf8
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(attempts == "2")
    #expect(collector.outputSnapshot().contains("正在断点续传"))
    #expect(collector.outputSnapshot().contains("Now using node v14.17.0"))
}
