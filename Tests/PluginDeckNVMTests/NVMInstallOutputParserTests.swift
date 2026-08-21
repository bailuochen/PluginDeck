import Testing
@testable import PluginDeckNVM

@Test func reportsVersionLookupBeforeDownloadStarts() {
    #expect(NVMInstallOutputParser.parse("").stage == "正在查询可用版本")
}

@Test func reportsTransientLookupRetry() {
    let output = "NVM 远程查询暂时失败，正在重试…"
    #expect(NVMInstallOutputParser.parse(output).stage == "远程查询失败，正在重试")
}

@Test func reportsStallRecoveryUntilDownloadResumes() {
    let stalled = """
    Downloading https://nodejs.org/node.tar.xz...
    下载长时间没有进展，正在断点续传（2/3）
    """
    #expect(NVMInstallOutputParser.parse(stalled).stage == "下载停滞，正在断点续传")

    let resumed = stalled + "\nDownloading https://nodejs.org/node.tar.xz..."
    #expect(NVMInstallOutputParser.parse(resumed).stage == "正在下载 Node.js")
}

@Test func parsesInstallProgressAndCleansCurlNoise() {
    let output = """
    Downloading and installing node v24.18.0...
    Downloading https://nodejs.org/dist/v24.18.0/node-v24.18.0-darwin-arm64.tar.xz...
    \r#=#=#
    \r##O#-#
    \r######## 42.5%
    """

    let snapshot = NVMInstallOutputParser.parse(output)

    #expect(snapshot.progress == 0.425)
    #expect(snapshot.stage == "正在下载 Node.js")
    #expect(snapshot.cleanedOutput.contains("Downloading and installing node v24.18.0"))
    #expect(!snapshot.cleanedOutput.contains("42.5%"))
    #expect(!snapshot.cleanedOutput.contains("#=#=#"))
}

@Test func tracksChecksumAndCompletionStages() {
    let checksum = NVMInstallOutputParser.parse("Computing checksum with shasum -a 256")
    #expect(checksum.stage == "正在校验下载文件")

    let matched = NVMInstallOutputParser.parse("Checksums matched!")
    #expect(matched.stage == "校验完成，正在安装")

    let complete = NVMInstallOutputParser.parse("Now using node v24.18.0 (npm v11.6.2)")
    #expect(complete.stage == "正在完成安装")
}

@Test func removesANSIFormattingFromInstallLog() {
    let output = "\u{001B}[32mNow using node v24.18.0\u{001B}[0m"
    let snapshot = NVMInstallOutputParser.parse(output)

    #expect(snapshot.cleanedOutput == "Now using node v24.18.0")
}
