import AppKit
import Darwin
import Foundation

private final class ProcessOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(decoding: snapshot, as: UTF8.self)
    }
}

private final class ProcessActivityTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var lastActivity = Date()
    private var timedOut = false

    func markActivity() {
        lock.lock()
        lastActivity = Date()
        lock.unlock()
    }

    func markTimedOutIfInactive(for interval: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !timedOut, Date().timeIntervalSince(lastActivity) >= interval else {
            return false
        }
        timedOut = true
        return true
    }

    var didTimeOut: Bool {
        lock.lock()
        let snapshot = timedOut
        lock.unlock()
        return snapshot
    }
}

actor NVMService {
    typealias OutputHandler = @Sendable (String) -> Void

    private let homeDirectory: String
    private let installInactivityTimeout: TimeInterval
    private var customDirectory: String?
    private var activeProcess: Process?
    private var cancellationRequested = false

    init(
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        customDirectory: String? = nil,
        installInactivityTimeout: TimeInterval = 30
    ) {
        self.homeDirectory = homeDirectory
        self.customDirectory = customDirectory
        self.installInactivityTimeout = installInactivityTimeout
    }

    func setCustomDirectory(_ path: String?) {
        customDirectory = path
    }

    func loadState() async throws -> NVMState {
        let location = try findNVM()
        async let listOutput = runNVM("nvm ls --no-colors", location: location)
        async let defaultOutput = runNVM("nvm alias default --no-colors", location: location)

        let (list, defaultAlias) = try await (listOutput, defaultOutput)
        return NVMState(
            versions: NVMOutputParser.installedVersions(from: list),
            defaultVersion: NVMOutputParser.defaultVersion(from: defaultAlias),
            nvmDirectory: location.directory,
            nvmScript: location.script
        )
    }

    func loadRemoteVersions(ltsOnly: Bool) async throws -> [RemoteNodeVersion] {
        let location = try findNVM()
        let indexCommand = """
        primary_index="$(nvm_get_mirror node std)/index.tab"
        nvm_download -L -sS --connect-timeout 5 --max-time 15 "$primary_index" -o - || \
        nvm_download -L -sS --connect-timeout 5 --max-time 15 "https://npmmirror.com/mirrors/node/index.tab" -o -
        """
        let output = try await runNVM(
            indexCommand,
            location: location
        )
        let releases = NVMOutputParser.remoteVersions(fromIndexTable: output)
        guard !releases.isEmpty else {
            throw NVMError.commandFailed("没有从 Node.js 版本索引中解析到可用版本。")
        }
        return ltsOnly ? releases.filter { $0.ltsName != nil } : releases
    }

    func install(_ version: NodeVersion, outputHandler: OutputHandler? = nil) async throws {
        guard isValid(version) else { throw NVMError.invalidVersion }
        let location = try findNVM()
        let maximumAttempts = 3
        var attempt = 1

        while true {
            do {
                _ = try await runNVM(
                    version.installCommand,
                    location: location,
                    tracksActivity: true,
                    inactivityTimeout: installInactivityTimeout,
                    outputHandler: outputHandler
                )
                return
            } catch {
                guard attempt < maximumAttempts, let message = retryMessage(after: error) else {
                    throw error
                }
                attempt += 1
                outputHandler?("\n\(message)（\(attempt)/\(maximumAttempts)）\n")
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    func uninstall(_ version: NodeVersion) async throws {
        guard isValid(version) else { throw NVMError.invalidVersion }
        let location = try findNVM()
        _ = try await runNVM("nvm uninstall \(version.executableVersion)", location: location)
    }

    func cancelActiveOperation() async {
        guard let activeProcess, activeProcess.isRunning else { return }
        cancellationRequested = true
        let processIDs = Self.descendantProcessIDs(of: activeProcess.processIdentifier)
            + [activeProcess.processIdentifier]

        for processID in processIDs {
            Darwin.kill(processID, SIGTERM)
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        for processID in processIDs where Darwin.kill(processID, 0) == 0 {
            Darwin.kill(processID, SIGKILL)
        }
    }

    func setDefault(_ version: NodeVersion) async throws {
        guard isValid(version) else { throw NVMError.invalidVersion }
        let location = try findNVM()
        _ = try await runNVM(
            "nvm alias default \(version.executableVersion)",
            location: location
        )
    }

    func resolveProject(_ project: ProjectRecord) async throws -> ProjectResolution {
        guard project.directoryExists else { throw NVMError.invalidProject }
        guard let requirement = ProjectVersionDetector.detect(in: project.path) else {
            return ProjectResolution(
                source: nil,
                requestedVersion: nil,
                resolvedVersion: nil,
                isInstalled: false
            )
        }

        if requirement.source == .packageEngines {
            return ProjectResolution(
                source: requirement.source,
                requestedVersion: requirement.value,
                resolvedVersion: nil,
                isInstalled: false
            )
        }

        let location = try findNVM()
        let requested = shellQuote(requirement.value)
        let installedOutput = try await runNVM("nvm version \(requested)", location: location)
        if let installed = parsedVersion(from: installedOutput) {
            return ProjectResolution(
                source: requirement.source,
                requestedVersion: requirement.value,
                resolvedVersion: installed,
                isInstalled: true
            )
        }

        let remoteOutput = try await runNVM("nvm version-remote \(requested)", location: location)
        return ProjectResolution(
            source: requirement.source,
            requestedVersion: requirement.value,
            resolvedVersion: parsedVersion(from: remoteOutput),
            isInstalled: false
        )
    }

    func terminalCommand(using version: NodeVersion) throws -> String {
        guard isValid(version) else { throw NVMError.invalidVersion }
        let location = try findNVM()
        return terminalPrefix(location) + " && nvm use \(shellQuote(version.executableVersion))"
    }

    func terminalCommand(in project: ProjectRecord, version: NodeVersion?) throws -> String {
        guard project.directoryExists else { throw NVMError.invalidProject }
        let location = try findNVM()
        let useCommand = version.map { "nvm use \(shellQuote($0.executableVersion))" } ?? "nvm use"
        return "cd \(shellQuote(project.path)) && \(terminalPrefix(location)) && \(useCommand)"
    }

    func openTerminal(command: String) async throws {
        let appleScript = """
        tell application "Terminal"
            activate
            do script \(appleScriptLiteral(command))
        end tell
        """

        try await MainActor.run {
            var error: NSDictionary?
            guard NSAppleScript(source: appleScript)?.executeAndReturnError(&error) != nil else {
                let message = error?[NSAppleScript.errorMessage] as? String ?? "无法打开终端。"
                throw NVMError.commandFailed(message)
            }
        }
    }

    func healthChecks() async -> [HealthCheck] {
        var checks: [HealthCheck] = []
        let location: NVMLocation
        do {
            location = try findNVM()
            checks.append(HealthCheck(
                id: "nvm-location",
                title: "NVM 安装",
                detail: location.script,
                level: .good,
                fixCommand: nil
            ))
        } catch {
            return [HealthCheck(
                id: "nvm-location",
                title: "NVM 安装",
                detail: error.localizedDescription,
                level: .error,
                fixCommand: nil
            )]
        }

        let fileManager = FileManager.default
        checks.append(HealthCheck(
            id: "nvm-script",
            title: "加载脚本",
            detail: fileManager.isReadableFile(atPath: location.script) ? "文件可读" : "文件不可读",
            level: fileManager.isReadableFile(atPath: location.script) ? .good : .error,
            fixCommand: nil
        ))
        checks.append(HealthCheck(
            id: "nvm-writable",
            title: "数据目录",
            detail: fileManager.isWritableFile(atPath: location.directory) ? "目录可写" : "目录不可写",
            level: fileManager.isWritableFile(atPath: location.directory) ? .good : .warning,
            fixCommand: nil
        ))

        let defaultOutput = (try? await runNVM("nvm alias default --no-colors", location: location)) ?? ""
        let hasDefault = NVMOutputParser.defaultVersion(from: defaultOutput) != nil
        checks.append(HealthCheck(
            id: "default-alias",
            title: "默认版本",
            detail: hasDefault ? "default alias 已设置" : "尚未设置 default alias",
            level: hasDefault ? .good : .warning,
            fixCommand: nil
        ))

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let profileName = shell.hasSuffix("bash") ? ".bashrc" : ".zshrc"
        let profilePath = "\(homeDirectory)/\(profileName)"
        let profile = (try? String(contentsOfFile: profilePath, encoding: .utf8)) ?? ""
        let isConfigured = profile.contains("nvm.sh") || profile.contains("NVM_DIR")
        let shellCommand = "export NVM_DIR=\"\(location.directory)\"\n[ -s \"\(location.script)\" ] && \\. \"\(location.script)\""
        checks.append(HealthCheck(
            id: "shell-profile",
            title: "Shell 配置",
            detail: isConfigured ? "\(profileName) 已包含 NVM 配置" : "\(profileName) 中未检测到 NVM 配置",
            level: isConfigured ? .good : .warning,
            fixCommand: isConfigured ? nil : shellCommand
        ))
        checks.append(HealthCheck(
            id: "terminal-automation",
            title: "Terminal 自动化",
            detail: "首次打开终端时由 macOS 请求授权；拒绝后仍可复制命令",
            level: .info,
            fixCommand: nil
        ))
        return checks
    }

    private struct NVMLocation: Sendable {
        let directory: String
        let script: String
    }

    private func findNVM() throws -> NVMLocation {
        let environmentDirectory = ProcessInfo.processInfo.environment["NVM_DIR"]
        if let customDirectory {
            let customLocation = NVMLocation(
                directory: customDirectory,
                script: "\(customDirectory)/nvm.sh"
            )
            guard FileManager.default.fileExists(atPath: customLocation.script) else {
                throw NVMError.invalidNVMDirectory(customDirectory)
            }
            return customLocation
        }
        let dataDirectory = customDirectory ?? environmentDirectory ?? "\(homeDirectory)/.nvm"
        let candidates = [
            environmentDirectory.map { NVMLocation(directory: $0, script: "\($0)/nvm.sh") },
            NVMLocation(
                directory: "\(homeDirectory)/.nvm",
                script: "\(homeDirectory)/.nvm/nvm.sh"
            ),
            NVMLocation(directory: dataDirectory, script: "/opt/homebrew/opt/nvm/nvm.sh"),
            NVMLocation(directory: dataDirectory, script: "/usr/local/opt/nvm/nvm.sh")
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.script) {
            return candidate
        }
        throw NVMError.notInstalled
    }

    private func runNVM(
        _ command: String,
        location: NVMLocation,
        tracksActivity: Bool = false,
        inactivityTimeout: TimeInterval? = nil,
        outputHandler: OutputHandler? = nil
    ) async throws -> String {
        let task = Process()
        let output = Pipe()
        let collector = ProcessOutputCollector()
        let activityTracker = ProcessActivityTracker()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = [
            "-c",
            "export NVM_DIR=\(shellQuote(location.directory)); export NVM_NO_COLORS=1; source \(shellQuote(location.script)); \(command)"
        ]
        task.standardOutput = output
        task.standardError = output

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            collector.append(chunk)
            activityTracker.markActivity()
            outputHandler?(String(decoding: chunk, as: UTF8.self))
        }

        let timeoutMonitor: DispatchSourceTimer? = inactivityTimeout.map { timeout in
            let monitor = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            monitor.schedule(deadline: .now() + timeout, repeating: 1)
            monitor.setEventHandler {
                guard task.isRunning, activityTracker.markTimedOutIfInactive(for: timeout) else {
                    return
                }
                Self.terminateProcessTree(rootProcessID: task.processIdentifier)
            }
            monitor.resume()
            return monitor
        }

        if tracksActivity {
            activeProcess = task
            cancellationRequested = false
        }
        defer {
            timeoutMonitor?.cancel()
            output.fileHandleForReading.readabilityHandler = nil
            if tracksActivity {
                activeProcess = nil
            }
        }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        let remaining = output.fileHandleForReading.readDataToEndOfFile()
        if !remaining.isEmpty {
            collector.append(remaining)
            outputHandler?(String(decoding: remaining, as: UTF8.self))
        }
        let result = collector.string()

        if tracksActivity && cancellationRequested {
            cancellationRequested = false
            throw NVMError.cancelled
        }
        if activityTracker.didTimeOut {
            throw NVMError.downloadStalled
        }
        guard status == 0 else {
            throw NVMError.commandFailed(result.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }

    private func parsedVersion(from output: String) -> NodeVersion? {
        let pattern = #"\bv\d+\.\d+\.\d+\b"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
            let range = Range(match.range, in: output)
        else { return nil }
        return NodeVersion(rawValue: String(output[range]))
    }

    private func isValid(_ version: NodeVersion) -> Bool {
        version.executableVersion.range(
            of: #"^v\d+\.\d+\.\d+$"#,
            options: .regularExpression
        ) != nil
    }

    private func retryMessage(after error: Error) -> String? {
        if let nvmError = error as? NVMError, case .downloadStalled = nvmError {
            return "下载长时间没有进展，正在断点续传"
        }
        guard case NVMError.commandFailed(let message) = error else { return nil }
        let normalized = message.lowercased()
        guard normalized.contains("not found"), normalized.contains("nvm ls-remote") else {
            return nil
        }
        return "NVM 远程查询暂时失败，正在重试"
    }

    private func terminalPrefix(_ location: NVMLocation) -> String {
        "export NVM_DIR=\(shellQuote(location.directory)); source \(shellQuote(location.script))"
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
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

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int32($0) }
    }
}
