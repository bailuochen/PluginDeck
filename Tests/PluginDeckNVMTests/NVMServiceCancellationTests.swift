import Darwin
import Foundation
import Testing
@testable import PluginDeckNVM

final class TestOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var output = ""

    func append(_ chunk: String) {
        lock.lock()
        output += chunk
        lock.unlock()
    }

    func childProcessID() -> Int32? {
        lock.lock()
        let snapshot = output
        lock.unlock()

        let prefix = "CHILD_PID="
        guard let line = snapshot.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return Int32(line.dropFirst(prefix.count))
    }

    func outputSnapshot() -> String {
        lock.lock()
        let snapshot = output
        lock.unlock()
        return snapshot
    }
}

@Test func cancellingInstallTerminatesDescendantProcesses() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let script = """
    nvm() {
      /bin/sleep 30 &
      child_pid=$!
      echo "CHILD_PID=$child_pid"
      wait "$child_pid"
    }
    """
    try script.write(
        to: directory.appendingPathComponent("nvm.sh"),
        atomically: true,
        encoding: .utf8
    )

    let collector = TestOutputCollector()
    let service = NVMService(customDirectory: directory.path)
    let installation = Task {
        try await service.install(NodeVersion(rawValue: "v1.2.3")) { chunk in
            collector.append(chunk)
        }
    }

    for _ in 0..<100 where collector.childProcessID() == nil {
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    let childProcessID = try #require(collector.childProcessID())

    await service.cancelActiveOperation()
    await #expect(throws: NVMError.self) {
        try await installation.value
    }
    #expect(Darwin.kill(childProcessID, 0) == -1)
}
