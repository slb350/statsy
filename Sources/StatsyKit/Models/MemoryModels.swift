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
    public let inUse: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let active: UInt64
    public let reclaimable: UInt64
    public let free: UInt64
    public let swapUsed: UInt64
    public let swapTotal: UInt64

    public var inUseFraction: Double { total == 0 ? 0 : Double(inUse) / Double(total) }
    public var swapFraction: Double { swapTotal == 0 ? 0 : Double(swapUsed) / Double(swapTotal) }

    public init(
        total: UInt64, inUse: UInt64, wired: UInt64, compressed: UInt64,
        active: UInt64, reclaimable: UInt64, free: UInt64,
        swapUsed: UInt64, swapTotal: UInt64
    ) {
        self.total = total
        self.inUse = inUse
        self.wired = wired
        self.compressed = compressed
        self.active = active
        self.reclaimable = reclaimable
        self.free = free
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
    }

    public static let zero = MemoryMetrics(
        total: 0, inUse: 0, wired: 0, compressed: 0, active: 0,
        reclaimable: 0, free: 0, swapUsed: 0, swapTotal: 0
    )
}

public enum MemoryCalculator {
    /// Converts page counts into byte totals for Statsy's pressure-oriented display.
    ///
    /// "In use" is active + wired + compressed. Inactive pages are kept as a
    /// separate reclaimable bucket so inactive memory does not inflate the
    /// headline percentage. These VM buckets can fall slightly short of
    /// installed RAM, so the three displayed categories are not forced to sum.
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
            inUse: active + wired + compressed,
            wired: wired,
            compressed: compressed,
            active: active,
            reclaimable: inactive,
            free: (counters.free + counters.speculative) * page,
            swapUsed: swapUsed,
            swapTotal: swapTotal
        )
    }
}
