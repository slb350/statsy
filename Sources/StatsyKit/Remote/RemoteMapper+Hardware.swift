import Foundation

// Sensors and discrete graphics, which arrive from two different collectors at
// two different cadences.
extension RemoteMapper {
    /// hwmon chip names that identify a sensor's cluster.
    ///
    /// Matched on the chip's driver rather than its bus path: ai-1's
    /// Threadripper reports through `k10temp` where an Intel host reports
    /// through `coretemp`, and the path differs on every board.
    /// Deliberately no `acpitz`: ai-1's ACPI zone reports a steady 16.8 °C,
    /// which is not the temperature of anything. A desktop board's ACPI zones
    /// are frequently unconnected, and three honest clusters beat four with one
    /// that lies.
    static func cluster(forChip name: String) -> SensorCluster? {
        switch name {
        case "k10temp", "coretemp", "zenpower": .cpu
        case "nvme", "drivetemp": .storage
        default: nil
        }
    }

    /// Temperatures from hwmon, with the GPUs folded in from the fleet textfile.
    ///
    /// The two sources have to be joined: `node_hwmon_temp_celsius` labels a
    /// reading with an opaque chip path, and only `node_hwmon_chip_names` says
    /// what that chip is. Sensors on chips with no cluster — the wireless card,
    /// for one — are dropped rather than averaged into something unrelated.
    mutating func thermal(from metrics: MetricSet) -> ThermalMetrics {
        // hwmon paths and their drivers do not change without a reboot, so the
        // chip-to-cluster map is resolved once instead of re-joining two
        // metrics and re-running the driver switch on every scrape.
        let clusters = cachedSensorClusters ?? Self.sensorClusters(from: metrics)
        if !clusters.isEmpty { cachedSensorClusters = clusters }
        var grouped: [SensorCluster: [Double]] = [:]

        for sample in metrics.samples("node_hwmon_temp_celsius") {
            guard let chip = sample.labels["chip"], let cluster = clusters[chip]
            else { continue }
            grouped[cluster, default: []].append(sample.value)
        }

        let gpuTemperatures = metrics.samples(collector("gpu_temperature_celsius")).map(\.value)
        if !gpuTemperatures.isEmpty {
            grouped[.gpu] = gpuTemperatures
        }

        // No fan telemetry: ai-1's fans are board-controlled and the cabinet
        // fan belongs to a different host entirely.
        return ThermalCalculator.metrics(grouped: grouped)
    }

    /// Resolves each hwmon chip path to the cluster its readings belong to.
    static func sensorClusters(from metrics: MetricSet) -> [String: SensorCluster] {
        var result: [String: SensorCluster] = [:]
        for sample in metrics.samples("node_hwmon_chip_names") {
            guard let chip = sample.labels["chip"],
                  let name = sample.labels["chip_name"],
                  let cluster = cluster(forChip: name)
            else { continue }
            result[chip] = cluster
        }
        return result
    }

    /// One reading per discrete card, ordered by device index.
    ///
    /// Every field comes from the same `nvidia-smi` query, so a card missing
    /// from one series is missing from all of them; a card whose total VRAM is
    /// unreadable is dropped rather than drawn as an empty bar.
    func gpus(from metrics: MetricSet) -> [GPUReading] {
        func field(_ name: String) -> [String: Double] {
            metrics.grouped(collector("gpu_\(name)"), by: "gpu")
        }

        let utilization = field("utilization_percent")
        let used = field("memory_used_bytes")
        let total = field("memory_total_bytes")
        let watts = field("power_watts")
        let limits = field("power_limit_watts")
        let temperatures = field("temperature_celsius")

        return total.compactMap { key, size -> GPUReading? in
            guard let index = Int(key) else { return nil }
            let capacity = Self.bytes(size)
            guard capacity > 0 else { return nil }
            return GPUReading(
                id: index,
                utilization: (utilization[key] ?? 0) / 100,
                memoryUsed: used[key].map(Self.bytes) ?? 0,
                memoryTotal: capacity,
                watts: watts[key] ?? 0,
                wattLimit: limits[key] ?? 0,
                celsius: temperatures[key] ?? 0,
                memoryLabel: target.unifiedMemory ? "GTT" : "VRAM"
            )
        }
        .sorted { $0.id < $1.id }
    }
}
