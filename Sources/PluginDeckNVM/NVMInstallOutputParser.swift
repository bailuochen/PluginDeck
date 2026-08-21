import Foundation

struct NVMInstallOutputSnapshot: Equatable, Sendable {
    let progress: Double?
    let stage: String
    let cleanedOutput: String
}

enum NVMInstallOutputParser {
    static func parse(_ rawOutput: String) -> NVMInstallOutputSnapshot {
        let normalized = stripANSICodes(from: rawOutput)
            .replacingOccurrences(of: "\r", with: "\n")

        return NVMInstallOutputSnapshot(
            progress: latestProgress(in: normalized),
            stage: stage(in: normalized),
            cleanedOutput: cleanedOutput(from: normalized)
        )
    }

    private static func latestProgress(in output: String) -> Double? {
        let pattern = #"\b(\d{1,3}(?:\.\d+)?)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        return regex.matches(
            in: output,
            range: NSRange(output.startIndex..., in: output)
        ).compactMap { match -> Double? in
            guard let range = Range(match.range(at: 1), in: output) else { return nil }
            guard let percentage = Double(output[range]), (0...100).contains(percentage) else {
                return nil
            }
            return percentage / 100
        }.last
    }

    private static func stage(in output: String) -> String {
        let markers = [
            ("Now using node", "正在完成安装"),
            ("is already installed", "正在完成安装"),
            ("Checksums matched", "校验完成，正在安装"),
            ("Computing checksum", "正在校验下载文件"),
            ("Verifying checksum", "正在校验下载文件"),
            ("Downloading and installing node", "正在下载 Node.js"),
            ("Downloading https://", "正在下载 Node.js"),
            ("NVM 远程查询暂时失败", "远程查询失败，正在重试"),
            ("下载长时间没有进展", "下载停滞，正在断点续传")
        ]
        let latest = markers.compactMap { marker, stage -> (String.Index, String)? in
            guard let range = output.range(of: marker, options: .backwards) else { return nil }
            return (range.lowerBound, stage)
        }.max { $0.0 < $1.0 }
        if let latest {
            return latest.1
        }
        return "正在查询可用版本"
    }

    private static func cleanedOutput(from output: String) -> String {
        var lines: [String] = []

        for substring in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(substring).trimmingCharacters(in: .whitespaces)
            guard !isProgressNoise(line) else { continue }

            if line.isEmpty {
                if !lines.isEmpty && lines.last != "" {
                    lines.append("")
                }
            } else {
                lines.append(line)
            }
        }

        while lines.last == "" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func isProgressNoise(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        if line.hasPrefix("% Total") || line.hasPrefix("Dload") {
            return true
        }
        if line.contains("--:--:--") {
            return true
        }

        let progressCharacters = CharacterSet(charactersIn: "#=O0+*- .0123456789%")
        return line.unicodeScalars.allSatisfy { progressCharacters.contains($0) }
    }

    private static func stripANSICodes(from output: String) -> String {
        let pattern = "\u{001B}\\[[0-?]*[ -/]*[@-~]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return output }
        return regex.stringByReplacingMatches(
            in: output,
            range: NSRange(output.startIndex..., in: output),
            withTemplate: ""
        )
    }
}
