import Foundation

/// A machine the panel can be pointed at.
public struct Target: Sendable, Equatable, Identifiable {
    public let id: String
    /// What the menu calls it.
    public let name: String
    public let source: Source

    public enum Source: Sendable, Equatable {
        case local
        case remote(RemoteTarget)
    }

    public init(id: String, name: String, source: Source) {
        self.id = id
        self.name = name
        self.source = source
    }

    public var remote: RemoteTarget? {
        guard case .remote(let target) = source else { return nil }
        return target
    }
}

/// One volume the panel should show for a remote target.
///
/// Listed explicitly rather than discovered: a Linux host mounts a dozen
/// filesystems that mean nothing on a glanceable panel, and the role is a
/// decision about what a mount is for, which the mount table cannot answer.
public struct RemoteVolume: Sendable, Equatable {
    public let mountPoint: String
    public let name: String
    public let role: VolumeRole

    public init(mountPoint: String, name: String, role: VolumeRole) {
        self.mountPoint = mountPoint
        self.name = name
        self.role = role
    }
}

/// The operating system a remote target runs, which decides how its exporter's
/// series are read and which `top` it streams.
///
/// node_exporter publishes different families on each: `/proc/meminfo` fields
/// and netstat totals on Linux, Mach VM buckets and per-interface counters on
/// Darwin. Declared rather than read from `node_uname_info`, so a scrape that
/// arrives without it still maps as the right platform.
public enum RemotePlatform: Sendable, Equatable {
    case linux
    case macOS

    /// The node_exporter collectors behind every series the mapper reads,
    /// bar capacity. Naming one an exporter has not enabled makes it answer
    /// 400, which the panel reports, rather than silently omitting a reading.
    ///
    /// Linux: `stat` publishes the boot time and `netstat` the IP totals.
    /// Darwin: `boottime` and `os` stand in for those, and `netdev` for the
    /// totals.
    var liveCollectors: [String] {
        switch self {
        case .linux:
            ["cpu", "loadavg", "stat", "uname", "hwmon", "diskstats", "netstat", "meminfo", "textfile"]
        case .macOS:
            ["cpu", "loadavg", "boottime", "uname", "os", "diskstats", "netdev", "meminfo", "textfile"]
        }
    }

    /// Read on the slower capacity cadence.
    var capacityCollectors: [String] { ["filesystem"] }

    /// What the header calls it.
    public var name: String {
        switch self {
        case .linux: "Linux"
        case .macOS: "macOS"
        }
    }
}

/// Everything needed to reach a host's node_exporter and read it correctly.
public struct RemoteTarget: Sendable, Equatable {
    public let sshUser: String
    public let sshHost: String
    /// Where node_exporter listens, addressed as the target host sees it.
    ///
    /// Not necessarily loopback: ai-1's exporter binds its LAN address
    /// specifically, so a forward to `127.0.0.1:9100` there connects to nothing.
    public let exporterHost: String
    public let exporterPort: Int
    /// This end of the tunnel, on loopback.
    public let localPort: Int
    public let platform: RemotePlatform

    /// The host's name in the header, and the `asset_host` label its own fleet
    /// metrics carry.
    ///
    /// One string for both because the fleet names hosts the way the panel
    /// should. The label is what matters: Legion's collector also publishes the
    /// NAS hosts' series, and only this tells them apart.
    public let hostName: String
    /// Header facts the exporter does not publish.
    public let model: String
    public let gpuDescription: String?
    /// Core groups in core-index order, for the grid's dividers. Empty for
    /// uniform cores; node_exporter publishes no performance levels.
    public let clusters: [CPUCluster]

    public let volumes: [RemoteVolume]
    /// The block devices whose counters drive the throughput readout. Named
    /// rather than summed over everything, which would count each write again
    /// for every LVM mapper stacked on top of a disk.
    public let diskDevices: [String]
    /// Namespace of the fleet collector's textfile metrics. Everything else
    /// host-specific already comes from here; leaving this one hard-coded in
    /// the mapper meant a host with a differently-prefixed collector would draw
    /// no GPUs and no services, with nothing reporting why.
    public let collectorPrefix: String

    /// Whether the GPU draws from system memory rather than its own VRAM.
    ///
    /// A unified-memory host serves models out of the GTT pool, which
    /// `/proc/meminfo` reports in no bucket at all: with 89 GiB of model
    /// resident, the buckets read 7 GiB in use. Declared rather than inferred
    /// from a series' presence, because homelab-ai-1 publishes GPU memory
    /// figures too — discrete VRAM its own card already accounts for.
    public let unifiedMemory: Bool

    /// Whether the panel streams `top` from this host to rank its processes.
    ///
    /// node_exporter publishes no per-process series, so the lists come over
    /// a second SSH session instead. Declared, like `unifiedMemory`, and
    /// carried into `MachineInfo.ranksProcesses`, which is all the views ask.
    public let ranksProcesses: Bool

    /// Collectors deliberately disabled on this host. Requesting even one
    /// disabled collector makes node_exporter reject the entire scrape.
    public let disabledCollectors: Set<String>

    var liveCollectors: [String] {
        platform.liveCollectors.filter { !disabledCollectors.contains($0) }
    }

    public init(
        sshUser: String, sshHost: String,
        exporterHost: String, exporterPort: Int = 9100, localPort: Int,
        platform: RemotePlatform = .linux,
        hostName: String, model: String, gpuDescription: String? = nil,
        clusters: [CPUCluster] = [],
        volumes: [RemoteVolume], diskDevices: [String],
        collectorPrefix: String = "homelab_", unifiedMemory: Bool = false,
        ranksProcesses: Bool = true, disabledCollectors: Set<String> = []
    ) {
        self.sshUser = sshUser
        self.sshHost = sshHost
        self.exporterHost = exporterHost
        self.exporterPort = exporterPort
        self.localPort = localPort
        self.platform = platform
        self.hostName = hostName
        self.model = model
        self.gpuDescription = gpuDescription
        self.clusters = clusters
        self.volumes = volumes
        self.diskDevices = diskDevices
        self.collectorPrefix = collectorPrefix
        self.unifiedMemory = unifiedMemory
        self.ranksProcesses = ranksProcesses
        self.disabledCollectors = disabledCollectors
    }

    public var metricsURL: URL? {
        URL(string: "http://127.0.0.1:\(localPort)/metrics")
    }

    /// The forwarded endpoint asked for only `collectors`, by node_exporter's
    /// own `collect[]` filter, so the host does not run the dozens of
    /// collectors whose series the mapper would throw away.
    func scrapeURL(collectors: [String]) -> URL? {
        guard let base = metricsURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = collectors.map { URLQueryItem(name: "collect[]", value: $0) }
        return components.url
    }

    /// `user@host`, as both SSH sessions address it.
    var sshDestination: String { "\(sshUser)@\(sshHost)" }
}
