import Foundation

struct DetectedProjectRequirement: Equatable, Sendable {
    let source: ProjectVersionSource
    let value: String
}

enum ProjectVersionDetector {
    static func detect(in path: String) -> DetectedProjectRequirement? {
        let directory = URL(fileURLWithPath: path)
        for (name, source) in [
            (".nvmrc", ProjectVersionSource.nvmrc),
            (".node-version", ProjectVersionSource.nodeVersion)
        ] {
            let url = directory.appendingPathComponent(name)
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                let value = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return DetectedProjectRequirement(source: source, value: value)
                }
            }
        }

        let packageURL = directory.appendingPathComponent("package.json")
        if
            let data = try? Data(contentsOf: packageURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let engines = json["engines"] as? [String: Any],
            let node = engines["node"] as? String,
            !node.isEmpty
        {
            return DetectedProjectRequirement(source: .packageEngines, value: node)
        }
        return nil
    }
}
