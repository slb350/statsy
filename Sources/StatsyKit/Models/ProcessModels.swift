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

public struct ProcessTable: Sendable, Equatable {
    public let byCPU: [ProcessSample]
    public let byMemory: [ProcessSample]

    public init(byCPU: [ProcessSample] = [], byMemory: [ProcessSample] = []) {
        self.byCPU = byCPU
        self.byMemory = byMemory
    }

    public static let empty = ProcessTable()

    /// Builds the two orderings the panel shows from one sampled block.
    public static func ranked(_ samples: [ProcessSample], limit: Int) -> ProcessTable {
        ProcessTable(
            byCPU: Array(samples.sorted { $0.cpu > $1.cpu }.prefix(limit)),
            byMemory: Array(samples.sorted { $0.memory > $1.memory }.prefix(limit))
        )
    }
}
