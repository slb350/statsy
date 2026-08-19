import Foundation

public struct ThermalSensor: Sendable, Equatable {
    public let key: String
    public let celsius: Double

    public init(key: String, celsius: Double) {
        self.key = key
        self.celsius = celsius
    }
}

/// The sensor groups the panel reports, identified by SMC key prefix.
public enum SensorCluster: String, Sendable, CaseIterable {
    case cpu, gpu, storage, battery, enclosure

    public var label: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .storage: "SSD"
        case .battery: "Battery"
        case .enclosure: "Enclosure"
        }
    }
}

public struct ClusterReading: Sendable, Equatable {
    public let average: Double
    public let minimum: Double
    public let maximum: Double
    public let count: Int

    public init(average: Double, minimum: Double, maximum: Double, count: Int) {
        self.average = average
        self.minimum = minimum
        self.maximum = maximum
        self.count = count
    }
}

public struct ThermalMetrics: Sendable, Equatable {
    public let clusters: [SensorCluster: ClusterReading]
    public let fans: [FanReading]

    public init(clusters: [SensorCluster: ClusterReading] = [:], fans: [FanReading] = []) {
        self.clusters = clusters
        self.fans = fans
    }

    public static let empty = ThermalMetrics()

    public subscript(cluster: SensorCluster) -> ClusterReading? { clusters[cluster] }
}

public struct FanReading: Sendable, Equatable, Identifiable {
    public let id: Int
    public let actual: Double
    public let maximum: Double

    public var fraction: Double { maximum > 0 ? actual / maximum : 0 }

    public init(id: Int, actual: Double, maximum: Double) {
        self.id = id
        self.actual = actual
        self.maximum = maximum
    }
}

public enum ThermalCalculator {
    /// Plausible range for a real temperature sensor, in Celsius.
    ///
    /// The SMC exposes hundreds of keys and some read as 0 or as absurd values
    /// when the sensor is absent or unpowered; averaging those in drags a
    /// cluster reading badly off.
    static let plausibleRange: ClosedRange<Double> = 1...150

    /// Maps an SMC key to the cluster it belongs to, or nil if we do not chart it.
    public static func cluster(for key: String) -> SensorCluster? {
        guard key.count >= 2 else { return nil }
        switch key.prefix(2) {
        case "Tp": return .cpu
        case "Tg": return .gpu
        case "TH": return .storage
        case "TB": return .battery
        case "Ts": return .enclosure
        default: return nil
        }
    }

    /// Averages sensors into per-cluster readings, discarding implausible values.
    public static func metrics(_ sensors: [ThermalSensor], fans: [FanReading] = []) -> ThermalMetrics {
        var grouped: [SensorCluster: [Double]] = [:]
        for sensor in sensors {
            guard plausibleRange.contains(sensor.celsius),
                  let cluster = cluster(for: sensor.key)
            else { continue }
            grouped[cluster, default: []].append(sensor.celsius)
        }

        var clusters: [SensorCluster: ClusterReading] = [:]
        for (cluster, values) in grouped where !values.isEmpty {
            clusters[cluster] = ClusterReading(
                average: values.reduce(0, +) / Double(values.count),
                minimum: values.min() ?? 0,
                maximum: values.max() ?? 0,
                count: values.count
            )
        }
        return ThermalMetrics(clusters: clusters, fans: fans)
    }
}
