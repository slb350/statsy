import Foundation

// CPU, memory and storage: the three panes whose arithmetic differs most
// between a Mach host and a Linux one.
extension RemoteMapper {
    // Hoisted out of the per-core loop, where the literals allocated four
    // arrays per core on every scrape.
    static let userModes = ["user"]
    static let systemModes = ["system", "irq", "softirq", "steal"]
    static let idleModes = ["idle", "iowait"]
    static let niceModes = ["nice"]

    /// Per-core counters, converted to the jiffies the tick calculator expects.
    ///
    /// `node_cpu_seconds_total` is jiffies divided by USER_HZ, so multiplying
    /// by 100 recovers the integer counter exactly. Reusing `CPUCalculator`
    /// rather than writing a second one keeps one tested implementation of the
    /// busy-share arithmetic, including its wrap-safe differencing.
    static func ticks(from metrics: MetricSet) -> [CPUTicks] {
        var byCore: [Int: [String: Double]] = [:]
        for sample in metrics.samples("node_cpu_seconds_total") {
            guard let core = sample.labels["cpu"].flatMap(Int.init),
                  let mode = sample.labels["mode"]
            else { continue }
            byCore[core, default: [:]][mode] = sample.value
        }

        // Sorted pairs rather than sorted keys: looking each core back up
        // costs 48 redundant hashes per scrape for entries the sort already has.
        return byCore.sorted { $0.key < $1.key }.map { _, modes in
            func jiffies(_ names: [String]) -> UInt32 {
                let seconds = names.reduce(0.0) { $0 + (modes[$1] ?? 0) }
                guard seconds.isFinite, seconds > 0 else { return 0 }
                return UInt32(truncatingIfNeeded: Int64(seconds * 100))
            }
            return CPUTicks(
                // Interrupt time is kernel time; iowait is a core with nothing
                // to run, which is what idle means here.
                user: jiffies(Self.userModes),
                system: jiffies(Self.systemModes),
                idle: jiffies(Self.idleModes),
                nice: jiffies(Self.niceModes)
            )
        }
    }

    /// Linux memory, expressed in the same four buckets the panel shows.
    ///
    /// `In use = active + wired + compressed` holds here exactly as it does on
    /// macOS; only the contents of each bucket are platform-specific. Anonymous
    /// and shared pages are what a process actually occupies, unreclaimable
    /// kernel memory is the closest thing Linux has to wired, and zswap is its
    /// compressor. Page cache is reported as reclaimable so an 80 GiB model
    /// sitting in cache does not read as memory pressure.
    ///
    /// On a unified-memory target, GPU-held memory joins in use as its own
    /// category, because no /proc/meminfo bucket contains it.
    func memory(from metrics: MetricSet) -> MemoryMetrics {
        func value(_ name: String) -> UInt64 {
            metrics.value("node_memory_\(name)_bytes").map(Self.bytes) ?? 0
        }

        let shared = value("Shmem")
        let active = value("AnonPages") + shared
        let wired = value("SUnreclaim") + value("KernelStack")
            + value("PageTables") + value("Percpu")
        let compressed = value("Zswap")

        // Shmem is counted inside Cached but cannot be dropped, so it is
        // removed here rather than counted in both buckets.
        let cached = value("Cached") + value("Buffers") + value("SReclaimable")
        let reclaimable = cached > shared ? cached - shared : 0

        let swapTotal = value("SwapTotal")
        let swapFree = value("SwapFree")

        // A unified host's model memory never reaches these buckets, so it
        // is added rather than mapped: the GTT pool holds what the GPU has
        // taken of system memory, and in use must include it to be true.
        var gpuShared: UInt64 = 0
        if target.unifiedMemory {
            gpuShared = metrics.samples(collector("gpu_memory_used_bytes"))
                .reduce(UInt64(0)) { $0 + Self.bytes($1.value) }
        }

        return MemoryMetrics(
            total: value("MemTotal"),
            inUse: active + wired + compressed + gpuShared,
            wired: wired,
            compressed: compressed,
            active: active,
            gpuShared: gpuShared,
            reclaimable: reclaimable,
            free: value("MemFree"),
            swapUsed: swapTotal > swapFree ? swapTotal - swapFree : 0,
            swapTotal: swapTotal
        )
    }

    /// Capacity for the target's listed mounts, plus throughput for its disk.
    ///
    /// Two sources, in that order of preference. `node_filesystem_*` is what
    /// `df` reads, and it alone separates space reserved for root from space
    /// genuinely in use — taking the reserve as used puts this host 4 GiB above
    /// what `df` reports for its root volume. The fleet collector's figures
    /// fill in what node_exporter cannot see: `/mnt/nas-storage` is an
    /// automount that materialises only when something touches it, and the
    /// collector touches it on every run.
    ///
    /// The headline figures cover local storage alone, so a NAS with room to
    /// spare cannot disguise a full NVMe.
    mutating func storage(from metrics: MetricSet, elapsed: TimeInterval) -> StorageMetrics {
        var volumes: [VolumeUsage] = []
        var total: UInt64 = 0
        var free: UInt64 = 0

        for volume in target.volumes {
            let mount = ["mountpoint": volume.mountPoint]
            // Looked up directly rather than through a grouped dictionary: a
            // Linux host mounts dozens of filesystems and only three are shown,
            // so indexing them all to read three keys is wasted work.
            func reading(_ name: String, _ fallback: String) -> UInt64? {
                (metrics.value(name, mount) ?? metrics.value(fallback, mount)).map(Self.bytes)
            }

            guard let size = reading("node_filesystem_size_bytes", collector("storage_size_bytes")),
                  size > 0,
                  let spare = reading(
                      "node_filesystem_avail_bytes", collector("storage_available_bytes")
                  )
            else { continue }

            // Space the filesystem is holding, which on ext4 is less than
            // capacity minus what a user may write.
            let occupied = metrics.value("node_filesystem_free_bytes", mount)
                .map(Self.bytes) ?? spare

            volumes.append(
                VolumeUsage(
                    role: volume.role, name: volume.name,
                    used: size > occupied ? size - occupied : 0, total: size
                )
            )
            if volume.role != .network {
                total += size
                free += spare
            }
        }

        let read = metrics.value("node_disk_read_bytes_total", ["device": target.diskDevice])
            .map(Self.bytes) ?? 0
        let written = metrics.value("node_disk_written_bytes_total", ["device": target.diskDevice])
            .map(Self.bytes) ?? 0
        defer { previousIO = (read: read, written: written) }

        var readRate = 0.0
        var writeRate = 0.0
        if let previousIO {
            readRate = RateCalculator.rate(
                previous: previousIO.read, current: read, elapsed: elapsed
            )
            writeRate = RateCalculator.rate(
                previous: previousIO.written, current: written, elapsed: elapsed
            )
        }

        return StorageMetrics(
            total: total, used: total > free ? total - free : 0, free: free,
            lifetimeRead: read, lifetimeWritten: written,
            readRate: readRate, writeRate: writeRate, volumes: volumes
        )
    }
}
