import Foundation

/// Turns monotonically increasing lifetime counters into per-second rates.
public enum RateCalculator {
    /// Bytes (or operations) per second between two counter readings.
    ///
    /// Returns zero rather than a negative or infinite rate when the counter has
    /// gone backwards (a device reattach resets it) or no time has elapsed.
    public static func rate(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / elapsed
    }
}
