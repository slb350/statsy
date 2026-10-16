import Foundation
import Testing
@testable import StatsyKit

/// A captured scrape and the target it was captured from.
struct FleetFixture: Sendable {
    let target: RemoteTarget
    let text: String
    /// Parsed once, unfiltered, for the tests that inspect the raw series.
    let metrics: MetricSet

    init(name: String, target: RemoteTarget) {
        self.target = target
        text = Fixtures.text(name)
        metrics = MetricSet(text: text)
    }

    /// A few seconds after the host's own collector last ran, so ages come
    /// out as they did live.
    var captured: Date {
        let stamp = metrics.value(
            "homelab_collection_timestamp_seconds", ["asset_host": target.hostName]
        ) ?? 0
        return Date(timeIntervalSince1970: stamp + 5)
    }

    /// Two scrapes 2 s apart, the second with each core one second busier in
    /// user time, so utilisation has a delta behind it.
    func snapshot(processes: ProcessTable = .empty) -> Snapshot {
        var mapper = RemoteMapper(target: target)
        let now = captured
        _ = mapper.snapshot(from: metrics, now: now, link: LinkStatus(state: .live))
        return mapper.snapshot(
            from: metrics, now: now.addingTimeInterval(2), link: LinkStatus(state: .live),
            processes: processes
        )
    }

    static let homelab1 = FleetFixture(name: "homelab-1", target: TargetRegistry.homelab1.remote!)
    static let legion = FleetFixture(
        name: "homelab-legion", target: TargetRegistry.homelabLegion.remote!
    )
    static let macMini2 = FleetFixture(name: "mac-mini-2", target: TargetRegistry.macMini2.remote!)
    static let macMini3 = FleetFixture(name: "mac-mini-3", target: TargetRegistry.macMini3.remote!)
    static let macMiniM6 = FleetFixture(name: "mac-mini-m6", target: TargetRegistry.macMiniM6.remote!)
    static let all = [homelab1, legion, macMini2, macMini3, macMiniM6]
}

@Suite("Remote mapper — the rest of the fleet")
struct RemoteMapperFleetTests {
    // MARK: - Every new target

    @Test("the declared series cover everything the mapper reads", arguments: FleetFixture.all)
    func wantedSeries(fixture: FleetFixture) {
        var filtered = RemoteMapper(target: fixture.target)
        var unfiltered = RemoteMapper(target: fixture.target)
        let now = fixture.captured
        let link = LinkStatus(state: .live)
        #expect(
            filtered.snapshot(from: filtered.metrics(from: fixture.text), now: now, link: link)
                == unfiltered.snapshot(from: fixture.metrics, now: now, link: link)
        )
    }

    @Test("reducing a scrape keeps every line the mapper reads, verbatim", arguments: FleetFixture.all)
    func reduction(fixture: FleetFixture) {
        let mapper = RemoteMapper(target: fixture.target)
        let reduced = PrometheusText.lines(fixture.text, wanted: mapper.wants)
        // Comments go, and nothing the mapper reads is lost on the way.
        #expect(reduced.allSatisfy { !$0.hasPrefix("#") })
        #expect(
            MetricSet(PrometheusText.parse(reduced.joined(separator: "\n")))
                == mapper.metrics(from: fixture.text)
        )
    }

    @Test("every fixture carries its own host's collector series", arguments: FleetFixture.all)
    func ownCollector(fixture: FleetFixture) {
        // The renderer's guard: a capture is accepted for a target only when
        // it carries that target's asset_host.
        #expect(PrometheusText.parse(fixture.text).contains {
            $0.name.hasPrefix(fixture.target.collectorPrefix)
                && $0.labels["asset_host"] == fixture.target.hostName
        })
    }

    @Test("every remote target declares process ranking", arguments: FleetFixture.all)
    func ranksProcesses(fixture: FleetFixture) {
        #expect(fixture.snapshot().machine.ranksProcesses)
    }

    @Test("a ranked table handed in reaches the snapshot unchanged")
    func processesPassThrough() {
        let table = ProcessTable.ranked(
            [ProcessSample(id: 7, name: "prometheus", cpu: 9.1, memory: 364_708 * 1024)], limit: 5
        )
        #expect(FleetFixture.homelab1.snapshot(processes: table).processes == table)
    }

    // MARK: - homelab-1

    @Test("homelab-1 draws its one discrete card")
    func homelab1GPU() throws {
        let gpus = FleetFixture.homelab1.snapshot().gpus
        let gpu = try #require(gpus.first)
        #expect(gpus.count == 1)
        #expect(gpu.memoryLabel == "VRAM")
        // The driver's usable VRAM excludes a small reserved part of the 32 GB card.
        #expect(gpu.memoryTotal == 34_208_743_424)
        #expect(gpu.wattLimit == 300)
        #expect(gpu.powerDescription == "\(Format.decimal(gpu.watts, decimals: 0)) / 300 W")
        // A discrete card's VRAM is not system memory.
        #expect(FleetFixture.homelab1.snapshot().memory.gpuShared == 0)
    }

    @Test("homelab-1 sums both NVMe drives for throughput")
    func homelab1Disks() {
        let metrics = FleetFixture.homelab1.metrics
        let expected = ["nvme0n1", "nvme1n1"].compactMap {
            metrics.value("node_disk_read_bytes_total", ["device": $0]).map(RemoteMapper.bytes)
        }.reduce(0, +)
        #expect(FleetFixture.homelab1.snapshot().storage.lifetimeRead == expected)
        #expect(expected > 0)
    }

    @Test("homelab-1 shows the local volumes its native exporter publishes")
    func homelab1Volumes() throws {
        let storage = FleetFixture.homelab1.snapshot().storage
        #expect(storage.volumes.map(\.name) == ["Root", "Srv"])
        let local = storage.volumes.filter { $0.role != .network }
        #expect(storage.total == local.reduce(0) { $0 + $1.total })
        #expect(try #require(storage.volumes.last).total > 1 << 40)
    }

    @Test("homelab-1 counts native utilities with former container services retired")
    func homelab1Services() {
        let services = FleetFixture.homelab1.snapshot().services
        let metrics = FleetFixture.homelab1.metrics
        #expect(services.totalUnits == metrics.samples("homelab_service_active").count)
        #expect(services.totalContainers == metrics.samples("homelab_container_running").count)
        #expect(services.totalUnits == 6)
        #expect(services.totalContainers == 0)
        #expect(services.endpoints.isEmpty)
    }

    @Test("homelab-1 reads all 16 threads")
    func homelab1Cores() {
        #expect(FleetFixture.homelab1.snapshot().cpu.cores.count == 16)
        #expect(FleetFixture.homelab1.snapshot().machine.platformVersion == "Linux 7.0.0-38-generic")
    }

    // MARK: - homelab-legion

    @Test("Legion ignores the series it collects on the NAS hosts' behalf")
    func legionScoping() throws {
        let metrics = FleetFixture.legion.metrics
        let foreign = metrics.samples("homelab_container_running")
            .filter { $0.labels["asset_host"] != "homelab-legion" }
        // The fixture really does carry them, or this test proves nothing.
        #expect(!foreign.isEmpty)

        let services = FleetFixture.legion.snapshot().services
        let own = metrics.samples("homelab_container_running")
            .filter { $0.labels["asset_host"] == "homelab-legion" }
        #expect(services.totalContainers == own.count)
        #expect(services.endpoints.map(\.name) == ["operations-goalert", "operations-grafana"])

        // The age is Legion's own run, not BabyNas's or DondeNas's.
        let stamp = try #require(
            metrics.value("homelab_collection_timestamp_seconds", ["asset_host": "homelab-legion"])
        )
        let age = try #require(services.collectionAge)
        let expected = FleetFixture.legion.captured.timeIntervalSince1970 + 2 - stamp
        #expect(abs(age - expected) < 0.001)
        #expect(age > 0)
    }

    @Test("Legion's APU reports its temperature through amdgpu hwmon")
    func legionGPUTemperature() throws {
        let snapshot = FleetFixture.legion.snapshot()
        // No collector GPU stage, so no card.
        #expect(snapshot.gpus.isEmpty)
        let gpu = try #require(snapshot.thermal[.gpu])
        #expect(gpu.count == 1)
    }

    @Test("Legion's volumes come from its own mounts, never the NAS hosts'")
    func legionVolumes() {
        let storage = FleetFixture.legion.snapshot().storage
        #expect(storage.volumes.map(\.name) == ["Root", "Srv", "NAS"])
    }

    // MARK: - The Mac minis

    @Test("a mini maps as macOS with its product version")
    func miniPlatform() {
        let machine = FleetFixture.macMini3.snapshot().machine
        #expect(machine.platformVersion == "macOS 26.6")
        #expect(machine.memoryBytes == 16 << 30)
        #expect(machine.summary.contains("4E + 4P"))
    }

    @Test("a mini's memory is the Mach buckets, read as the local panel reads them")
    func miniMemory() throws {
        let metrics = FleetFixture.macMini3.metrics
        func value(_ name: String) throws -> UInt64 {
            RemoteMapper.bytes(try #require(metrics.value("node_memory_\(name)_bytes")))
        }
        let memory = FleetFixture.macMini3.snapshot().memory
        #expect(memory.active == (try value("active")))
        #expect(memory.wired == (try value("wired")))
        #expect(memory.compressed == (try value("compressed")))
        #expect(memory.reclaimable == (try value("inactive")))
        #expect(memory.inUse == memory.active + memory.wired + memory.compressed)
        #expect(memory.swapUsed == (try value("swap_used")))
        #expect(memory.gpuShared == 0)
    }

    @Test("a mini's network totals leave out loopback")
    func miniNetwork() throws {
        let metrics = FleetFixture.macMini3.metrics
        let loopback = try #require(metrics.value("node_network_receive_bytes_total", ["device": "lo0"]))
        let all = metrics.samples("node_network_receive_bytes_total")
            .reduce(0) { $0 + RemoteMapper.bytes($1.value) }
        #expect(FleetFixture.macMini3.snapshot().network.lifetimeIn == all - RemoteMapper.bytes(loopback))
        #expect(loopback > 0)
    }

    @Test("a mini reads all eight cores in two clusters")
    func miniCores() {
        let snapshot = FleetFixture.macMini2.snapshot()
        #expect(snapshot.cpu.cores.count == 8)
        #expect(snapshot.machine.clusters.map(\.coreCount) == [4, 4])
    }

    @Test("a mini's disk is its APFS container, with NAS mounts beside it")
    func miniVolumes() throws {
        let storage = FleetFixture.macMini2.snapshot().storage
        #expect(storage.volumes.map(\.name) == ["Data", "Models", "Backups"])
        let data = try #require(storage.volumes.first)
        #expect(storage.total == data.total)
        #expect(storage.lifetimeRead > 0)
    }

    @Test("a mini counts LaunchAgents as its units")
    func miniUnits() {
        let metrics = FleetFixture.macMini3.metrics
        let services = FleetFixture.macMini3.snapshot().services
        #expect(services.totalUnits == metrics.samples("homelab_launchagent_loaded").count)
        #expect(services.totalUnits > 0)
        #expect(services.totalContainers == 5)
    }

    @Test("a mini has no sensors to show")
    func miniThermal() {
        #expect(FleetFixture.macMini2.snapshot().thermal.clusters.isEmpty)
    }

    // MARK: - mac-mini-m6

    @Test("M6 maps all 12 cores and its macOS product version")
    func m6Machine() {
        let snapshot = FleetFixture.macMiniM6.snapshot()
        #expect(snapshot.cpu.cores.map(\.id) == Array(0..<12))
        #expect(snapshot.machine.clusters.map(\.coreCount) == [6, 2, 4])
        #expect(snapshot.machine.platformVersion == "macOS 27.0")
        #expect(snapshot.memory.total == 16 << 30)
        #expect(snapshot.memory.inUse == 13_378_945_024)
        #expect(snapshot.memory.gpuShared == 0)
        #expect(snapshot.gpus.isEmpty)
    }

    @Test("M6 counts only its internal disk in capacity and throughput")
    func m6Storage() throws {
        let fixture = FleetFixture.macMiniM6
        let storage = fixture.snapshot().storage
        #expect(storage.volumes.map(\.name) == ["Data", "Models", "Backups"])
        let data = try #require(storage.volumes.first)
        #expect(data.total == 245_054_767_104)
        #expect(storage.total == data.total)
        #expect(storage.free == data.total - data.used)
        #expect(storage.volumes.dropFirst().allSatisfy { $0.role == .network })
        let disk0 = try #require(fixture.metrics.value("node_disk_read_bytes_total", ["device": "disk0"]))
        #expect(storage.lifetimeRead == RemoteMapper.bytes(disk0))
        // The simulator's disk image publishes disk4; it must not be counted.
        #expect(fixture.metrics.value("node_disk_read_bytes_total", ["device": "disk4"]) != nil)
    }

    @Test("M6 reads readiness collector age without inventing service counts")
    func m6Collector() throws {
        let services = FleetFixture.macMiniM6.snapshot().services
        #expect(try #require(services.collectionAge) == 7)
        #expect(services.totalUnits == 0)
        #expect(services.totalContainers == 0)
        #expect(services.endpoints.isEmpty)
    }
}
