import Foundation
import Testing
@testable import StatsyKit

/// The mapper, exercised against a scrape homelab-ai-1 actually produced.
///
/// Fixture-driven rather than hand-built: the readings that break a mapper are
/// the ones nobody would think to write down — an automount node_exporter
/// cannot see, a failed collector, a Threadripper reporting through a driver
/// no Intel host uses.
@Suite("Remote mapper")
struct RemoteMapperTests {
    static let metrics = MetricSet(text: fixture())
    static let target = TargetRegistry.homelabAI1.remote!
    /// Close to when the fixture was captured, so ages come out sane.
    static let captured = Date(timeIntervalSince1970: 1_789_943_990)

    static func fixture() -> String {
        let url = Bundle.module.url(
            forResource: "homelab-ai-1", withExtension: "prom", subdirectory: "Fixtures"
        )
        return (try? String(contentsOf: url!, encoding: .utf8)) ?? ""
    }

    private func mapped() -> Snapshot {
        var mapper = RemoteMapper(target: Self.target)
        return mapper.snapshot(from: Self.metrics, now: Self.captured, link: LinkStatus(state: .live))
    }

    @Test("the fixture parses")
    func fixtureLoads() {
        // 48 threads across the eight modes Linux reports.
        #expect(Self.metrics.samples("node_cpu_seconds_total").count == 384)
    }

    // MARK: - CPU

    @Test("reads all 48 threads")
    func coreCount() {
        #expect(RemoteMapper.ticks(from: Self.metrics).count == 48)
    }

    @Test("the first sample has no baseline to difference against")
    func firstSampleIsIdle() {
        // Matches the local engine: with no previous ticks there is nothing to
        // report, and inventing a busy figure from a lifetime total is exactly
        // the `top` mistake the parser already guards against.
        #expect(mapped().cpu.cores.isEmpty)
    }

    @Test("derives utilisation once a second scrape arrives")
    func secondSample() {
        var mapper = RemoteMapper(target: Self.target)
        _ = mapper.snapshot(from: Self.metrics, now: Self.captured, link: .local)

        // One core spends the whole second in user time; the rest stay idle.
        var samples = Self.metrics.samples("node_cpu_seconds_total")
        for index in samples.indices where samples[index].labels == ["cpu": "0", "mode": "user"] {
            samples[index] = MetricSample(
                name: samples[index].name,
                labels: samples[index].labels,
                value: samples[index].value + 1
            )
        }
        for index in samples.indices where samples[index].labels["mode"] == "idle"
            && samples[index].labels["cpu"] != "0" {
            samples[index] = MetricSample(
                name: samples[index].name,
                labels: samples[index].labels,
                value: samples[index].value + 1
            )
        }

        let next = mapper.snapshot(
            from: MetricSet(samples), now: Self.captured.addingTimeInterval(1), link: .local
        )
        #expect(next.cpu.cores.count == 48)
        #expect(next.cpu.cores[0].busy == 1.0)
        #expect(next.cpu.cores[1].busy == 0.0)
    }

    @Test("a scrape with a different core count carries the last reading forward")
    func coreCountChange() {
        var mapper = RemoteMapper(target: Self.target)
        _ = mapper.snapshot(from: Self.metrics, now: Self.captured, link: .local)

        // One core busy for a second, so there is a real reading to hold on to.
        var busy = Self.metrics.samples("node_cpu_seconds_total")
        for index in busy.indices where busy[index].labels == ["cpu": "0", "mode": "user"] {
            busy[index] = MetricSample(
                name: busy[index].name, labels: busy[index].labels, value: busy[index].value + 1
            )
        }
        let good = mapper.snapshot(
            from: MetricSet(busy), now: Self.captured.addingTimeInterval(1), link: .local
        )
        #expect(good.cpu.cores.count == 48)

        // A scrape that lost some cores has no delta to offer. Reporting an
        // idle machine would contradict the load average printed beside it.
        let truncated = MetricSet(busy.filter { $0.labels["cpu"] != "47" })
        let next = mapper.snapshot(
            from: truncated, now: Self.captured.addingTimeInterval(2), link: .local
        )
        #expect(next.cpu.cores.count == 48)
        #expect(next.cpu.busy == good.cpu.busy)
    }

    @Test("reads the load average")
    func loadAverage() {
        let load = mapped().cpu.loadAverage
        #expect(load.one == 0)
        #expect(load.five == 0.01)
        #expect(load.fifteen == 1.05)
    }

    // MARK: - Memory

    @Test("in use is active plus wired plus compressed, as it is on macOS")
    func memoryInvariant() {
        let memory = mapped().memory
        #expect(memory.inUse == memory.active + memory.wired + memory.compressed)
    }

    @Test("page cache is reclaimable, not pressure")
    func cacheIsNotPressure() {
        let memory = mapped().memory
        // 80 GiB of the model sits in page cache. Counting it as in use would
        // show this idle host at 85% memory.
        #expect(memory.reclaimable > 70 << 30)
        #expect(memory.inUseFraction < 0.3)
    }

    @Test("the three buckets do not exceed installed memory")
    func memoryDoesNotOverCount() {
        let memory = mapped().memory
        #expect(memory.inUse + memory.reclaimable + memory.free <= memory.total)
    }

    @Test("reads swap")
    func swap() {
        let memory = mapped().memory
        #expect(memory.swapTotal > 8_000_000_000)
        // Nothing is swapped out on this host, which is the point of checking.
        #expect(memory.swapUsed < 1 << 20)
    }

    // MARK: - Storage

    @Test("shows every configured mount, including the one node_exporter cannot see")
    func volumes() {
        let volumes = mapped().storage.volumes
        #expect(volumes.map(\.name) == ["Root", "Srv", "NAS"])
        // /mnt/nas-storage is an automount and absent from node_filesystem_*.
        #expect(volumes.last?.total ?? 0 > 10 << 40)
    }

    @Test("does not count a filesystem's reserved blocks as used")
    func reservedBlocks() throws {
        let root = try #require(mapped().storage.volumes.first)
        // `df -h /` reports 33G used of 98G. Taking capacity minus what a user
        // may write instead would report 37 GiB, because ext4 holds back 5% for
        // root that `df` counts as neither used nor available.
        #expect(root.used < 35 << 30)
        #expect(root.used > 30 << 30)
    }

    @Test("falls back to the collector for a mount node_exporter cannot see")
    func automountFallback() throws {
        // node_filesystem_* has no series for /mnt/nas-storage at all.
        #expect(Self.metrics.grouped("node_filesystem_size_bytes", by: "mountpoint")["/mnt/nas-storage"] == nil)
        let nas = try #require(mapped().storage.volumes.last)
        #expect(nas.name == "NAS")
        #expect(nas.fraction > 0.7)
    }

    @Test("volumes stay distinct now that they are keyed by name")
    func volumeIdentity() {
        let volumes = mapped().storage.volumes
        #expect(Set(volumes.map(\.id)).count == volumes.count)
    }

    @Test("headline capacity covers local storage only")
    func capacityExcludesTheNAS() {
        let storage = mapped().storage
        // Root plus /srv, around 2 TB. A 12 TB NAS in the total would make a
        // full NVMe look like plenty of room.
        #expect(storage.total > 1 << 40)
        #expect(storage.total < 3 << 40)
    }

    @Test("reads throughput counters from the physical disk, not its mappers")
    func diskCounters() {
        let storage = mapped().storage
        #expect(storage.lifetimeRead > 200_000_000_000)
        #expect(storage.lifetimeWritten > 3_000_000_000_000)
        // No baseline yet, so no rate is claimed.
        #expect(storage.readRate == 0)
    }

    // MARK: - Thermal

    @Test("finds the CPU package through k10temp rather than a fixed chip path")
    func cpuTemperature() throws {
        let cpu = try #require(mapped().thermal[.cpu])
        #expect(cpu.count == 5)
        #expect(cpu.average > 30 && cpu.average < 45)
    }

    @Test("reads NVMe temperature")
    func storageTemperature() throws {
        let storage = try #require(mapped().thermal[.storage])
        #expect(storage.average > 30 && storage.average < 60)
    }

    @Test("averages the three GPUs into one cluster reading")
    func gpuTemperature() throws {
        let gpu = try #require(mapped().thermal[.gpu])
        #expect(gpu.count == 3)
        #expect(gpu.minimum == 35)
        #expect(gpu.maximum == 38)
    }

    @Test("drops sensors that belong to no cluster")
    func unrelatedSensors() {
        // The wireless card publishes through iwlwifi and would otherwise drag
        // an average somewhere meaningless.
        #expect(mapped().thermal[.battery] == nil)
    }

    @Test("reports no fans, because this host publishes none")
    func noFans() {
        #expect(mapped().thermal.fans.isEmpty)
    }

    // MARK: - GPU

    @Test("reads three cards in device order")
    func gpuOrder() {
        #expect(mapped().gpus.map(\.id) == [0, 1, 2])
    }

    @Test("reads VRAM, the reading this panel exists to show")
    func vram() throws {
        let first = try #require(mapped().gpus.first)
        #expect(first.memoryTotal == 21_474_836_480)
        #expect(first.memoryUsed == 19_649_265_664)
        #expect(first.memoryFraction > 0.9)
    }

    @Test("reads utilisation as a fraction, power against its limit, and temperature")
    func gpuFields() throws {
        let first = try #require(mapped().gpus.first)
        #expect(first.utilization == 0)
        #expect(first.wattLimit == 250)
        #expect(first.powerFraction < 0.1)
        #expect(first.celsius == 38)
    }

    // MARK: - Services and identity

    @Test("counts units and reads endpoint readiness")
    func services() {
        let services = mapped().services
        // Sixteen services. The oneshot backup reports as a job, not a unit.
        #expect(services.totalUnits == 16)
        #expect(services.allUnitsActive)
        #expect(services.endpoints == [EndpointReadiness(name: "qwen3.8-27b", ready: true)])
    }

    @Test("reports how old the collector's run is")
    func collectionAge() throws {
        let age = try #require(mapped().services.collectionAge)
        // The textfile updates once a minute, so the panel must be able to say so.
        #expect(age >= 0 && age < 120)
    }

    @Test("names the platform from the kernel rather than assuming macOS")
    func identity() {
        let machine = mapped().machine
        #expect(machine.host == "homelab-ai-1")
        #expect(machine.platformVersion == "Linux 7.0.0-31-generic")
        #expect(machine.summary.contains("3 × RTX 3080 20 GB".uppercased()))
        // MemTotal, not the 128 GiB on the invoice.
        #expect(machine.memoryBytes > 120 << 30)
    }

    @Test("reads host-wide traffic, since the netdev collector is failing")
    func network() {
        #expect(Self.metrics.value("node_scrape_collector_success", ["collector": "netdev"]) == 0)
        let network = mapped().network
        #expect(network.lifetimeIn > 10_000_000_000)
        #expect(network.lifetimeOut > 6_000_000_000)
    }

    @Test("reads uptime from boot time")
    func uptime() {
        let uptime = mapped().uptime
        #expect(uptime > 15 * 3600 && uptime < 17 * 3600)
    }

    @Test("carries no process table, because node_exporter publishes none")
    func noProcesses() {
        #expect(mapped().processes == .empty)
    }

    // MARK: - Degradation

    @Test("an empty scrape maps to empty readings rather than crashing")
    func emptyScrape() {
        var mapper = RemoteMapper(target: Self.target)
        let snapshot = mapper.snapshot(
            from: MetricSet([]), now: Self.captured, link: LinkStatus(state: .down)
        )
        #expect(snapshot.gpus.isEmpty)
        #expect(snapshot.memory.total == 0)
        #expect(snapshot.storage.volumes.isEmpty)
        #expect(snapshot.uptime == 0)
    }

    @Test("the declared series cover everything the mapper reads")
    func wantedSeries() {
        // A name the mapper reads but does not declare would be filtered out
        // of a live scrape and silently never arrive, while the fixture — which
        // is parsed unfiltered — would go on passing every other test here.
        var mapper = RemoteMapper(target: Self.target)
        let filtered = MetricSet(text: Self.fixture(), wanted: mapper.wants)
        let declared = mapper.snapshot(
            from: filtered, now: Self.captured, link: LinkStatus(state: .live)
        )
        #expect(declared == mapped())
    }

    @Test("fleet metrics are read through the target's collector prefix")
    func collectorPrefix() {
        // A host whose collector publishes under another namespace must read as
        // absent rather than silently drawing an empty band.
        var renamed = RemoteMapper(target: RemoteTarget(
            sshUser: Self.target.sshUser, sshHost: Self.target.sshHost,
            exporterHost: Self.target.exporterHost, localPort: Self.target.localPort,
            hostName: Self.target.hostName, model: Self.target.model,
            volumes: Self.target.volumes, diskDevice: Self.target.diskDevice,
            collectorPrefix: "fleet_"
        ))
        let snapshot = renamed.snapshot(
            from: Self.metrics, now: Self.captured, link: LinkStatus(state: .live)
        )
        #expect(snapshot.gpus.isEmpty)
        #expect(snapshot.services.isEmpty)
        // node_exporter's own series are unaffected by the collector's naming.
        #expect(snapshot.memory.total > 0)
        #expect(!mapped().gpus.isEmpty)
    }

    @Test("a card missing its capacity is dropped rather than drawn empty")
    func partialGPU() {
        let samples = Self.metrics.samples("homelab_gpu_memory_used_bytes")
            + Self.metrics.samples("homelab_gpu_temperature_celsius")
        #expect(RemoteMapper(target: Self.target).gpus(from: MetricSet(samples)).isEmpty)
    }
}
