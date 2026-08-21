import Foundation

enum NVMOutputParser {
    static func installedVersions(from output: String) -> [NodeVersion] {
        let pattern = #"(?m)^\s*(?:->\s*)?(v\d+\.\d+\.\d+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(output.startIndex..., in: output)

        let versions = regex.matches(in: output, range: range).compactMap { match -> NodeVersion? in
            guard let capture = Range(match.range(at: 1), in: output) else { return nil }
            return NodeVersion(rawValue: String(output[capture]))
        }

        return Array(Set(versions)).sorted(by: >)
    }

    static func defaultVersion(from output: String) -> NodeVersion? {
        let pattern = #"default\s*->\s*v?(\d+\.\d+\.\d+)(?:\s|$)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: output,
                range: NSRange(output.startIndex..., in: output)
            ),
            let capture = Range(match.range(at: 1), in: output)
        else { return nil }

        return NodeVersion(rawValue: "v" + String(output[capture]))
    }

    static func remoteVersions(from output: String) -> [RemoteNodeVersion] {
        let pattern = #"(?m)^\s*(v\d+\.\d+\.\d+)(?:\s+\((?:Latest )?LTS:\s*([^)]+)\))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(output.startIndex..., in: output)

        return regex.matches(in: output, range: range).compactMap { match in
            guard let versionRange = Range(match.range(at: 1), in: output) else { return nil }
            let version = NodeVersion(rawValue: String(output[versionRange]))
            let ltsName: String?
            if let nameRange = Range(match.range(at: 2), in: output) {
                ltsName = String(output[nameRange])
            } else {
                ltsName = nil
            }
            return RemoteNodeVersion(version: version, ltsName: ltsName)
        }.sorted { $0.version > $1.version }
    }

    static func remoteVersions(fromIndexTable output: String) -> [RemoteNodeVersion] {
        let lines = output.split(whereSeparator: \Character.isNewline)
        guard let headerLine = lines.first else { return [] }

        let headers = headerLine
            .split(separator: "\t", omittingEmptySubsequences: false)
            .map(String.init)
        let indexes = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })

        guard
            let versionIndex = indexes["version"],
            let dateIndex = indexes["date"],
            let filesIndex = indexes["files"],
            let npmIndex = indexes["npm"],
            let v8Index = indexes["v8"],
            let ltsIndex = indexes["lts"],
            let securityIndex = indexes["security"]
        else { return [] }

        func value(in columns: [Substring], at index: Int) -> String? {
            guard columns.indices.contains(index) else { return nil }
            let value = String(columns[index])
            return value.isEmpty || value == "-" ? nil : value
        }

        let releases = lines.dropFirst().compactMap { line -> RemoteNodeVersion? in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard let rawVersion = value(in: columns, at: versionIndex) else { return nil }
            guard rawVersion.range(of: #"^v\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else {
                return nil
            }

            let files = value(in: columns, at: filesIndex).map {
                Set($0.split(separator: ",").map(String.init))
            } ?? []
            let security = value(in: columns, at: securityIndex)?.lowercased()

            return RemoteNodeVersion(
                version: NodeVersion(rawValue: rawVersion),
                ltsName: value(in: columns, at: ltsIndex),
                releaseDate: value(in: columns, at: dateIndex),
                npmVersion: value(in: columns, at: npmIndex),
                v8Version: value(in: columns, at: v8Index),
                availableFiles: files,
                isSecurityRelease: security == "true"
            )
        }

        return Dictionary(
            releases.map { ($0.id, $0) },
            uniquingKeysWith: { _, replacement in replacement }
        ).values.sorted { $0.version > $1.version }
    }
}
