import Foundation

/// Turns one scrape into a `Snapshot`.
///
/// Pure transformation, in the same sense as the calculators: it performs no
/// I/O and holds only the previous counters it needs to difference against.
/// Everything host-specific it cannot read from the scrape — what the machine
/// is called, which mounts are worth showing — comes from the `RemoteTarget`.
public struct RemoteMapper: Sendable {
    let target: RemoteTarget

    var previousTicks: [CPUTicks] = []
    var previousIO: (read: UInt64, written: UInt64)?
    var lastSampledAt: Date?

    /// The last reading with a usable delta behind it.
    private var lastCPU: CPUMetrics?

    /// Facts that do not change between scrapes, kept from the first one.
    private var cachedMachine: MachineInfo?
    var cachedSensorClusters: [String: SensorCluster]?

    public init(target: RemoteTarget) {
        self.target = target
    }

    /// Parses a scrape into the series this mapper reads, as the panel and the
    /// renderer both do.
    public func metrics(from text: String) -> MetricSet {
        MetricSet(samples(from: text))
    }

    /// The wanted samples of one scrape, for a caller merging several.
    public func samples(from text: String) -> [MetricSample] {
        PrometheusText.parse(text, wanted: wants)
    }

    /// `processes` is ranked by the caller: the scrape carries no process
    /// telemetry, which arrives on its own stream.
    public mutating func snapshot(
        from metrics: MetricSet, now: Date, link: LinkStatus,
        processes: ProcessTable = .empty
    ) -> Snapshot {
        let metrics = scoped(metrics)
        let memory = memory(from: metrics)
        let elapsed = lastSampledAt.map { now.timeIntervalSince($0) } ?? 0
        lastSampledAt = now

        let ticks = Self.ticks(from: metrics)
        let cpu = cpu(from: ticks, loadAverage: Self.loadAverage(from: metrics))
        previousTicks = ticks
        let thermal = thermal(from: metrics)

        return Snapshot(
            machine: machine(from: metrics, memoryTotal: memory.total),
            cpu: cpu,
            memory: memory,
            storage: storage(from: metrics, elapsed: elapsed),
            thermal: thermal.metrics,
            processes: processes,
            network: network(from: metrics),
            gpus: gpus(from: metrics),
            services: services(from: metrics, now: now, usesCabinetTemperatures: thermal.usesCabinet),
            uptime: Self.uptime(from: metrics, now: now),
            link: link
        )
    }

    /// Drops fleet series published on behalf of other hosts.
    ///
    /// Legion's collector also publishes BabyNas's and DondeNas's storage,
    /// containers and timestamps under the same names. Read label-free, a
    /// panel pointed at Legion would count the NAS hosts' containers as its
    /// own and take whichever host's timestamp happened to come first.
    /// Series without the label, which is all of node_exporter's own, pass.
    func scoped(_ metrics: MetricSet) -> MetricSet {
        metrics.filter { sample in
            sample.labels["asset_host"].map { $0 == target.hostName } ?? true
        }
    }

    /// Utilisation, or the previous reading when this scrape cannot support one.
    ///
    /// A scrape that carries a different number of cores than the last leaves
    /// nothing to difference. Locally that cannot happen — the baseline is
    /// primed in `start()` and the core count is fixed hardware — but a
    /// truncated response can change it here, and `CPUCalculator` answers an
    /// unusable pair with an idle machine. Printing 0% busy beside a load
    /// average of 44, under a ribbon that says LIVE, is the kind of confident
    /// wrong answer this panel exists not to give. The next scrape re-baselines
    /// against the new count and recovers on its own.
    private mutating func cpu(from ticks: [CPUTicks], loadAverage: LoadAverage) -> CPUMetrics {
        if !previousTicks.isEmpty, ticks.count != previousTicks.count, let lastCPU {
            return CPUMetrics(
                user: lastCPU.user, system: lastCPU.system, idle: lastCPU.idle,
                cores: lastCPU.cores, loadAverage: loadAverage
            )
        }
        let metrics = CPUCalculator.metrics(
            previous: previousTicks, current: ticks, loadAverage: loadAverage
        )
        // The first scrape has no delta either; it is not worth carrying forward.
        if !metrics.cores.isEmpty { lastCPU = metrics }
        return metrics
    }

    /// The header facts, read from the first scrape and kept.
    ///
    /// `MachineInfo` is documented as static, and it is: kernel release, total
    /// memory and the target's own description do not move. Rebuilding it 30
    /// times a minute also rebuilt the two header strings it now precomputes.
    private mutating func machine(from metrics: MetricSet, memoryTotal: UInt64) -> MachineInfo {
        if let cachedMachine { return cachedMachine }
        let machine = MachineInfo(
            host: target.hostName,
            model: target.model,
            clusters: target.clusters,
            gpuDescription: target.gpuDescription,
            // The memory pane's own denominator: MemTotal on Linux, which
            // excludes firmware-reserved memory, rather than the sticker figure.
            memoryBytes: memoryTotal,
            ranksProcesses: target.ranksProcesses,
            processMemory: target.platform.processMemory,
            unifiedMemory: target.unifiedMemory,
            platform: target.platform.name,
            osVersion: osVersion(from: metrics) ?? ""
        )
        // Only kept once the scrape actually carried the host's identity; a
        // partial first response must not pin an empty header forever.
        if machine.memoryBytes > 0 { cachedMachine = machine }
        return machine
    }

    static func loadAverage(from metrics: MetricSet) -> LoadAverage {
        LoadAverage(
            one: metrics.value("node_load1") ?? 0,
            five: metrics.value("node_load5") ?? 0,
            fifteen: metrics.value("node_load15") ?? 0
        )
    }

    /// Host-wide IP byte counters.
    ///
    /// Not the per-interface `node_network_*_bytes_total` series, because ai-1's
    /// netdev collector fails and publishes none. These totals are what the
    /// panel shows anyway, and they come from the netstat collector instead.
    static func linuxNetwork(from metrics: MetricSet) -> NetworkMetrics {
        NetworkMetrics(
            lifetimeIn: metrics.value("node_netstat_IpExt_InOctets").map(Self.bytes) ?? 0,
            lifetimeOut: metrics.value("node_netstat_IpExt_OutOctets").map(Self.bytes) ?? 0
        )
    }

    static func uptime(from metrics: MetricSet, now: Date) -> TimeInterval {
        guard let boot = metrics.value("node_boot_time_seconds") else { return 0 }
        return max(0, now.timeIntervalSince1970 - boot)
    }

    /// Unit, container and endpoint health from the fleet collector's textfile.
    ///
    /// A Mac has LaunchAgents where Linux has systemd units, and the collector
    /// names them differently; loaded is the Mac's healthy state, since a
    /// periodic agent is not running between its runs.
    func services(from metrics: MetricSet, now: Date, usesCabinetTemperatures: Bool) -> ServiceHealth {
        let units = metrics.samples(collector("service_active"))
            + metrics.samples(collector("launchagent_loaded"))
        let containers = metrics.samples(collector("container_running"))
        let endpoints = metrics.samples(collector("service_http_ready"))
            .compactMap { sample -> EndpointReadiness? in
                guard let name = sample.labels["service"] else { return nil }
                return EndpointReadiness(name: name, ready: sample.value != 0)
            }
            .sorted { $0.name < $1.name }

        // The fleet textfile may contain a sample from the fan's earlier cycle.
        // Show the oldest contributing sample's age, not just the re-export time.
        var timestampNames = ["collection_timestamp_seconds", "gpu_sample_timestamp_seconds"]
        if usesCabinetTemperatures {
            timestampNames.append("cabinet_status_timestamp_seconds")
        }
        let timestamps = timestampNames
            .flatMap { metrics.samples(collector($0)).map(\.value) }
            .filter { $0.isFinite && $0 > 0 }
        let age = timestamps.min().map { max(0, now.timeIntervalSince1970 - $0) }

        return ServiceHealth(
            activeUnits: units.filter { $0.value != 0 }.count,
            totalUnits: units.count,
            runningContainers: containers.filter { $0.value != 0 }.count,
            totalContainers: containers.count,
            endpoints: endpoints,
            collectionAge: age
        )
    }

    /// node_exporter series this mapper reads by name.
    ///
    /// Handed to the parser so the rest of a scrape is recognised and dropped
    /// before its labels are parsed, which is most of the cost of a scrape.
    /// Names admitted by prefix are not listed here, so this is not the whole
    /// inventory; what guarantees nothing goes missing is
    /// `RemoteMapperTests.wantedSeries`, which maps a filtered scrape and an
    /// unfiltered one and requires the same answer.
    private static let wantedNames: Set<String> = [
        "node_cpu_seconds_total",
        "node_load1", "node_load5", "node_load15",
        "node_boot_time_seconds",
        "node_uname_info",
        "node_hwmon_temp_celsius", "node_hwmon_chip_names",
        "node_disk_read_bytes_total", "node_disk_written_bytes_total",
        "node_netstat_IpExt_InOctets", "node_netstat_IpExt_OutOctets",
        "node_filesystem_size_bytes", "node_filesystem_avail_bytes",
        "node_filesystem_free_bytes"
    ]

    public func wants(_ name: String) -> Bool {
        // The collector's textfile is read wholesale; it is small and its
        // contents are exactly what a target chooses to publish.
        Self.wantedNames.contains(name)
            || name.hasPrefix(target.collectorPrefix)
            || name.hasPrefix("node_memory_")
            || platformWants(name)
    }

    /// A fleet metric's full name for this target.
    func collector(_ suffix: String) -> String { target.collectorPrefix + suffix }

    /// Converts a counter to bytes, discarding the non-finite and negative
    /// values the exposition format permits but a byte total cannot hold.
    static func bytes(_ value: Double) -> UInt64 {
        guard value.isFinite, value > 0 else { return 0 }
        return UInt64(value)
    }
}
