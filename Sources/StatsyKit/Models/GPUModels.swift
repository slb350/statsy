import Foundation

/// One discrete GPU, as the fleet collector reports it: nvidia-smi on a discrete
/// host, the amdgpu sysfs contract on a unified one.
///
/// Apple silicon has no equivalent reading: its GPU shares system memory and
/// publishes neither a VRAM figure nor a board power draw, so a local snapshot
/// carries no cards at all rather than carrying empty ones.
public struct GPUReading: Sendable, Equatable, Identifiable {
    /// The collector's `gpu` label — the device index for nvidia-smi and the
    /// amdgpu stage alike.
    public let id: Int
    public let utilization: Double
    public let memoryUsed: UInt64
    public let memoryTotal: UInt64
    public let watts: Double
    public let wattLimit: Double
    public let celsius: Double
    /// What the memory figures are called on this card: `VRAM` on a discrete
    /// card, `GTT` where the GPU draws from system memory.
    public let memoryLabel: String

    public var memoryFraction: Double {
        .ratio(memoryUsed, of: memoryTotal)
    }

    public var powerFraction: Double {
        wattLimit == 0 ? 0 : watts / wattLimit
    }

    public init(
        id: Int, utilization: Double = 0,
        memoryUsed: UInt64 = 0, memoryTotal: UInt64 = 0,
        watts: Double = 0, wattLimit: Double = 0, celsius: Double = 0,
        memoryLabel: String = "VRAM"
    ) {
        self.id = id
        self.utilization = utilization
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.watts = watts
        self.wattLimit = wattLimit
        self.celsius = celsius
        self.memoryLabel = memoryLabel
    }
}
