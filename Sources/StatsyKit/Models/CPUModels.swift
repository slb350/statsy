import Foundation

/// Raw per-core tick counters as reported by the kernel.
///
/// These are 32-bit and wrap around, which the delta arithmetic must survive.
public struct CPUTicks: Sendable, Equatable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public struct LoadAverage: Sendable, Equatable {
    public let one: Double
    public let five: Double
    public let fifteen: Double

    public init(one: Double, five: Double, fifteen: Double) {
        self.one = one
        self.five = five
        self.fifteen = fifteen
    }
}

public struct CoreLoad: Sendable, Equatable, Identifiable {
    public let id: Int
    /// Busy share of this core over the sampling window, 0...1.
    public let busy: Double

    public init(id: Int, busy: Double) {
        self.id = id
        self.busy = busy
    }
}

/// A named group of cores, as reported by `hw.perflevelN.*`.
public struct CPUCluster: Sendable, Equatable {
    public let name: String
    public let coreCount: Int

    public init(name: String, coreCount: Int) {
        self.name = name
        self.coreCount = coreCount
    }
}

public struct CPUMetrics: Sendable, Equatable {
    public let user: Double
    public let system: Double
    public let idle: Double
    public let cores: [CoreLoad]
    public let loadAverage: LoadAverage

    public var busy: Double { user + system }

    public init(user: Double, system: Double, idle: Double, cores: [CoreLoad], loadAverage: LoadAverage) {
        self.user = user
        self.system = system
        self.idle = idle
        self.cores = cores
        self.loadAverage = loadAverage
    }

    public static let zero = CPUMetrics(
        user: 0, system: 0, idle: 1, cores: [],
        loadAverage: LoadAverage(one: 0, five: 0, fifteen: 0)
    )
}

public enum CPUCalculator {
    /// Derives utilisation from two tick samples.
    ///
    /// Returns `.zero` when the samples are unusable (mismatched core counts, or
    /// no elapsed ticks) rather than dividing by zero.
    public static func metrics(
        previous: [CPUTicks],
        current: [CPUTicks],
        loadAverage: LoadAverage
    ) -> CPUMetrics {
        guard !current.isEmpty, previous.count == current.count else { return .zero }

        var cores: [CoreLoad] = []
        cores.reserveCapacity(current.count)
        var totalBusy = 0.0
        var totalUser = 0.0
        var totalSystem = 0.0
        var totalIdle = 0.0

        for index in current.indices {
            let user = Double(current[index].user &- previous[index].user)
            let system = Double(current[index].system &- previous[index].system)
            let nice = Double(current[index].nice &- previous[index].nice)
            let idle = Double(current[index].idle &- previous[index].idle)

            let busy = user + system + nice
            let total = busy + idle
            cores.append(CoreLoad(id: index, busy: total > 0 ? busy / total : 0))

            totalUser += user + nice
            totalSystem += system
            totalIdle += idle
            totalBusy += total
        }

        guard totalBusy > 0 else {
            return CPUMetrics(user: 0, system: 0, idle: 1, cores: cores, loadAverage: loadAverage)
        }
        return CPUMetrics(
            user: totalUser / totalBusy,
            system: totalSystem / totalBusy,
            idle: totalIdle / totalBusy,
            cores: cores,
            loadAverage: loadAverage
        )
    }
}
