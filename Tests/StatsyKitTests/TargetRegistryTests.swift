import Foundation
import Testing
@testable import StatsyKit

@Suite("Target registry")
struct TargetRegistryTests {
    private var remotes: [RemoteTarget] { TargetRegistry.all.compactMap(\.remote) }

    @Test("M6 uses its own address and three tiers in CPU index order")
    func m6Configuration() throws {
        let target = try #require(TargetRegistry.target(id: "mac-mini-m6"))
        let remote = try #require(target.remote)
        #expect(remote.sshDestination == "stephenbrandon@192.168.70.165")
        #expect(remote.exporterHost == "127.0.0.1")
        #expect(remote.localPort == 19265)
        #expect(remote.platform == .macOS)
        #expect(remote.hostName == "mac-mini-m6")
        #expect(remote.model == "Apple M6")
        #expect(remote.gpuDescription == "12-core GPU")
        #expect(remote.clusters == [
            CPUCluster(name: "Efficiency", coreCount: 6),
            CPUCluster(name: "Super", coreCount: 2),
            CPUCluster(name: "Performance", coreCount: 4)
        ])
        #expect(remote.diskDevices == ["disk0"])
        #expect(remote.volumes.map(\.name) == ["Data", "Models", "Backups"])
        #expect(remote.ranksProcesses)
        // Apple GPU occupancy already lives in the Darwin memory buckets.
        #expect(!remote.unifiedMemory)
    }

    @Test("every remote target owns its own tunnel port")
    func distinctPorts() {
        let ports = remotes.map(\.localPort)
        #expect(Set(ports).count == ports.count)
    }

    @Test("every remote target names itself as its collector does")
    func distinctHostNames() {
        let names = remotes.map(\.hostName)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0 == $0.lowercased() })
    }

    @Test("each new host forwards to where its exporter listens", arguments: [
        (TargetRegistry.homelab1, "steve@192.168.68.73", "192.168.68.73", RemotePlatform.linux),
        (TargetRegistry.homelabLegion, "steve@192.168.68.72", "127.0.0.1", .linux),
        (TargetRegistry.macMini2, "stephenbrandon@192.168.68.82", "127.0.0.1", .macOS),
        (TargetRegistry.macMini3, "stephenbrandon@192.168.68.84", "127.0.0.1", .macOS),
        (TargetRegistry.macMiniM6, "stephenbrandon@192.168.70.165", "127.0.0.1", .macOS)
    ])
    func exporterBinding(target: Target, destination: String, exporter: String, platform: RemotePlatform) throws {
        let remote = try #require(target.remote)
        #expect(remote.sshDestination == destination)
        #expect(remote.exporterHost == exporter)
        #expect(remote.platform == platform)
        #expect(remote.ranksProcesses)
        #expect(TargetRegistry.target(id: target.id) == target)
    }

    @Test("a scrape asks node_exporter for only the named collectors")
    func scrapeURL() throws {
        let remote = try #require(TargetRegistry.strix.remote)
        let url = try #require(remote.scrapeURL(collectors: ["cpu", "meminfo"]))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "127.0.0.1")
        #expect(components.port == 19163)
        #expect(components.path == "/metrics")
        #expect(components.queryItems == [
            URLQueryItem(name: "collect[]", value: "cpu"),
            URLQueryItem(name: "collect[]", value: "meminfo")
        ])
    }

    @Test("capacity is read on its own cadence and nowhere else", arguments: [
        RemotePlatform.linux, .macOS
    ])
    func collectorSplit(platform: RemotePlatform) {
        #expect(platform.capacityCollectors == ["filesystem"])
        #expect(!platform.liveCollectors.contains("filesystem"))
        // The fleet textfile carries units, GPUs and the capacity fallback.
        #expect(platform.liveCollectors.contains("textfile"))
    }

    @Test("each platform streams the top its parser reads")
    func topDialects() {
        #expect(RemotePlatform.linux.topDialect == .procps)
        #expect(RemotePlatform.linux.topCommand.contains("-b"))
        #expect(RemotePlatform.macOS.topDialect == .darwin)
        #expect(RemotePlatform.macOS.topCommand.contains("-l 0"))
    }
}
