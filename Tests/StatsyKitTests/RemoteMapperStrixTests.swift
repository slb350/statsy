import Foundation
import Testing
@testable import StatsyKit

/// The strix target, exercised against a scrape the host actually produced.
///
/// Strix is the unified-memory shape: a Strix Halo serving a model out of a
/// GTT pool `/proc/meminfo` does not see, with GPU figures arriving from the
/// fleet collector's amdgpu-stage contract pinned into this fixture. The
/// readings that break here are the ones ai-1 cannot produce — a lone GPU
/// whose memory is system memory, an NFS automount, GPU temperature arriving
/// from the textfile beside an amdgpu hwmon chip the cluster map must ignore.
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
    func identity() {
        let machine = mapped().machine
        #expect(machine.host == "strix")
        #expect(machine.platformVersion == "Linux 7.0.0-34-generic")
        #expect(machine.summary.contains("RADEON 8060S 128 GB (UNIFIED)"))
        // MemTotal, not the 128 GiB on the sticker — the fixture's own value.
        #expect(machine.memoryBytes == UInt64(Self.metrics.value("node_memory_MemTotal_bytes") ?? 0))
        #expect(!machine.ranksProcesses)
    }

    // MARK: - Memory buckets (the GPU fold arrives in a later task)

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

    @Test("shows Root; Coldstore's capacity arrives with the collector")
    func volumes() throws {
        let volumes = mapped().storage.volumes
        // The deployed collector on strix lists only "/" in its `filesystems`
        // config, so the NFS automount publishes `homelab_mount_present` but
        // no capacity figures, and node_filesystem_* never sees the automount.
        // The mapper therefore shows Root alone; when the collector's storage
        // stage covers /mnt/coldstore this becomes ["Root", "Coldstore"].
        #expect(volumes.map(\.name) == ["Root"])
        let root = try #require(volumes.first)
        #expect(root.fraction >= 0 && root.fraction <= 1)
    }

    @Test("headline capacity covers local storage only")
    func capacityExcludesTheNAS() {
        let storage = mapped().storage
        // Byte-exact: the headline is the fixture's own root filesystem size,
        // and BabyNas's coldstore cannot leak into it.
        let rootSize = Self.metrics.value("node_filesystem_size_bytes", ["mountpoint": "/"]) ?? 0
        #expect(storage.total == RemoteMapper.bytes(rootSize))
        // The declared /mnt/coldstore automount carries no capacity series in
        // this fixture (the collector's `filesystems` lists only "/"), so it
        // must be skipped rather than shown.
        #expect(!storage.volumes.contains { $0.name == "Coldstore" })
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
}
