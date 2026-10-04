import Foundation

public struct ProcessSample: Sendable, Equatable, Identifiable {
    public let id: Int32
    public let name: String
    /// Percentage of a single core, as `top` reports it. May exceed 100.
    public let cpu: Double
    public let memory: UInt64

    public init(id: Int32, name: String, cpu: Double, memory: UInt64) {
        self.id = id
        self.name = name
        self.cpu = cpu
        self.memory = memory
    }
}

/// What a process source's memory figure measures. Not the same quantity on
/// each platform, so not the same caption.
public enum ProcessMemory: Sendable, Equatable {
    /// macOS `top`'s MEM: the physical footprint, compressed pages included.
    case footprint
    /// procps' RES: pages resident in RAM.
    case resident
}

public struct ProcessTable: Sendable, Equatable {
    public let byCPU: [ProcessSample]
    public let byMemory: [ProcessSample]

    public init(byCPU: [ProcessSample] = [], byMemory: [ProcessSample] = []) {
        self.byCPU = byCPU
        self.byMemory = byMemory
    }

    public static let empty = ProcessTable()

    /// Rows shown in each pane's process list, on every target.
    public static let shownRows = 5

    /// Builds the two orderings the panel shows from one sampled block.
    public static func ranked(_ samples: [ProcessSample], limit: Int = shownRows) -> ProcessTable {
        ProcessTable(
            byCPU: Array(samples.sorted { $0.cpu > $1.cpu }.prefix(limit)),
            byMemory: Array(samples.sorted { $0.memory > $1.memory }.prefix(limit))
        )
    }
}
