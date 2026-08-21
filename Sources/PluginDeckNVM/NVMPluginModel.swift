import AppKit
import Foundation
import SwiftUI
import PluginDeckCore

@MainActor
final class NVMPluginModel: ObservableObject {
    @Published private(set) var state = NVMState()
    @Published private(set) var remoteVersions: [RemoteNodeVersion] = []
    @Published private(set) var projects: [ProjectRecord] = []
    @Published private(set) var projectResolutions: [String: ProjectResolution] = [:]
    @Published private(set) var healthChecks: [HealthCheck] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingRemote = false
    @Published private(set) var isCheckingHealth = false
    @Published private(set) var changingVersion: NodeVersion?
    @Published private(set) var installingVersion: NodeVersion?
    @Published private(set) var uninstallingVersion: NodeVersion?
    @Published private(set) var resolvingProjects: Set<String> = []
    @Published private(set) var customNVMDirectory: String?
    @Published private(set) var operationTitle = ""
    @Published private(set) var operationLog = ""
    @Published private(set) var operationProgress: Double?
    @Published private(set) var operationStage = ""
    @Published private(set) var operationStatus: OperationStatus = .idle
    @Published private(set) var isOperationRunning = false
    @Published var isShowingOperationLog = false
    @Published var selectedSection: AppSection = .installed
    @Published var remoteFilter: RemoteVersionFilter = .lts
    @Published var remoteSearch = ""
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var fallbackCommand: String?

    private let service: NVMService
    private let registry: PluginRegistry
    private let projectsKey = "plugindeck.nvm.recentProjects"
    private let customDirectoryKey = "plugindeck.nvm.customDirectory"
    private var loadedRemoteFilter: RemoteVersionFilter?
    private var operationCommand = ""
    private var operationRawOutput = ""
    private var hostTaskID: UUID?

    init(registry: PluginRegistry) {
        self.registry = registry
        let defaults = UserDefaults.standard
        let savedDirectory = defaults.string(forKey: customDirectoryKey)
            ?? defaults.string(forKey: "customNVMDirectory")
        customNVMDirectory = savedDirectory
        service = NVMService(customDirectory: savedDirectory)

        if
            let data = defaults.data(forKey: projectsKey)
                ?? defaults.data(forKey: "recentProjects"),
            let saved = try? JSONDecoder().decode([ProjectRecord].self, from: data)
        {
            projects = saved
        }
    }

    var filteredRemoteVersions: [RemoteNodeVersion] {
        let query = remoteSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return remoteVersions }
        return remoteVersions.filter {
            $0.version.displayName.lowercased().contains(query)
                || ($0.ltsName?.lowercased().contains(query) ?? false)
                || ($0.releaseDate?.contains(query) ?? false)
                || ($0.npmVersion.map { "npm \($0)".lowercased().contains(query) } ?? false)
                || ($0.v8Version.map { "v8 \($0)".lowercased().contains(query) } ?? false)
        }
    }

    func isNewestPatch(_ release: RemoteNodeVersion) -> Bool {
        remoteVersions.first { $0.version.majorVersion == release.version.majorVersion } == release
    }

    func isNewestRemoteVersion(_ release: RemoteNodeVersion) -> Bool {
        remoteVersions.first == release
    }

    func isInstalled(_ version: NodeVersion) -> Bool {
        state.versions.contains(version)
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            state = try await service.loadState()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadRemoteVersions(force: Bool = false) async {
        let requestedFilter = remoteFilter
        guard force || loadedRemoteFilter != requestedFilter || remoteVersions.isEmpty else { return }
        isLoadingRemote = true
        defer { isLoadingRemote = false }

        do {
            let releases = try await service.loadRemoteVersions(ltsOnly: requestedFilter == .lts)
            guard remoteFilter == requestedFilter else { return }
            remoteVersions = releases
            loadedRemoteFilter = requestedFilter
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ version: NodeVersion) async {
        changingVersion = version
        defer { changingVersion = nil }
        let taskID = registry.beginTask(
            pluginID: "dev.plugindeck.nvm",
            pluginName: "NVM",
            kind: .update,
            message: "设置默认版本 \(version.displayName)"
        )

        do {
            try await service.setDefault(version)
            state.defaultVersion = version
            registry.finishTask(taskID, succeeded: true, message: "默认版本已更新")
            successMessage = "已将 \(version.displayName) 设为新终端默认版本"
            errorMessage = nil
        } catch {
            registry.finishTask(taskID, succeeded: false, message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func install(_ version: NodeVersion) async {
        guard installingVersion == nil else { return }
        installingVersion = version
        beginOperation("安装 \(version.displayName)", command: version.installCommand)
        defer {
            installingVersion = nil
            isOperationRunning = false
        }

        do {
            try await service.install(version, outputHandler: operationOutputHandler())
            state = try await service.loadState()
            appendOperationMessage("安装完成。")
            finishOperation(status: .succeeded, stage: "安装完成", progress: 1)
            successMessage = "\(version.displayName) 安装完成"
            errorMessage = nil
        } catch {
            finishOperation(with: error)
            errorMessage = error.localizedDescription
            await refreshAfterOperation()
        }
    }

    func uninstall(_ version: NodeVersion) async {
        guard uninstallingVersion == nil else { return }
        guard version != state.defaultVersion else {
            errorMessage = "请先选择另一个默认版本，再卸载 \(version.displayName)。"
            return
        }

        uninstallingVersion = version
        defer { uninstallingVersion = nil }
        let taskID = registry.beginTask(
            pluginID: "dev.plugindeck.nvm",
            pluginName: "NVM",
            kind: .uninstall,
            message: "卸载 Node.js \(version.displayName)"
        )

        do {
            try await service.uninstall(version)
            state = try await service.loadState()
            registry.finishTask(taskID, succeeded: true, message: "\(version.displayName) 已卸载")
            successMessage = "已卸载 \(version.displayName)"
            errorMessage = nil
            await refreshAllProjects()
        } catch {
            registry.finishTask(taskID, succeeded: false, message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func cancelCurrentOperation() async {
        guard isOperationRunning else { return }
        appendOperationMessage("正在取消…")
        operationStage = "正在取消"
        await service.cancelActiveOperation()
    }

    func openTerminal(using version: NodeVersion) async {
        do {
            let command = try await service.terminalCommand(using: version)
            try await service.openTerminal(command: command)
            fallbackCommand = nil
            errorMessage = nil
        } catch {
            fallbackCommand = try? await service.terminalCommand(using: version)
            errorMessage = "\(error.localizedDescription) 可以复制命令后手动运行。"
        }
    }

    func addProject() {
        let panel = NSOpenPanel()
        panel.title = "选择 Node.js 项目目录"
        panel.prompt = "添加项目"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        addProject(path: url.path)
    }

    func addProject(path: String) {
        let project = ProjectRecord(path: path)
        guard project.directoryExists else {
            errorMessage = NVMError.invalidProject.localizedDescription
            return
        }
        projects.removeAll { $0.path == project.path }
        projects.insert(project, at: 0)
        saveProjects()
        Task { await refreshProject(project) }
    }

    func removeProject(_ project: ProjectRecord) {
        projects.removeAll { $0.id == project.id }
        projectResolutions[project.id] = nil
        saveProjects()
    }

    func setProjectVersion(_ version: NodeVersion, for project: ProjectRecord) {
        guard project.directoryExists else {
            errorMessage = NVMError.invalidProject.localizedDescription
            return
        }

        let url = URL(fileURLWithPath: project.path).appendingPathComponent(".nvmrc")
        do {
            try "\(version.displayName)\n".write(to: url, atomically: true, encoding: .utf8)
            successMessage = "已更新 \(project.name) 的 .nvmrc"
            errorMessage = nil
            Task { await refreshProject(project) }
        } catch {
            errorMessage = "无法写入 .nvmrc：\(error.localizedDescription)"
        }
    }

    func refreshAllProjects() async {
        for project in projects {
            await refreshProject(project)
        }
    }

    func refreshProject(_ project: ProjectRecord) async {
        guard !resolvingProjects.contains(project.id) else { return }
        resolvingProjects.insert(project.id)
        defer { resolvingProjects.remove(project.id) }

        do {
            projectResolutions[project.id] = try await service.resolveProject(project)
        } catch {
            projectResolutions[project.id] = ProjectResolution(
                source: nil,
                requestedVersion: nil,
                resolvedVersion: nil,
                isInstalled: false
            )
            errorMessage = error.localizedDescription
        }
    }

    func prepareProject(_ project: ProjectRecord, installIfNeeded: Bool) async {
        await refreshProject(project)
        guard let resolution = projectResolutions[project.id] else { return }
        guard let version = resolution.resolvedVersion else {
            errorMessage = resolution.source == .packageEngines
                ? "package.json 中是版本范围，请先选择一个具体版本写入 .nvmrc。"
                : "无法解析项目需要的 Node.js 版本。"
            return
        }

        if !resolution.isInstalled {
            guard installIfNeeded else { return }
            installingVersion = version
            beginOperation(
                "为 \(project.name) 安装 \(version.displayName)",
                command: version.installCommand
            )
            defer {
                installingVersion = nil
                isOperationRunning = false
            }
            do {
                try await service.install(version, outputHandler: operationOutputHandler())
                state = try await service.loadState()
                appendOperationMessage("安装完成，正在打开项目终端。")
                finishOperation(status: .succeeded, stage: "安装完成", progress: 1)
                await refreshProject(project)
            } catch {
                finishOperation(with: error)
                errorMessage = error.localizedDescription
                await refreshAfterOperation()
                return
            }
        }

        do {
            let command = try await service.terminalCommand(in: project, version: version)
            try await service.openTerminal(command: command)
            fallbackCommand = nil
            successMessage = "已用 \(version.displayName) 打开 \(project.name)"
            errorMessage = nil
        } catch {
            fallbackCommand = try? await service.terminalCommand(in: project, version: version)
            errorMessage = "\(error.localizedDescription) 可以复制命令后手动运行。"
        }
    }

    func loadHealthChecks() async {
        isCheckingHealth = true
        healthChecks = await service.healthChecks()
        isCheckingHealth = false
    }

    func chooseCustomNVMDirectory() async {
        let panel = NSOpenPanel()
        panel.title = "选择包含 nvm.sh 的目录"
        panel.prompt = "使用此目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = customNVMDirectory.map { URL(fileURLWithPath: $0) }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        customNVMDirectory = url.path
        UserDefaults.standard.set(url.path, forKey: customDirectoryKey)
        await service.setCustomDirectory(url.path)
        await refresh()
        await loadHealthChecks()
    }

    func clearCustomNVMDirectory() async {
        customNVMDirectory = nil
        UserDefaults.standard.removeObject(forKey: customDirectoryKey)
        await service.setCustomDirectory(nil)
        await refresh()
        await loadHealthChecks()
    }

    func revealNVMDirectory() {
        guard !state.nvmDirectory.isEmpty else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: state.nvmDirectory)
    }

    func revealProject(_ project: ProjectRecord) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
    }

    func copyShellConfiguration() {
        guard !state.nvmScript.isEmpty else { return }
        let command = "export NVM_DIR=\"\(state.nvmDirectory)\"\n[ -s \"\(state.nvmScript)\" ] && \\. \"\(state.nvmScript)\""
        copyToPasteboard(command, message: "Shell 初始化配置已复制")
    }

    func copyFallbackCommand() {
        guard let fallbackCommand else { return }
        copyToPasteboard(fallbackCommand, message: "终端命令已复制")
    }

    func copyHealthFix(_ check: HealthCheck) {
        guard let command = check.fixCommand else { return }
        copyToPasteboard(command, message: "修复命令已复制")
    }

    func copyOperationLog() {
        guard !operationLog.isEmpty else { return }
        copyToPasteboard(operationLog, message: "任务日志已复制")
    }

    func dismissError() {
        errorMessage = nil
        fallbackCommand = nil
    }

    private func beginOperation(_ title: String, command: String) {
        operationTitle = title
        operationCommand = command
        operationRawOutput = ""
        operationLog = "$ \(command)\n\n"
        operationProgress = nil
        operationStage = "正在查询可用版本"
        operationStatus = .running
        isOperationRunning = true
        isShowingOperationLog = true
        hostTaskID = registry.beginTask(
            pluginID: "dev.plugindeck.nvm",
            pluginName: "NVM",
            kind: .install,
            message: title
        )
    }

    private func operationOutputHandler() -> NVMService.OutputHandler {
        { [weak self] chunk in
            Task { @MainActor [weak self] in
                self?.appendOperationOutput(chunk)
            }
        }
    }

    private func appendOperationOutput(_ chunk: String) {
        operationRawOutput += chunk
        let snapshot = NVMInstallOutputParser.parse(operationRawOutput)
        operationProgress = snapshot.progress
        operationStage = snapshot.stage
        if let hostTaskID {
            registry.updateTask(hostTaskID, message: snapshot.stage)
        }
        operationLog = "$ \(operationCommand)"
        if !snapshot.cleanedOutput.isEmpty {
            operationLog += "\n\n\(snapshot.cleanedOutput)"
        }
    }

    private func appendOperationMessage(_ message: String) {
        if !operationRawOutput.hasSuffix("\n") && !operationRawOutput.isEmpty {
            operationRawOutput += "\n"
        }
        operationRawOutput += "\(message)\n"
        appendOperationOutput("")
    }

    private func finishOperation(
        status: OperationStatus,
        stage: String,
        progress: Double? = nil
    ) {
        operationStatus = status
        operationStage = stage
        operationProgress = progress ?? operationProgress
        if let hostTaskID {
            registry.finishTask(
                hostTaskID,
                status: hostTaskStatus(for: status),
                message: stage
            )
            self.hostTaskID = nil
        }
    }

    private func hostTaskStatus(for status: OperationStatus) -> PluginTask.Status {
        switch status {
        case .succeeded: .completed
        case .cancelled: .cancelled
        case .idle, .running, .failed: .failed
        }
    }

    private func finishOperation(with error: Error) {
        if operationRawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendOperationMessage(error.localizedDescription)
        }

        if let nvmError = error as? NVMError, case .cancelled = nvmError {
            finishOperation(status: .cancelled, stage: "安装已取消")
        } else {
            finishOperation(status: .failed, stage: "安装失败")
        }
    }

    private func refreshAfterOperation() async {
        if let updated = try? await service.loadState() {
            state = updated
        }
        await refreshAllProjects()
    }

    private func copyToPasteboard(_ value: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        successMessage = message
    }

    private func saveProjects() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: projectsKey)
    }
}
