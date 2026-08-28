import Foundation

/// What a volume is for. Decouples display labels from decisions about them.
public enum VolumeRole: Sendable, Equatable {
    case data
    case swap
    case system
}

public struct VolumeUsage: Sendable, Equatable, Identifiable {
    public var id: VolumeRole { role }
    public let role: VolumeRole
    public let name: String
    public let used: UInt64
    public let total: UInt64

    public var fraction: Double { total == 0 ? 0 : Double(used) / Double(total) }

    public init(role: VolumeRole, name: String, used: UInt64, total: UInt64) {
        self.role = role
        self.name = name
        self.used = used
        self.total = total
    }
}

public struct StorageCapacity: Sendable, Equatable {
    public let total: UInt64
    public let used: UInt64
    public let free: UInt64
    public let volumes: [VolumeUsage]

    public init(total: UInt64, used: UInt64, free: UInt64, volumes: [VolumeUsage]) {
        self.total = total
        self.used = used
        self.free = free
        self.volumes = volumes
    }
}

public struct StorageMetrics: Sendable, Equatable {
    public let total: UInt64
    public let used: UInt64
    public let free: UInt64
    /// Lifetime byte counters from the block storage driver.
    public let lifetimeRead: UInt64
    public let lifetimeWritten: UInt64
    /// Instantaneous throughput derived from consecutive lifetime readings.
    public let readRate: Double
    public let writeRate: Double
    public let volumes: [VolumeUsage]

    public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }

    public init(
        total: UInt64 = 0, used: UInt64 = 0, free: UInt64 = 0,
        lifetimeRead: UInt64 = 0, lifetimeWritten: UInt64 = 0,
        readRate: Double = 0, writeRate: Double = 0, volumes: [VolumeUsage] = []
    ) {
        self.total = total
        self.used = used
        self.free = free
        self.lifetimeRead = lifetimeRead
        self.lifetimeWritten = lifetimeWritten
        self.readRate = readRate
        self.writeRate = writeRate
        self.volumes = volumes
    }

    public static let empty = StorageMetrics()
}
