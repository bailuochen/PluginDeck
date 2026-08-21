import Darwin
import Foundation

public struct PluginActionResult: Codable, Hashable, Sendable {
    public let title: String?
    public let message: String
    public let detail: String?

    public init(title: String? = nil, message: String, detail: String? = nil) {
        self.title = title
        self.message = message
        self.detail = detail
    }
}

public struct PluginActionParameters: Codable, Sendable {
    public let pluginID: String
    public let actionID: String
    public let dataDirectory: String
    public let payload: [String: String]

    public init(
        pluginID: String,
        actionID: String,
        dataDirectory: String,
        payload: [String: String] = [:]
    ) {
        self.pluginID = pluginID
        self.actionID = actionID
        self.dataDirectory = dataDirectory
        self.payload = payload
    }
}

public enum ExternalPluginError: LocalizedError {
    case packageMissing
    case actionMissing
    case launchFailed(String)
    case timedOut(Int)
    case invalidResponse(String)
    case remote(String)

    public var errorDescription: String? {
        switch self {
        case .packageMissing: "插件包或可执行入口不存在"
        case .actionMissing: "插件动作不存在"
        case .launchFailed(let message): "插件无法启动：\(message)"
        case .timedOut(let seconds): "插件运行超过 \(seconds) 秒，已终止"
        case .invalidResponse(let message): "插件返回了无效 JSON-RPC 响应：\(message)"
        case .remote(let message): "插件执行失败：\(message)"
        }
    }
}

public actor ExternalPluginRunner {
    public init() {}

    public func run(
        plugin: InstalledPlugin,
        action: PluginManifest.Action,
        payload: [String: String] = [:]
    ) async throws -> PluginActionResult {
        guard let packagePath = plugin.packagePath,
              let entryPoint = plugin.manifest.entryPoint,
              plugin.manifest.actions?.contains(action) == true else {
            throw ExternalPluginError.packageMissing
        }
        let packageURL = URL(fileURLWithPath: packagePath, isDirectory: true)
        try PluginManifestValidator.validate(
            plugin.manifest,
            packageDirectory: packageURL,
            externalImport: true
        )
        let executable = packageURL.appendingPathComponent(entryPoint.executable)
        let dataDirectory = packageURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PluginData", isDirectory: true)
            .appendingPathComponent(plugin.id, isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

        let request = JSONRPCRequest(
            method: action.method,
            params: PluginActionParameters(
                pluginID: plugin.id,
                actionID: action.id,
                dataDirectory: dataDirectory.path,
                payload: payload
            )
        )
        let requestData = try JSONEncoder().encode(request) + Data([0x0A])
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errorOutput = Pipe()
        let outputCollector = ProcessDataCollector()
        let errorCollector = ProcessDataCollector()
        process.executableURL = executable
        process.currentDirectoryURL = packageURL
        process.arguments = []
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
            "HOME": NSHomeDirectory(),
            "TMPDIR": NSTemporaryDirectory(),
            "LANG": "en_US.UTF-8",
            "PLUGINDECK_PLUGIN_ID": plugin.id,
            "PLUGINDECK_DATA_DIR": dataDirectory.path
        ]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { outputCollector.append(data) }
        }
        errorOutput.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errorCollector.append(data) }
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            errorOutput.fileHandleForReading.readabilityHandler = nil
        }

        let timeout = TimeoutState()
        let timeoutSeconds = action.timeoutSeconds ?? 60
        let processBox = ProcessBox(process)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + .seconds(timeoutSeconds))
        timer.setEventHandler {
            guard processBox.process.isRunning else { return }
            timeout.markTimedOut()
            Self.terminateProcessTree(rootProcessID: processBox.process.processIdentifier)
        }
        timer.resume()
        defer { timer.cancel() }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { terminated in
                continuation.resume(returning: terminated.terminationStatus)
            }
            do {
                try process.run()
                input.fileHandleForWriting.write(requestData)
                try? input.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: ExternalPluginError.launchFailed(error.localizedDescription))
            }
        }
        output.fileHandleForReading.readabilityHandler = nil
        errorOutput.fileHandleForReading.readabilityHandler = nil
        outputCollector.append(output.fileHandleForReading.readDataToEndOfFile())
        errorCollector.append(errorOutput.fileHandleForReading.readDataToEndOfFile())
        let responseData = outputCollector.data
        let errorData = errorCollector.data
        if timeout.didTimeOut { throw ExternalPluginError.timedOut(timeoutSeconds) }

        let stderr = String(decoding: errorData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == 0 else {
            throw ExternalPluginError.remote(stderr.isEmpty ? "退出码 \(status)" : stderr)
        }
        do {
            let response = try JSONDecoder().decode(
                JSONRPCResponse<PluginActionResult>.self,
                from: responseData
            )
            if let error = response.error {
                throw ExternalPluginError.remote(error.message)
            }
            guard let result = response.result else {
                throw ExternalPluginError.invalidResponse("缺少 result")
            }
            return result
        } catch let error as ExternalPluginError {
            throw error
        } catch {
            let raw = String(decoding: responseData, as: UTF8.self)
            throw ExternalPluginError.invalidResponse(raw.isEmpty ? error.localizedDescription : raw)
        }
    }

    private nonisolated static func terminateProcessTree(rootProcessID: Int32) {
        let processIDs = descendantProcessIDs(of: rootProcessID) + [rootProcessID]
        for processID in processIDs {
            Darwin.kill(processID, SIGTERM)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) {
            for processID in processIDs where Darwin.kill(processID, 0) == 0 {
                Darwin.kill(processID, SIGKILL)
            }
        }
    }

    private nonisolated static func descendantProcessIDs(of processID: Int32) -> [Int32] {
        childProcessIDs(of: processID).flatMap { childID in
            descendantProcessIDs(of: childID) + [childID]
        }
    }

    private nonisolated static func childProcessIDs(of processID: Int32) -> [Int32] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", String(processID)]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int32($0) }
    }
}

private final class ProcessDataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

private final class TimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func markTimedOut() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
