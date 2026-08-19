import Foundation

/// Static facts about the machine, read once at startup.
public struct MachineInfo: Sendable, Equatable {
    public let model: String
    public let clusters: [CPUCluster]
    public let gpuCoreCount: Int?
    public let memoryBytes: UInt64
    public let osVersion: String

    public init(
        model: String = "", clusters: [CPUCluster] = [],
        gpuCoreCount: Int? = nil, memoryBytes: UInt64 = 0, osVersion: String = ""
    ) {
        self.model = model
        self.clusters = clusters
        self.gpuCoreCount = gpuCoreCount
        self.memoryBytes = memoryBytes
        self.osVersion = osVersion
    }

    /// The header line: "APPLE M5 MAX · 6S + 12P · 40-CORE GPU · 128 GB".
    public var summary: String {
        var parts = [model.uppercased()]
        if !clusters.isEmpty {
            parts.append(clusters.map { "\($0.coreCount)\($0.name.prefix(1).uppercased())" }
                .joined(separator: " + "))
        }
        if let gpuCoreCount { parts.append("\(gpuCoreCount)-CORE GPU") }
        parts.append("\(Format.gibibytes(memoryBytes)) GB")
        return parts.joined(separator: "  ·  ")
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
    public let uptime: TimeInterval

    public init(
        machine: MachineInfo = MachineInfo(),
        cpu: CPUMetrics = .zero,
        memory: MemoryMetrics = .zero,
        storage: StorageMetrics = .empty,
        thermal: ThermalMetrics = .empty,
        processes: ProcessTable = .empty,
        network: NetworkMetrics = .empty,
        uptime: TimeInterval = 0
    ) {
        self.machine = machine
        self.cpu = cpu
        self.memory = memory
        self.storage = storage
        self.thermal = thermal
        self.processes = processes
        self.network = network
        self.uptime = uptime
    }

    public static let placeholder = Snapshot()

    /// Uptime as the header shows it, e.g. "UP 29d 23h".
    public var uptimeDescription: String {
        let days = Int(uptime) / 86400
        let hours = (Int(uptime) % 86400) / 3600
        return days > 0 ? "UP \(days)d \(hours)h" : "UP \(hours)h"
    }
}
