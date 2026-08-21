import Foundation

actor NVMBridge {
    struct Snapshot: Sendable {
        let isInstalled: Bool
        let directory: String
        let currentVersion: String?
        let defaultVersion: String?
        let installedVersions: [String]
        let error: String?
    }

    struct CommandResult: Sendable {
        let output: String
        let error: String
        let exitCode: Int32
    }

    func snapshot() -> Snapshot {
        let directory = NSString(string: "~/.nvm").expandingTildeInPath
        let check = run("command -v nvm >/dev/null 2>&1")
        guard check.exitCode == 0 else {
            return Snapshot(
                isInstalled: false,
                directory: directory,
                currentVersion: nil,
                defaultVersion: nil,
                installedVersions: [],
                error: "没有检测到 NVM"
            )
        }

        let versionsResult = run(
            "for dir in \"$NVM_DIR\"/versions/node/*; do [ -d \"$dir\" ] && basename \"$dir\"; done"
        )
        let versions = versionsResult.output
            .split(separator: "\n")
            .map(String.init)
            .sorted(by: versionDescending)
        let current = cleanVersion(run("nvm current").output)
        let defaultVersion = cleanVersion(run("nvm version default").output)

        return Snapshot(
            isInstalled: true,
            directory: directory,
            currentVersion: current,
            defaultVersion: defaultVersion,
            installedVersions: versions,
            error: versionsResult.exitCode == 0 ? nil : versionsResult.error
        )
    }

    func install(version: String) -> CommandResult {
        guard isValid(version) else {
            return CommandResult(output: "", error: "版本格式无效", exitCode: 2)
        }
        return run("nvm install \(shellQuote(version))")
    }

    func uninstall(version: String) -> CommandResult {
        guard isValid(version) else {
            return CommandResult(output: "", error: "版本格式无效", exitCode: 2)
        }
        return run("nvm uninstall \(shellQuote(version))")
    }

    func setDefault(version: String) -> CommandResult {
        guard isValid(version) else {
            return CommandResult(output: "", error: "版本格式无效", exitCode: 2)
        }
        return run("nvm alias default \(shellQuote(version))")
    }

    private func run(_ command: String) -> CommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-lc",
            "export NVM_DIR=\"${NVM_DIR:-$HOME/.nvm}\"; "
                + "[ -s \"$NVM_DIR/nvm.sh\" ] && source \"$NVM_DIR/nvm.sh\"; "
                + command
        ]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(
                data: stdout.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let error = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            return CommandResult(
                output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                error: error.trimmingCharacters(in: .whitespacesAndNewlines),
                exitCode: process.terminationStatus
            )
        } catch {
            return CommandResult(output: "", error: error.localizedDescription, exitCode: -1)
        }
    }

    private func cleanVersion(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "none" || cleaned == "N/A" ? nil : cleaned
    }

    private func isValid(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: "^[A-Za-z0-9._*/-]+$", options: .regularExpression) != nil
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func versionDescending(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedDescending
    }
}
