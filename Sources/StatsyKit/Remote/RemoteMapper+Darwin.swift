import Foundation

// The readings that differ between a Linux exporter and a Darwin one. Each
// pane asks for its platform's version here, so the rest of the mapper never
// branches on the operating system.
extension RemoteMapper {
    func memory(from metrics: MetricSet) -> MemoryMetrics {
        switch target.platform {
        case .linux: linuxMemory(from: metrics)
        case .macOS: darwinMemory(from: metrics)
        }
    }

    func network(from metrics: MetricSet) -> NetworkMetrics {
        switch target.platform {
        case .linux: Self.linuxNetwork(from: metrics)
        case .macOS: Self.darwinNetwork(from: metrics)
        }
    }

    /// Series only one platform's readers use. A Linux host publishes the
    /// interface counters too, a dozen labelled series apiece, which its
    /// netstat totals make redundant.
    func platformWants(_ name: String) -> Bool {
        switch target.platform {
        case .linux: false
        case .macOS: Self.darwinNames.contains(name)
        }
    }

    private static let darwinNames: Set<String> = [
        "node_os_info",
        "node_network_receive_bytes_total", "node_network_transmit_bytes_total"
    ]

    /// The header's version: the kernel release on Linux, where it is what
    /// distinguishes one host from the next, and the product version on macOS,
    /// as the local header shows it.
    func osVersion(from metrics: MetricSet) -> String? {
        switch target.platform {
        case .linux: metrics.samples("node_uname_info").first?.labels["release"]
        case .macOS: metrics.samples("node_os_info").first?.labels["version"]
        }
    }

    /// Darwin memory, read into the buckets the local panel fills from
    /// `host_statistics64`.
    ///
    /// node_exporter's Darwin collector is that same call, page counts times
    /// the page size, so the local mapping applies unchanged: in use is
    /// active + wired + compressed, and inactive is reclaimable. The one
    /// difference is free, which here excludes speculative pages that the
    /// exporter does not publish.
    func darwinMemory(from metrics: MetricSet) -> MemoryMetrics {
        func value(_ name: String) -> UInt64 {
            metrics.value("node_memory_\(name)_bytes").map(Self.bytes) ?? 0
        }
        let active = value("active")
        let wired = value("wired")
        let compressed = value("compressed")
        return MemoryMetrics(
            total: value("total"),
            inUse: active + wired + compressed,
            wired: wired,
            compressed: compressed,
            active: active,
            reclaimable: value("inactive"),
            free: value("free"),
            swapUsed: value("swap_used"),
            swapTotal: value("swap_total")
        )
    }

    /// Totals over every interface but loopback, as the local IF-MIB read is.
    ///
    /// Darwin has no netstat collector, so the per-interface counters are the
    /// only source. They are 64-bit, unlike the `getifaddrs` counters the
    /// local source rejected: en0 on mac-mini-3 read 167 GB, matching
    /// `netstat -ib` to the byte.
    static func darwinNetwork(from metrics: MetricSet) -> NetworkMetrics {
        func total(_ name: String) -> UInt64 {
            metrics.samples(name).reduce(0) { sum, sample in
                guard let device = sample.labels["device"], !device.hasPrefix("lo") else {
                    return sum
                }
                return sum + bytes(sample.value)
            }
        }
        return NetworkMetrics(
            lifetimeIn: total("node_network_receive_bytes_total"),
            lifetimeOut: total("node_network_transmit_bytes_total")
        )
    }
}
