import Testing
@testable import PluginDeckNVM

@Test func buildsDirectNVMInstallCommand() {
    #expect(NodeVersion(rawValue: "18.20.4").installCommand == "nvm install v18.20.4")
    #expect(NodeVersion(rawValue: "v22.16.0").installCommand == "nvm install v22.16.0")
}

@Test func parsesInstalledVersionsAndSortsNewestFirst() {
    let output = """
           v12.18.0
           v18.20.8
        -> v22.16.0
           v14.17.6
    default -> v22.16.0
    """

    #expect(
        NVMOutputParser.installedVersions(from: output).map(\.displayName)
            == ["v22.16.0", "v18.20.8", "v14.17.6", "v12.18.0"]
    )
}

@Test func parsesDefaultAlias() {
    #expect(
        NVMOutputParser.defaultVersion(from: "default -> v18.20.8 (*)")
            == NodeVersion(rawValue: "v18.20.8")
    )
}

@Test func parsesDefaultAliasWithoutVPrefix() {
    #expect(
        NVMOutputParser.defaultVersion(from: "default -> 18.20.4 (-> v18.20.4 *)")
            == NodeVersion(rawValue: "v18.20.4")
    )
}

@Test func missingDefaultAliasReturnsNil() {
    #expect(NVMOutputParser.defaultVersion(from: "default -> N/A") == nil)
}

@Test func parsesRemoteVersionsAndLTSNames() {
    let output = """
           v23.11.1
           v24.18.1   (LTS: Krypton)
           v24.19.0   (Latest LTS: Krypton)
    """

    let versions = NVMOutputParser.remoteVersions(from: output)
    #expect(versions.map(\.version.displayName) == ["v24.19.0", "v24.18.1", "v23.11.1"])
    #expect(versions[0].ltsName == "Krypton")
    #expect(versions[2].ltsName == nil)
}

@Test func parsesRemoteVersionMetadataFromNodeIndex() {
    let output = """
    version\tdate\tfiles\tnpm\tv8\tuv\tzlib\topenssl\tmodules\tlts\tsecurity
    v24.19.0\t2026-04-07\theaders,osx-arm64-tar,osx-x64-tar\t11.6.2\t13.6.233.17\t1.51.0\t1.3.1\t3.5.4\t137\tKrypton\ttrue
    v23.11.1\t2025-05-14\theaders,osx-x64-tar\t10.9.2\t12.9.202.28\t1.50.0\t1.3.0\t3.0.16\t131\t-\t-
    version\tdate\tfiles\tnpm\tv8\tuv\tzlib\topenssl\tmodules\tlts\tsecurity
    v24.19.0\t2026-04-07\theaders,osx-arm64-tar,osx-x64-tar\t11.6.2\t13.6.233.17\t1.51.0\t1.3.1\t3.5.4\t137\tKrypton\ttrue
    """

    let versions = NVMOutputParser.remoteVersions(fromIndexTable: output)
    #expect(versions.count == 2)
    #expect(versions.map(\.version.displayName) == ["v24.19.0", "v23.11.1"])
    #expect(versions[0].releaseDate == "2026-04-07")
    #expect(versions[0].npmVersion == "11.6.2")
    #expect(versions[0].v8Version == "13.6.233.17")
    #expect(versions[0].ltsName == "Krypton")
    #expect(versions[0].isSecurityRelease)
    #expect(versions[0].macArchitectureSummary == "Apple Silicon + Intel")
    #expect(versions[1].ltsName == nil)
    #expect(versions[1].macArchitectureSummary == "仅 Intel")
}
