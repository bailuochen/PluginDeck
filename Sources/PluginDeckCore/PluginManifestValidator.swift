import Foundation

public enum PluginValidationError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidIdentifier
    case invalidVersion
    case incompatibleHost(String)
    case incompatibleMacOS(String)
    case incompatibleArchitecture
    case missingEntryPoint
    case unsafeEntryPoint
    case entryPointNotExecutable
    case actionsRequired
    case invalidAction(String)
    case duplicateAction(String)
    case unsafeUserInterface
    case userInterfaceNotFound
    case invalidTrustLevel
    case invalidDistribution(String)
    case manifestNotFound

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): "不支持插件清单版本 \(version)"
        case .invalidIdentifier: "插件 ID 必须使用小写反向域名格式"
        case .invalidVersion: "插件版本必须使用 MAJOR.MINOR.PATCH 格式"
        case .incompatibleHost(let version): "插件需要 PluginDeck \(version) 或更高版本"
        case .incompatibleMacOS(let version): "插件需要 macOS \(version) 或更高版本"
        case .incompatibleArchitecture: "插件不支持当前 Mac 架构"
        case .missingEntryPoint: "外部插件必须声明可执行入口"
        case .unsafeEntryPoint: "插件入口必须是包内的安全相对路径"
        case .entryPointNotExecutable: "插件入口不存在、是符号链接或不可执行"
        case .actionsRequired: "外部插件至少需要声明一个动作"
        case .invalidAction(let id): "插件动作格式无效：\(id)"
        case .duplicateAction(let id): "插件动作 ID 重复：\(id)"
        case .unsafeUserInterface: "插件页面必须是包内的安全相对路径"
        case .userInterfaceNotFound: "插件页面不存在、是符号链接或不是 HTML 文件"
        case .invalidTrustLevel: "自行导入的插件必须标记为 community"
        case .invalidDistribution(let reason): "插件发布信息无效：\(reason)"
        case .manifestNotFound: "所选目录中没有找到 plugin.json"
        }
    }
}

public enum PluginManifestValidator {
    public static let hostVersion = "0.4.0"

    public static func decodeManifest(in directory: URL) throws -> PluginManifest {
        let url = directory.appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PluginValidationError.manifestNotFound
        }
        let decoder = JSONDecoder()
        return try decoder.decode(PluginManifest.self, from: Data(contentsOf: url))
    }

    public static func validate(
        _ manifest: PluginManifest,
        packageDirectory: URL? = nil,
        externalImport: Bool = false,
        marketplace: Bool = false
    ) throws {
        guard manifest.schemaVersion == 1 else {
            throw PluginValidationError.unsupportedSchema(manifest.schemaVersion)
        }
        guard manifest.id.range(
            of: #"^[a-z0-9]+(?:[.-][a-z0-9-]+)+$"#,
            options: .regularExpression
        ) != nil else {
            throw PluginValidationError.invalidIdentifier
        }
        guard isSemanticVersion(manifest.version) else {
            throw PluginValidationError.invalidVersion
        }
        guard isVersionNumber(manifest.compatibility.minimumHostVersion),
              isVersionNumber(manifest.compatibility.minimumMacOSVersion) else {
            throw PluginValidationError.invalidVersion
        }
        guard compareVersions(hostVersion, manifest.compatibility.minimumHostVersion) >= 0 else {
            throw PluginValidationError.incompatibleHost(manifest.compatibility.minimumHostVersion)
        }
        let currentMacOS = ProcessInfo.processInfo.operatingSystemVersion
        let currentMacOSString = "\(currentMacOS.majorVersion).\(currentMacOS.minorVersion).\(currentMacOS.patchVersion)"
        guard compareVersions(currentMacOSString, manifest.compatibility.minimumMacOSVersion) >= 0 else {
            throw PluginValidationError.incompatibleMacOS(manifest.compatibility.minimumMacOSVersion)
        }
        guard manifest.compatibility.architectures.contains(currentArchitecture) else {
            throw PluginValidationError.incompatibleArchitecture
        }

        if externalImport {
            guard marketplace || manifest.trustLevel == .community else {
                throw PluginValidationError.invalidTrustLevel
            }
            guard let entryPoint = manifest.entryPoint else {
                throw PluginValidationError.missingEntryPoint
            }
            guard entryPoint.protocolVersion == 1, isSafeRelativePath(entryPoint.executable) else {
                throw PluginValidationError.unsafeEntryPoint
            }
            guard let actions = manifest.actions, !actions.isEmpty else {
                throw PluginValidationError.actionsRequired
            }
            var actionIDs = Set<String>()
            for action in actions {
                guard action.id.range(
                    of: #"^[a-zA-Z0-9][a-zA-Z0-9._-]*$"#,
                    options: .regularExpression
                ) != nil,
                action.method.range(
                    of: #"^[a-zA-Z0-9][a-zA-Z0-9._-]*$"#,
                    options: .regularExpression
                ) != nil,
                !action.title.isEmpty
                else {
                    throw PluginValidationError.invalidAction(action.id)
                }
                guard actionIDs.insert(action.id).inserted else {
                    throw PluginValidationError.duplicateAction(action.id)
                }
            }
            if let ui = manifest.ui {
                guard ui.bridgeVersion == 1,
                      ui.entryPoint.hasSuffix(".html"),
                      isSafeRelativePath(ui.entryPoint) else {
                    throw PluginValidationError.unsafeUserInterface
                }
            }
            if let packageDirectory {
                let executable = packageDirectory
                    .appendingPathComponent(entryPoint.executable)
                    .standardizedFileURL
                let root = packageDirectory.standardizedFileURL
                let values = try? executable.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard executable.path.hasPrefix(root.path + "/"),
                      values?.isRegularFile == true,
                      values?.isSymbolicLink != true,
                      FileManager.default.isExecutableFile(atPath: executable.path) else {
                    throw PluginValidationError.entryPointNotExecutable
                }
                if let ui = manifest.ui {
                    let page = packageDirectory
                        .appendingPathComponent(ui.entryPoint)
                        .standardizedFileURL
                    let pageValues = try? page.resourceValues(
                        forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                    )
                    guard page.path.hasPrefix(root.path + "/"),
                          pageValues?.isRegularFile == true,
                          pageValues?.isSymbolicLink != true else {
                        throw PluginValidationError.userInterfaceNotFound
                    }
                }
            }
        }

        if marketplace {
            guard manifest.distribution.downloadURL?.scheme == "https" else {
                throw PluginValidationError.invalidDistribution("下载地址必须使用 HTTPS")
            }
            guard let checksum = manifest.distribution.sha256,
                  checksum.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
                throw PluginValidationError.invalidDistribution("必须提供小写 SHA-256")
            }
        }
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private static func isSemanticVersion(_ value: String) -> Bool {
        value.range(of: #"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$"#, options: .regularExpression) != nil
    }

    private static func isVersionNumber(_ value: String) -> Bool {
        value.range(of: #"^\d+(?:\.\d+){1,2}$"#, options: .regularExpression) != nil
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b ? 1 : -1 }
        }
        return 0
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return !path.split(separator: "/").contains("..")
    }

}
