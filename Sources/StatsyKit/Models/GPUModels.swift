import Foundation

/// One GPU, as the fleet collector reports it: nvidia-smi, a cached discrete
/// amdgpu sample, or the unified-memory amdgpu sysfs contract.
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

    /// Draw against the card's limit. amdgpu publishes no cap, so a card
    /// without one shows its draw alone rather than against a limit of zero.
    public var powerDescription: String {
        let draw = Format.decimal(watts, decimals: 0)
        return wattLimit > 0 ? "\(draw) / \(Format.decimal(wattLimit, decimals: 0)) W" : "\(draw) W"
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
