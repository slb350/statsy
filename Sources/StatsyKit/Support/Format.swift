import Foundation

/// Display formatting for metric values.
///
/// Every helper is a pure function so the panel's text can be verified without
/// touching the sampling layer.
public enum Format {
    private static let binaryUnits = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
    private static let rateUnits = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s", "PB/s"]

    /// Scales a byte count into its largest whole unit.
    private static func scaled(_ value: Double) -> (value: Double, unit: Int) {
        var value = max(0, value)
        var unit = 0
        while value >= 1024, unit < binaryUnits.count - 1 {
            value /= 1024
            unit += 1
        }
        return (value, unit)
    }

    /// Formats a byte count using binary (1024-based) units, e.g. `1.25 TiB`.
    public static func binary(_ bytes: UInt64, decimals: Int = 1) -> String {
        let (value, unit) = scaled(Double(bytes))
        return "\(decimal(value, decimals: unit == 0 ? 0 : decimals)) \(binaryUnits[unit])"
    }

    /// A used-of-total pair, e.g. `18.3 GiB / 20.0 GiB`.
    public static func binary(_ used: UInt64, of total: UInt64) -> String {
        "\(binary(used)) / \(binary(total))"
    }

    /// Whole gibibytes, as the panel shows memory ("70 / 128 GB").
    public static func gibibytes(_ bytes: UInt64) -> String {
        decimal(Double(bytes) / 1_073_741_824, decimals: 0)
    }

    /// A throughput reading scaled to a sensible unit, e.g. `44 KB/s`.
    public static func rate(_ bytesPerSecond: Double) -> String {
        let (value, unit) = scaled(bytesPerSecond)
        return "\(decimal(value, decimals: unit == 0 ? 0 : 1)) \(rateUnits[unit])"
    }

    /// A 0...1 fraction rendered as a percentage number without the sign.
    public static func percent(_ fraction: Double, decimals: Int = 1) -> String {
        decimal(fraction * 100, decimals: decimals)
    }

    /// An age in its largest whole unit, e.g. `42s`, `14m`, `9d`, so a reading
    /// gone stale for days fits where a seconds count was laid out.
    public static func age(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds))
        return switch whole {
        case ..<60: "\(whole)s"
        case ..<3600: "\(whole / 60)m"
        case ..<86400: "\(whole / 3600)h"
        default: "\(whole / 86400)d"
        }
    }

    /// A fixed-precision decimal. The one place the panel formats a number.
    public static func decimal(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }
}
