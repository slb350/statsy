import Foundation

/// Static facts about the machine, read once at startup.
public struct MachineInfo: Sendable, Equatable {
    /// The target's hostname, shown when the panel is not looking at this Mac.
    /// Empty locally, where naming the machine the panel is running on adds
    /// nothing.
    public let host: String
    public let model: String
    public let clusters: [CPUCluster]
    /// The graphics segment of the header, already worded: "40-core GPU" on
    /// Apple silicon, "3 × RTX 3080 20 GB" on a host with discrete cards.
    /// One field rather than two mutually exclusive ones, so no call site has
    /// to choose a spelling and no reader has to learn which wins.
    public let gpuDescription: String?
    public let memoryBytes: UInt64
    /// Whether this target can rank processes.
    ///
    /// Stated by the source rather than inferred from the target being remote:
    /// `ProcessSource` is a seam, and a future privileged helper or a Linux
    /// process collector must be able to turn this on without the views
    /// learning anything new.
    public let ranksProcesses: Bool
    /// "macOS" or "Linux". Named so the header does not have to assume.
    public let platform: String
    public let osVersion: String

    /// The header line: "APPLE M5 MAX · 6S + 12P · 40-CORE GPU · 128 GB".
    ///
    /// Built once here rather than computed per read: the header redraws with
    /// every sample, and none of what goes into this changes between them.
    public let summary: String
    /// The operating system as the header shows it, e.g. "macOS 15.2".
    public let platformVersion: String

    public init(
        host: String = "", model: String = "", clusters: [CPUCluster] = [],
        gpuDescription: String? = nil, memoryBytes: UInt64 = 0,
        ranksProcesses: Bool = false,
        platform: String = "macOS", osVersion: String = ""
    ) {
        self.host = host
        self.model = model
        self.clusters = clusters
        self.gpuDescription = gpuDescription
        self.memoryBytes = memoryBytes
        self.ranksProcesses = ranksProcesses
        self.platform = platform
        self.osVersion = osVersion

        var parts: [String] = []
        if !host.isEmpty { parts.append(host.uppercased()) }
        parts.append(model.uppercased())
        if !clusters.isEmpty {
            parts.append(clusters.map { "\($0.coreCount)\($0.name.prefix(1).uppercased())" }
                .joined(separator: " + "))
        }
        if let gpuDescription { parts.append(gpuDescription.uppercased()) }
        parts.append("\(Format.gibibytes(memoryBytes)) GB")
        summary = parts.joined(separator: "  ·  ")
        platformVersion = osVersion.isEmpty ? platform : "\(platform) \(osVersion)"
    }
}

/// One complete reading of the machine, as rendered by the panel.
public struct Snapshot: Sendable, Equatable {
    public let machine: MachineInfo
    public let cpu: CPUMetrics
    public let memory: MemoryMetrics
    public let storage: StorageMetrics
    public let thermal: ThermalMetrics
    public let processes: ProcessTable
    public let network: NetworkMetrics
    /// Discrete GPUs. Empty on Apple silicon, which publishes no equivalent.
    public let gpus: [GPUReading]
    /// Unit and endpoint health. Empty unless the target publishes it.
    public let services: ServiceHealth
    public let uptime: TimeInterval
    public let link: LinkStatus

    public init(
        machine: MachineInfo = MachineInfo(),
        cpu: CPUMetrics = .zero,
        memory: MemoryMetrics = .zero,
        storage: StorageMetrics = .empty,
        thermal: ThermalMetrics = .empty,
        processes: ProcessTable = .empty,
        network: NetworkMetrics = .empty,
        gpus: [GPUReading] = [],
        services: ServiceHealth = .empty,
        uptime: TimeInterval = 0,
        link: LinkStatus = .local
    ) {
        self.machine = machine
        self.cpu = cpu
        self.memory = memory
        self.storage = storage
        self.thermal = thermal
        self.processes = processes
        self.network = network
        self.gpus = gpus
        self.services = services
        self.uptime = uptime
        self.link = link
    }

    public static let placeholder = Snapshot()

    /// The same readings, relabelled with a new link state.
    ///
    /// Rebuilding the whole value to change one field means every field added
    /// later has to be remembered in the stale path, where forgetting one
    /// silently blanks that section of the panel.
    public func marking(_ link: LinkStatus) -> Snapshot {
        Snapshot(
            machine: machine, cpu: cpu, memory: memory, storage: storage,
            thermal: thermal, processes: processes, network: network,
            gpus: gpus, services: services, uptime: uptime, link: link
        )
    }

    /// Uptime as the header shows it, e.g. "UP 29d 23h".
    public var uptimeDescription: String {
        let days = Int(uptime) / 86400
        let hours = (Int(uptime) % 86400) / 3600
        return days > 0 ? "UP \(days)d \(hours)h" : "UP \(hours)h"
    }
}
