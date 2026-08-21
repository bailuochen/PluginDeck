import Foundation

public struct PluginManifest: Codable, Hashable, Identifiable, Sendable {
    public struct EntryPoint: Codable, Hashable, Sendable {
        public let executable: String
        public let protocolVersion: Int

        public init(executable: String, protocolVersion: Int = 1) {
            self.executable = executable
            self.protocolVersion = protocolVersion
        }
    }

    public struct Distribution: Codable, Hashable, Sendable {
        public let downloadURL: URL?
        public let updateURL: URL?
        public let sha256: String?

        public init(downloadURL: URL? = nil, updateURL: URL? = nil, sha256: String? = nil) {
            self.downloadURL = downloadURL
            self.updateURL = updateURL
            self.sha256 = sha256
        }
    }

    public struct Author: Codable, Hashable, Sendable {
        public let name: String
        public let url: URL?

        public init(name: String, url: URL? = nil) {
            self.name = name
            self.url = url
        }
    }

    public struct Compatibility: Codable, Hashable, Sendable {
        public let minimumHostVersion: String
        public let minimumMacOSVersion: String
        public let architectures: [String]

        public init(
            minimumHostVersion: String,
            minimumMacOSVersion: String,
            architectures: [String]
        ) {
            self.minimumHostVersion = minimumHostVersion
            self.minimumMacOSVersion = minimumMacOSVersion
            self.architectures = architectures
        }
    }

    public enum Category: String, Codable, CaseIterable, Sendable {
        case runtimes
        case packageManagers = "package-managers"
        case sourceControl = "source-control"
        case containers
        case system

        public var displayName: String {
            switch self {
            case .runtimes: "运行时"
            case .packageManagers: "包管理"
            case .sourceControl: "版本控制"
            case .containers: "容器"
            case .system: "系统工具"
            }
        }
    }

    public enum Permission: String, Codable, CaseIterable, Sendable {
        case network
        case shell
        case fileRead = "file.read"
        case fileWrite = "file.write"
        case processRead = "process.read"

        public var displayName: String {
            switch self {
            case .network: "访问网络"
            case .shell: "执行 Shell 命令"
            case .fileRead: "读取文件"
            case .fileWrite: "写入文件"
            case .processRead: "读取进程信息"
            }
        }
    }

    public enum TrustLevel: String, Codable, Sendable {
        case official
        case verified
        case community

        public var displayName: String {
            switch self {
            case .official: "官方"
            case .verified: "已验证"
            case .community: "社区"
            }
        }
    }

    public enum ReleaseStatus: String, Codable, Sendable {
        case available
        case planned
    }

    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let summary: String
    public let description: String
    public let version: String
    public let category: Category
    public let author: Author
    public let trustLevel: TrustLevel
    public let releaseStatus: ReleaseStatus
    public let permissions: [Permission]
    public let networkDomains: [String]
    public let compatibility: Compatibility
    public let entryPoint: EntryPoint?
    public let distribution: Distribution
    public let repositoryURL: URL?
    public let icon: String
    public let featured: Bool
    public let capabilities: [String]

    public init(
        schemaVersion: Int = 1,
        id: String,
        name: String,
        summary: String,
        description: String,
        version: String,
        category: Category,
        author: Author,
        trustLevel: TrustLevel,
        releaseStatus: ReleaseStatus = .available,
        permissions: [Permission],
        networkDomains: [String] = [],
        compatibility: Compatibility,
        entryPoint: EntryPoint? = nil,
        distribution: Distribution = Distribution(),
        repositoryURL: URL? = nil,
        icon: String,
        featured: Bool = false,
        capabilities: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.summary = summary
        self.description = description
        self.version = version
        self.category = category
        self.author = author
        self.trustLevel = trustLevel
        self.releaseStatus = releaseStatus
        self.permissions = permissions
        self.networkDomains = networkDomains
        self.compatibility = compatibility
        self.entryPoint = entryPoint
        self.distribution = distribution
        self.repositoryURL = repositoryURL
        self.icon = icon
        self.featured = featured
        self.capabilities = capabilities
    }
}

public struct InstalledPlugin: Codable, Hashable, Identifiable, Sendable {
    public var id: String { manifest.id }
    public let manifest: PluginManifest
    public var isEnabled: Bool
    public let installedAt: Date
    public var updatedAt: Date

    public init(
        manifest: PluginManifest,
        isEnabled: Bool = true,
        installedAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.manifest = manifest
        self.isEnabled = isEnabled
        self.installedAt = installedAt
        self.updatedAt = updatedAt
    }
}

public struct PluginTask: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case install
        case uninstall
        case update
        case enable
        case disable
    }

    public enum Status: String, Codable, Sendable {
        case running
        case completed
        case failed
        case cancelled
    }

    public let id: UUID
    public let pluginID: String
    public let pluginName: String
    public let kind: Kind
    public var status: Status
    public let startedAt: Date
    public var finishedAt: Date?
    public var message: String

    public init(
        id: UUID = UUID(),
        pluginID: String,
        pluginName: String,
        kind: Kind,
        status: Status = .running,
        startedAt: Date = .now,
        finishedAt: Date? = nil,
        message: String = ""
    ) {
        self.id = id
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.kind = kind
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.message = message
    }
}
