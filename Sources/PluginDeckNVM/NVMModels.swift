import Foundation

struct NodeVersion: Identifiable, Hashable, Comparable, Sendable {
    let rawValue: String

    var id: String { rawValue }
    var displayName: String { rawValue.hasPrefix("v") ? rawValue : "v\(rawValue)" }
    var executableVersion: String { displayName }
    var installCommand: String { "nvm install \(executableVersion)" }
    var majorVersion: Int { components.first ?? 0 }

    static func < (lhs: NodeVersion, rhs: NodeVersion) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }

    private var components: [Int] {
        displayName.dropFirst().split(separator: ".").map { Int($0) ?? 0 }
    }
}

struct NVMState: Sendable {
    var versions: [NodeVersion] = []
    var defaultVersion: NodeVersion?
    var nvmDirectory: String = ""
    var nvmScript: String = ""
}

struct RemoteNodeVersion: Identifiable, Hashable, Sendable {
    let version: NodeVersion
    let ltsName: String?
    let releaseDate: String?
    let npmVersion: String?
    let v8Version: String?
    let availableFiles: Set<String>
    let isSecurityRelease: Bool

    init(
        version: NodeVersion,
        ltsName: String?,
        releaseDate: String? = nil,
        npmVersion: String? = nil,
        v8Version: String? = nil,
        availableFiles: Set<String> = [],
        isSecurityRelease: Bool = false
    ) {
        self.version = version
        self.ltsName = ltsName
        self.releaseDate = releaseDate
        self.npmVersion = npmVersion
        self.v8Version = v8Version
        self.availableFiles = availableFiles
        self.isSecurityRelease = isSecurityRelease
    }

    var id: String { version.id }

    var macArchitectureSummary: String? {
        let supportsAppleSilicon = availableFiles.contains("osx-arm64-tar")
        let supportsIntel = availableFiles.contains("osx-x64-tar")

        switch (supportsAppleSilicon, supportsIntel) {
        case (true, true):
            return "Apple Silicon + Intel"
        case (true, false):
            return "Apple Silicon"
        case (false, true):
            return "仅 Intel"
        case (false, false):
            return nil
        }
    }
}

enum OperationStatus: Equatable, Sendable {
    case idle
    case running
    case succeeded
    case failed
    case cancelled
}

struct ProjectRecord: Identifiable, Hashable, Codable, Sendable {
    let path: String

    var id: String { path }
    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var nvmrcVersion: String? {
        let url = URL(fileURLWithPath: path).appendingPathComponent(".nvmrc")
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var directoryExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

enum ProjectVersionSource: String, Sendable {
    case nvmrc = ".nvmrc"
    case nodeVersion = ".node-version"
    case packageEngines = "package.json engines.node"
}

struct ProjectResolution: Hashable, Sendable {
    let source: ProjectVersionSource?
    let requestedVersion: String?
    let resolvedVersion: NodeVersion?
    let isInstalled: Bool

    var summary: String {
        guard let source, let requestedVersion else { return "未找到版本配置" }
        guard let resolvedVersion else {
            return source == .packageEngines
                ? "\(source.rawValue): \(requestedVersion)（版本范围）"
                : "无法解析 \(requestedVersion)"
        }
        if requestedVersion == resolvedVersion.displayName {
            return "\(source.rawValue): \(resolvedVersion.displayName)"
        }
        return "\(source.rawValue): \(requestedVersion) → \(resolvedVersion.displayName)"
    }
}

enum HealthLevel: Int, Sendable {
    case good
    case info
    case warning
    case error
}

struct HealthCheck: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let level: HealthLevel
    let fixCommand: String?
}

enum AppSection: String, CaseIterable, Identifiable {
    case installed
    case discover
    case projects
    case environment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .installed: "已安装"
        case .discover: "在线版本"
        case .projects: "项目"
        case .environment: "环境"
        }
    }

    var icon: String {
        switch self {
        case .installed: "shippingbox"
        case .discover: "arrow.down.circle"
        case .projects: "folder"
        case .environment: "wrench.and.screwdriver"
        }
    }
}

enum RemoteVersionFilter: String, CaseIterable, Identifiable {
    case lts
    case all

    var id: String { rawValue }
    var title: String { self == .lts ? "LTS" : "全部" }
}

enum NVMError: LocalizedError {
    case notInstalled
    case commandFailed(String)
    case invalidVersion
    case invalidProject
    case invalidNVMDirectory(String)
    case cancelled
    case downloadStalled

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "没有找到 NVM。请先安装 NVM，或确认 ~/.nvm/nvm.sh 存在。"
        case .commandFailed(let message):
            return message.isEmpty ? "NVM 命令执行失败。" : message
        case .invalidVersion:
            return "Node 版本格式无效。"
        case .invalidProject:
            return "项目目录不存在或无法写入。"
        case .invalidNVMDirectory(let path):
            return "所选目录中没有找到 nvm.sh：\(path)"
        case .cancelled:
            return "操作已取消。"
        case .downloadStalled:
            return "下载长时间没有进展，请检查网络或配置 Node.js 镜像后重试。"
        }
    }
}
