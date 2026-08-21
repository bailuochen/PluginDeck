import CryptoKit
import Foundation

public struct PluginImportCandidate: Sendable {
    public let manifest: PluginManifest
    public let packageDirectory: URL
    public let source: PluginInstallationSource
    public let origin: String

    public init(
        manifest: PluginManifest,
        packageDirectory: URL,
        source: PluginInstallationSource,
        origin: String
    ) {
        self.manifest = manifest
        self.packageDirectory = packageDirectory
        self.source = source
        self.origin = origin
    }
}

public struct InstalledPluginArtifact: Sendable {
    public let manifest: PluginManifest
    public let packageDirectory: URL
    public let source: PluginInstallationSource
}

public enum PluginInstallerError: LocalizedError {
    case invalidGitURL
    case toolUnavailable(String)
    case cloneFailed(String)
    case packageTooLarge
    case downloadFailed
    case checksumMismatch
    case extractionFailed(String)
    case unsafePackage(String)
    case manifestMismatch
    case versionAlreadyInstalled

    public var errorDescription: String? {
        switch self {
        case .invalidGitURL: "只支持不含凭据的公开 HTTPS Git 仓库"
        case .toolUnavailable(let message): "无法运行所需系统工具：\(message)"
        case .cloneFailed(let message): "克隆仓库失败：\(message)"
        case .packageTooLarge: "插件包超过 50 MB 限制"
        case .downloadFailed: "插件包下载失败"
        case .checksumMismatch: "插件包 SHA-256 校验失败"
        case .extractionFailed(let message): "插件包解压失败：\(message)"
        case .unsafePackage(let path): "插件包包含不安全路径或符号链接：\(path)"
        case .manifestMismatch: "下载包中的 plugin.json 与市场目录不一致"
        case .versionAlreadyInstalled: "相同版本已经安装"
        }
    }
}

public actor PluginPackageInstaller {
    private let pluginsDirectory: URL
    private let stagingDirectory: URL
    private let fileManager = FileManager.default

    public init(pluginsDirectory: URL) {
        self.pluginsDirectory = pluginsDirectory
        self.stagingDirectory = pluginsDirectory.deletingLastPathComponent()
            .appendingPathComponent("Staging", isDirectory: true)
    }

    public func inspectLocalDirectory(_ directory: URL) throws -> PluginImportCandidate {
        let root = directory.standardizedFileURL
        let manifest = try PluginManifestValidator.decodeManifest(in: root)
        try PluginManifestValidator.validate(
            manifest,
            packageDirectory: root,
            externalImport: true
        )
        return PluginImportCandidate(
            manifest: manifest,
            packageDirectory: root,
            source: .local,
            origin: root.path
        )
    }

    public func cloneGitRepository(_ url: URL) throws -> PluginImportCandidate {
        guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
            throw PluginInstallerError.invalidGitURL
        }
        try prepareStagingDirectory()
        let destination = stagingDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let result = try run(
            executable: "/usr/bin/git",
            arguments: ["clone", "--depth", "1", "--single-branch", url.absoluteString, destination.path]
        )
        guard result.status == 0 else {
            try? fileManager.removeItem(at: destination)
            throw PluginInstallerError.cloneFailed(result.output)
        }
        do {
            let manifest = try PluginManifestValidator.decodeManifest(in: destination)
            try PluginManifestValidator.validate(
                manifest,
                packageDirectory: destination,
                externalImport: true
            )
            return PluginImportCandidate(
                manifest: manifest,
                packageDirectory: destination,
                source: .git,
                origin: url.absoluteString
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    public func prepareMarketplacePlugin(_ manifest: PluginManifest) async throws -> PluginImportCandidate {
        try PluginManifestValidator.validate(manifest, externalImport: true, marketplace: true)
        guard let downloadURL = manifest.distribution.downloadURL else {
            throw PluginInstallerError.downloadFailed
        }
        let (data, response) = try await URLSession.shared.data(from: downloadURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PluginInstallerError.downloadFailed
        }
        guard data.count <= 50 * 1024 * 1024 else {
            throw PluginInstallerError.packageTooLarge
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == manifest.distribution.sha256 else {
            throw PluginInstallerError.checksumMismatch
        }

        try prepareStagingDirectory()
        let work = stagingDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archive = work.appendingPathExtension("zip")
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        try data.write(to: archive, options: .atomic)
        do {
            try preflightArchive(archive)
            let result = try run(
                executable: "/usr/bin/ditto",
                arguments: ["-x", "-k", archive.path, work.path]
            )
            try? fileManager.removeItem(at: archive)
            guard result.status == 0 else {
                throw PluginInstallerError.extractionFailed(result.output)
            }
            try validateTree(work)
            let root = try locatePackageRoot(in: work)
            let packagedManifest = try PluginManifestValidator.decodeManifest(in: root)
            guard packagedManifest == manifest else {
                throw PluginInstallerError.manifestMismatch
            }
            try PluginManifestValidator.validate(
                packagedManifest,
                packageDirectory: root,
                externalImport: true,
                marketplace: true
            )
            return PluginImportCandidate(
                manifest: manifest,
                packageDirectory: root,
                source: .marketplace,
                origin: downloadURL.absoluteString
            )
        } catch {
            try? fileManager.removeItem(at: archive)
            try? fileManager.removeItem(at: work)
            throw error
        }
    }

    public func install(_ candidate: PluginImportCandidate) throws -> InstalledPluginArtifact {
        try PluginManifestValidator.validate(
            candidate.manifest,
            packageDirectory: candidate.packageDirectory,
            externalImport: true,
            marketplace: candidate.source == .marketplace
        )
        try fileManager.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        let pluginRoot = pluginsDirectory.appendingPathComponent(candidate.manifest.id, isDirectory: true)
        let target = pluginRoot.appendingPathComponent(candidate.manifest.version, isDirectory: true)
        guard !fileManager.fileExists(atPath: target.path) else {
            throw PluginInstallerError.versionAlreadyInstalled
        }
        let staged = pluginsDirectory.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.copyItem(at: candidate.packageDirectory, to: staged)
            try? fileManager.removeItem(at: staged.appendingPathComponent(".git", isDirectory: true))
            try validateTree(staged)
            try PluginManifestValidator.validate(
                candidate.manifest,
                packageDirectory: staged,
                externalImport: true,
                marketplace: candidate.source == .marketplace
            )
            try fileManager.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
            try fileManager.moveItem(at: staged, to: target)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
        if candidate.source != .local {
            cleanup(candidate)
        }
        return InstalledPluginArtifact(
            manifest: candidate.manifest,
            packageDirectory: target,
            source: candidate.source
        )
    }

    public func cleanup(_ candidate: PluginImportCandidate) {
        guard candidate.source != .local else { return }
        let root = stagingDirectory.standardizedFileURL
        let target = candidate.packageDirectory.standardizedFileURL
        guard target.path.hasPrefix(root.path + "/") else { return }
        let relativePath = String(target.path.dropFirst(root.path.count + 1))
        guard let topLevel = relativePath.split(separator: "/").first else { return }
        try? fileManager.removeItem(
            at: root.appendingPathComponent(String(topLevel), isDirectory: true)
        )
    }

    private func prepareStagingDirectory() throws {
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
    }

    private func validateTree(_ directory: URL) throws {
        var totalSize: Int64 = 0
        var itemCount = 0
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey],
            options: []
        ) else { return }
        for case let url as URL in enumerator {
            itemCount += 1
            guard itemCount <= 5_000 else { throw PluginInstallerError.packageTooLarge }
            let values = try? url.resourceValues(
                forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
            )
            if values?.isSymbolicLink == true {
                throw PluginInstallerError.unsafePackage(url.lastPathComponent)
            }
            if values?.isRegularFile == true {
                totalSize += Int64(values?.fileSize ?? 0)
                guard totalSize <= 200 * 1024 * 1024 else {
                    throw PluginInstallerError.packageTooLarge
                }
            }
            guard url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/") else {
                throw PluginInstallerError.unsafePackage(url.path)
            }
        }
    }

    private func preflightArchive(_ archive: URL) throws {
        let listing = try run(executable: "/usr/bin/unzip", arguments: ["-Z1", archive.path])
        guard listing.status == 0 else {
            throw PluginInstallerError.extractionFailed(listing.output)
        }
        let paths = listing.output.split(whereSeparator: \.isNewline).map(String.init)
        guard paths.count <= 5_000 else { throw PluginInstallerError.packageTooLarge }
        for path in paths {
            guard !path.hasPrefix("/"),
                  !path.split(separator: "/").contains(".."),
                  !path.contains("\\") else {
                throw PluginInstallerError.unsafePackage(path)
            }
        }
        let sizeListing = try run(executable: "/usr/bin/unzip", arguments: ["-l", archive.path])
        guard sizeListing.status == 0 else {
            throw PluginInstallerError.extractionFailed(sizeListing.output)
        }
        let pattern = #"(?m)^\s*(\d+)\s+\d+\s+files?\s*$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.matches(
                in: sizeListing.output,
                range: NSRange(sizeListing.output.startIndex..., in: sizeListing.output)
           ).last,
           let range = Range(match.range(at: 1), in: sizeListing.output),
           let total = Int64(sizeListing.output[range]),
           total > 200 * 1024 * 1024 {
            throw PluginInstallerError.packageTooLarge
        }
    }

    private func locatePackageRoot(in directory: URL) throws -> URL {
        if fileManager.fileExists(atPath: directory.appendingPathComponent("plugin.json").path) {
            return directory
        }
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let roots = children.filter {
            fileManager.fileExists(atPath: $0.appendingPathComponent("plugin.json").path)
        }
        guard roots.count == 1, let root = roots.first else {
            throw PluginValidationError.manifestNotFound
        }
        return root
    }

    private func run(executable: String, arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "GIT_TERMINAL_PROMPT": "0",
            "LANG": "C"
        ]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PluginInstallerError.toolUnavailable(error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
