import Foundation
import Testing
@testable import StatsyKit

/// The strix target, exercised against a scrape the host actually produced.
///
/// Strix is the unified-memory shape: a Strix Halo serving a model out of a
/// GTT pool `/proc/meminfo` does not see, with GPU figures arriving from the
/// fleet collector's amdgpu stage. The readings that break here are the ones
/// ai-1 cannot produce — a lone GPU whose memory is system memory, GPU
/// temperature arriving from the textfile beside an amdgpu hwmon chip the
/// cluster map must ignore.
@Suite("Remote mapper — strix")
struct RemoteMapperStrixTests {
    static let metrics = MetricSet(text: fixture())
    static let target = TargetRegistry.strix.remote!
    /// One minute after the fixture's own `homelab_collection_timestamp_seconds`
    /// stamp, so the collection age the mapper reports is the ~60 s this
    /// fixture pins, not a value against the wall clock.
    static let captured = Date(
        timeIntervalSince1970: (Self.metrics.value("homelab_collection_timestamp_seconds") ?? 0) + 60
    )

    static func fixture() -> String {
        let url = Bundle.module.url(
            forResource: "strix", withExtension: "prom", subdirectory: "Fixtures"
        )
        return (try? String(contentsOf: url!, encoding: .utf8)) ?? ""
    }

    private func mapped() -> Snapshot {
        var mapper = RemoteMapper(target: Self.target)
        return mapper.snapshot(from: Self.metrics, now: Self.captured, link: LinkStatus(state: .live))
    }

    // MARK: - Fixture

    @Test("the fixture parses")
    func fixtureLoads() {
        #expect(Self.metrics.samples("node_cpu_seconds_total").count == 256)
    }

    // MARK: - CPU and identity

    @Test("reads all 32 threads")
    func coreCount() {
        #expect(RemoteMapper.ticks(from: Self.metrics).count == 32)
    }

    @Test("names the host, platform and GPU as declared")
    func identity() throws {
        let machine = mapped().machine
        #expect(machine.host == "strix")
        #expect(machine.platformVersion == "Linux 7.0.0-34-generic")
        #expect(machine.summary.contains("RADEON 8060S 128 GB (UNIFIED)"))
        // MemTotal, not the 128 GiB on the sticker — the fixture's own value.
        // Pinned, so a fixture that loses the series fails the test rather
        // than comparing 0 == 0.
        let memTotal = try #require(Self.metrics.value("node_memory_MemTotal_bytes"))
        #expect(machine.memoryBytes == UInt64(memTotal))
        #expect(!machine.ranksProcesses)
    }

    // MARK: - Memory buckets and the unified-memory fold

    @Test("anonymous and shared pages are active, kernel memory is wired")
    func linuxBuckets() {
        func value(_ name: String) -> Double {
            Self.metrics.value("node_memory_\(name)_bytes") ?? 0
        }
        let memory = mapped().memory
        #expect(memory.active == UInt64(value("AnonPages")) + UInt64(value("Shmem")))
        #expect(
            memory.wired
                == UInt64(value("SUnreclaim")) + UInt64(value("KernelStack"))
                    + UInt64(value("PageTables")) + UInt64(value("Percpu"))
        )
        #expect(memory.total == UInt64(value("MemTotal")))
    }

    // MARK: - Thermal

    /// The fixture's own `node_hwmon_temp_celsius` readings for a driver,
    /// joined through `node_hwmon_chip_names` the way the mapper does.
    private static func readings(forDriver driver: String) -> [Double] {
        guard let chip = Self.metrics.samples("node_hwmon_chip_names")
            .first(where: { $0.labels["chip_name"] == driver })?.labels["chip"]
        else { return [] }
        return Self.metrics.samples("node_hwmon_temp_celsius")
            .filter { $0.labels["chip"] == chip }
            .map(\.value)
    }

    @Test("finds the CPU package through k10temp and the NVMe through nvme")
    func hwmonClusters() throws {
        let cpu = try #require(mapped().thermal[.cpu])
        // The single k10temp reading (chip pci0000:00_0000:00_18_3) is the
        // CPU package, and the nvme chip's readings are the drive.
        let package = Self.readings(forDriver: "k10temp")
        #expect(package.count == 1)
        #expect(cpu.count == package.count)
        #expect(cpu.average == package.reduce(0, +) / Double(package.count))
        let storage = try #require(mapped().thermal[.storage])
        let drive = Self.readings(forDriver: "nvme")
        #expect(storage.count == drive.count)
        #expect(storage.average == drive.reduce(0, +) / Double(drive.count))
    }

    @Test("GPU temperature comes from the textfile alone, not the amdgpu hwmon chip")
    func gpuTemperatureIsSingleSource() throws {
        let gpu = try #require(mapped().thermal[.gpu])
        let expected = try #require(Self.metrics.value("homelab_gpu_temperature_celsius"))
        #expect(gpu.count == 1)
        #expect(gpu.average == expected)
    }

    @Test("sensors that belong to no cluster are dropped")
    func unrelatedSensors() {
        // Every sensor on a chip with no cluster must stay out: the fixture
        // holds one mt7925 (WiFi) reading and two acpitz (ACPI zone) readings,
        // and r8169, the wired NIC, is the likeliest future cluster-map
        // mistake — its chip name reads like a device, so it tempts a map.
        #expect(mapped().thermal[.battery] == nil)
        #expect(mapped().thermal.fans.isEmpty)
    }

    // MARK: - Storage

    @Test("shows Root alone; coldstore is undeclared by contract")
    func volumes() throws {
        let volumes = mapped().storage.volumes
        // /mnt/coldstore is deliberately not among the target's volumes: the
        // fleet's contract checks that hard NFS mount's presence but never
        // stats it (a stalled server would wedge the collector past every
        // timeout), and node_exporter publishes no capacity for it either —
        // so no safe source can ever fill the row.
        #expect(volumes.map(\.name) == ["Root"])
        let root = try #require(volumes.first)
        #expect(root.fraction >= 0 && root.fraction <= 1)
    }

    @Test("headline capacity covers local storage only")
    func capacityExcludesTheNAS() throws {
        let storage = mapped().storage
        // Byte-exact: the headline is the fixture's own root filesystem size,
        // and BabyNas's coldstore cannot leak into it. Pinned, so a fixture
        // that loses the series fails the test rather than comparing 0 == 0.
        let rootSize = try #require(
            Self.metrics.value("node_filesystem_size_bytes", ["mountpoint": "/"])
        )
        #expect(storage.total == RemoteMapper.bytes(rootSize))
        // No network volume is declared for this host, and none may leak in.
        #expect(!storage.volumes.contains { $0.role == .network })
    }

    // MARK: - Services and link

    @Test("reads the flash-next endpoint and the declared units")
    func services() {
        let services = mapped().services
        #expect(services.totalUnits == 7)
        #expect(services.allUnitsActive)
        #expect(services.endpoints == [EndpointReadiness(name: "flash-next", ready: true)])
    }

    @Test("reports how old the collector's run is")
    func collectionAge() throws {
        let age = try #require(mapped().services.collectionAge)
        // `captured` sits exactly a minute past the fixture's stamp.
        #expect(age >= 59 && age < 61)
    }

    @Test("reads uptime and host-wide traffic")
    func uptimeAndNetwork() {
        #expect(mapped().uptime > 0)
        #expect(mapped().network.lifetimeIn > 0)
        #expect(mapped().network.lifetimeOut > 0)
    }

    // MARK: - Filtering

    @Test("the declared series cover everything the mapper reads")
    func wantedSeries() {
        var mapper = RemoteMapper(target: Self.target)
        let filtered = MetricSet(text: Self.fixture(), wanted: mapper.wants)
        let declared = mapper.snapshot(
            from: filtered, now: Self.captured, link: LinkStatus(state: .live)
        )
        #expect(declared == mapped())
    }

    // MARK: - Unified memory fold

    @Test("GPU-held memory is counted as in use, because no bucket counts it")
    func unifiedFold() {
        let memory = mapped().memory
        let gpuShared = Self.metrics.samples("homelab_gpu_memory_used_bytes")
            .reduce(UInt64(0)) { $0 + RemoteMapper.bytes($1.value) }
        #expect(memory.gpuShared == gpuShared)
        #expect(memory.gpuShared > 0)
        #expect(
            memory.inUse
                == memory.active + memory.wired + memory.compressed + memory.gpuShared
        )
    }

    @Test("used without total folds into memory but draws no card")
    func foldWithoutCard() {
        // The partial state the contract allows: a card is keyed on
        // `memory_total_bytes`, so without it the band stays empty, while
        // the fold sums `used` label-free and still raises the headline.
        let noTotal = MetricSet(
            PrometheusText.parse(Self.fixture())
                .filter { $0.name != "homelab_gpu_memory_total_bytes" }
        )
        var mapper = RemoteMapper(target: Self.target)
        let snapshot = mapper.snapshot(from: noTotal, now: Self.captured, link: LinkStatus(state: .live))
        let gpuShared = Self.metrics.samples("homelab_gpu_memory_used_bytes")
            .reduce(UInt64(0)) { $0 + RemoteMapper.bytes($1.value) }
        #expect(snapshot.gpus.isEmpty)
        #expect(snapshot.memory.gpuShared == gpuShared)
        #expect(snapshot.memory.gpuShared > 0)
    }

    @Test("non-finite or negative GPU memory contributes nothing")
    func unifiedFoldDiscardsNonFiniteValues() {
        let samples = Self.metrics.samples("homelab_gpu_memory_used_bytes").map { sample in
            MetricSample(name: sample.name, labels: sample.labels, value: -1)
        }
        let rest = PrometheusText.parse(Self.fixture()).filter {
            $0.name != "homelab_gpu_memory_used_bytes"
        }
        let poisoned = MetricSet(rest + samples)
        var mapper = RemoteMapper(target: Self.target)
        #expect(mapper.snapshot(from: poisoned, now: Self.captured, link: LinkStatus(state: .live)).memory.gpuShared == 0)
    }

    @Test("no GPU series on a unified host means no fold, not zero memory")
    func foldAbsentSeries() {
        let bare = MetricSet(
            PrometheusText.parse(Self.fixture())
                .filter { !$0.name.hasPrefix("homelab_gpu_") }
        )
        var mapper = RemoteMapper(target: Self.target)
        let snapshot = mapper.snapshot(from: bare, now: Self.captured, link: LinkStatus(state: .live))
        #expect(snapshot.gpus.isEmpty)
        #expect(snapshot.memory.gpuShared == 0)
        #expect(snapshot.memory.total > 120 << 30)
    }

    @Test("a discrete host folds nothing even when GPU series are present")
    func noUnifiedFoldOnDiscreteHosts() {
        // The gate is the target's declaration, never the series' presence:
        // mapped through ai-1's target, this fixture's GPU figures are
        // discrete VRAM that the card's own bar already accounts for.
        var mapper = RemoteMapper(target: TargetRegistry.homelabAI1.remote!)
        let snapshot = mapper.snapshot(from: Self.metrics, now: Self.captured, link: LinkStatus(state: .live))
        #expect(!snapshot.gpus.isEmpty)
        #expect(snapshot.memory.gpuShared == 0)
    }

    // MARK: - The lone GTT card

    @Test("reads one card from the GTT pool, not the VRAM carveout")
    func loneGpu() throws {
        let gpus = RemoteMapper(target: Self.target).gpus(from: Self.metrics)
        #expect(gpus.map(\.id) == [0])
        let gpu = try #require(gpus.first)
        #expect(gpu.memoryLabel == "GTT")
        // 128 GiB shared pool; the 512 MiB carveout would read 1 << 29.
        #expect(gpu.memoryTotal > 120 << 30)
        #expect(gpu.memoryUsed == Self.metrics.value("homelab_gpu_memory_used_bytes").map(RemoteMapper.bytes))
        #expect(gpu.utilization >= 0 && gpu.utilization <= 1)
        // This kernel's amdgpu publishes no power cap.
        #expect(gpu.wattLimit == 0)
        #expect(gpu.watts > 0)
        #expect(gpu.celsius == Self.metrics.value("homelab_gpu_temperature_celsius"))
    }
}
