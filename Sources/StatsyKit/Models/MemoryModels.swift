import Foundation

/// Raw page counts from `host_statistics64(HOST_VM_INFO64)`.
public struct VMCounters: Sendable, Equatable {
    public let free: UInt64
    public let active: UInt64
    public let inactive: UInt64
    public let speculative: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let pageSize: UInt64

    public init(
        free: UInt64, active: UInt64, inactive: UInt64, speculative: UInt64,
        wired: UInt64, compressed: UInt64, pageSize: UInt64
    ) {
        self.free = free
        self.active = active
        self.inactive = inactive
        self.speculative = speculative
        self.wired = wired
        self.compressed = compressed
        self.pageSize = pageSize
    }
}

public struct MemoryMetrics: Sendable, Equatable {
    public let total: UInt64
    public let used: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let active: UInt64
    public let inactive: UInt64
    public let unused: UInt64
    public let swapUsed: UInt64
    public let swapTotal: UInt64

    public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
    public var swapFraction: Double { swapTotal == 0 ? 0 : Double(swapUsed) / Double(swapTotal) }

    public init(
        total: UInt64, used: UInt64, wired: UInt64, compressed: UInt64,
        active: UInt64, inactive: UInt64, unused: UInt64,
        swapUsed: UInt64, swapTotal: UInt64
    ) {
        self.total = total
        self.used = used
        self.wired = wired
        self.compressed = compressed
        self.active = active
        self.inactive = inactive
        self.unused = unused
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
    }

    public static let zero = MemoryMetrics(
        total: 0, used: 0, wired: 0, compressed: 0, active: 0,
        inactive: 0, unused: 0, swapUsed: 0, swapTotal: 0
    )
}

public enum MemoryCalculator {
    /// Converts page counts into byte totals matching Activity Monitor.
    ///
    /// "Memory Used" is active + inactive + wired + compressed — everything but
    /// free and speculative. Omitting inactive under-reports by tens of GB.
    public static func metrics(
        _ counters: VMCounters,
        totalBytes: UInt64,
        swapUsed: UInt64 = 0,
        swapTotal: UInt64 = 0
    ) -> MemoryMetrics {
        let page = counters.pageSize
        let active = counters.active * page
        let inactive = counters.inactive * page
        let wired = counters.wired * page
        let compressed = counters.compressed * page

        return MemoryMetrics(
            total: totalBytes,
            used: active + inactive + wired + compressed,
            wired: wired,
            compressed: compressed,
            active: active,
            inactive: inactive,
            unused: (counters.free + counters.speculative) * page,
            swapUsed: swapUsed,
            swapTotal: swapTotal
        )
    }
}
