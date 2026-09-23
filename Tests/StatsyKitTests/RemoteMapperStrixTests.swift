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
    /// Just after the fixture's textfile stamp, so ages come out sane.
    static let captured = Date(timeIntervalSince1970: 1_790_196_803)

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
        // MemTotal, not the 128 GiB on the sticker.
        #expect(machine.memoryBytes > 120 << 30)
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

    @Test("finds the CPU package through k10temp and the NVMe through nvme")
    func hwmonClusters() throws {
        let cpu = try #require(mapped().thermal[.cpu])
        #expect(cpu.count >= 1)
        let storage = try #require(mapped().thermal[.storage])
        #expect(storage.count >= 1)
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
        // The WiFi NIC and the ACPI zone would drag an average somewhere
        // meaningless; strix has both, in quantity.
        #expect(mapped().thermal[.battery] == nil)
        #expect(mapped().thermal.fans.isEmpty)
    }

    // MARK: - Storage

    @Test("shows Root; Coldstore's capacity arrives with the collector")
    func volumes() throws {
        let volumes = mapped().storage.volumes
        // Deviation from the brief, see task-2-report.md: at capture time
        // the fleet collector's config lists only "/" in `filesystems`, so
        // the NFS automount publishes `homelab_mount_present` but no
        // capacity figures, and node_filesystem_* never sees the automount.
        // The mapper therefore shows Root alone; when the collector's
        // storage stage covers /mnt/coldstore this becomes ["Root", "Coldstore"].
        #expect(volumes.map(\.name) == ["Root"])
        let root = try #require(volumes.first)
        #expect(root.fraction >= 0 && root.fraction <= 1)
    }

    @Test("headline capacity covers local storage only")
    func capacityExcludesTheNAS() {
        let storage = mapped().storage
        // Root alone is ~915 GiB; BabyNas's coldstore must stay out of it.
        #expect(storage.total > 900 << 30)
        #expect(storage.total < 1 << 40)
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
        #expect(age >= 0 && age < 120)
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
