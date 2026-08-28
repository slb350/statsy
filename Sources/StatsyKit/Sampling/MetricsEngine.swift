import Foundation

/// Owns every sampler and produces one `Snapshot` per refresh.
///
/// All syscalls happen on the actor's executor, never on the main thread, so a
/// slow SMC read cannot stutter the panel. The engine is deliberately cheap:
/// a monitor that distorts the machine it measures is worse than no monitor.
public actor MetricsEngine {
    private let host = HostSource()
    private let storage = StorageSource()
    private let network = NetworkSource()
    private let processes: any ProcessSource

    /// Built in `start()`, not `init`: enumerating SMC keys costs about half a
    /// second, and `init` runs synchronously on whichever thread constructs the
    /// engine — the main one, before the window appears.
    private var smc: SMCReader?
    private var machine = MachineInfo()
    private var bootDate = Date()

    private var previousTicks: [CPUTicks] = []
    private var previousIO: (read: UInt64, written: UInt64)?
    private var lastSampledAt: Date?

    /// Temperatures move on a thermal time constant, and reading all 130
    /// sensors costs 17ms of blocked hardware wait. Sampling them at the panel's
    /// 1 Hz would spend 85% of the app's CPU budget re-reading numbers that have
    /// not changed.
    private static let thermalInterval: TimeInterval = 5

    /// Rows shown in each pane's process list.
    private static let processLimit = 5
    private var thermal = ThermalMetrics.empty
    private var thermalSampledAt: Date?

    public init(processes: any ProcessSource = TopProcessSource()) {
        self.processes = processes
    }

    /// Primes the tick baseline and starts the process stream.
    ///
    /// Without a baseline the first sample would have nothing to difference
    /// against and would report zero utilisation.
    public func start() async {
        smc = SMCReader()
        machine = MachineSource().read(host: host)
        bootDate = Date(timeIntervalSinceNow: -host.uptime())
        previousTicks = host.cpuTicks()
        previousIO = storage.lifetimeBytes()
        lastSampledAt = Date()
        await processes.start()
    }

    public func stop() async {
        await processes.stop()
    }

    public func sample() async -> Snapshot {
        let now = Date()
        let elapsed = lastSampledAt.map { now.timeIntervalSince($0) } ?? 0
        lastSampledAt = now

        let ticks = host.cpuTicks()
        let cpu = CPUCalculator.metrics(
            previous: previousTicks, current: ticks, loadAverage: host.loadAverage()
        )
        previousTicks = ticks

        return Snapshot(
            machine: machine,
            cpu: cpu,
            memory: sampleMemory(),
            storage: sampleStorage(elapsed: elapsed),
            thermal: sampleThermal(now: now),
            processes: ProcessTable.ranked(await processes.current(), limit: Self.processLimit),
            network: network.read(),
            uptime: now.timeIntervalSince(bootDate)
        )
    }

    private func sampleMemory() -> MemoryMetrics {
        guard let counters = host.vmCounters() else { return .zero }
        let swap = host.swapUsage()
        return MemoryCalculator.metrics(
            counters, totalBytes: host.physicalMemory,
            swapUsed: swap.used, swapTotal: swap.total
        )
    }

    private func sampleStorage(elapsed: TimeInterval) -> StorageMetrics {
        let capacity = storage.capacity()
        let ioCounters = storage.lifetimeBytes()
        defer { previousIO = ioCounters }

        var readRate = 0.0
        var writeRate = 0.0
        if let previousIO {
            readRate = RateCalculator.rate(
                previous: previousIO.read, current: ioCounters.read, elapsed: elapsed
            )
            writeRate = RateCalculator.rate(
                previous: previousIO.written, current: ioCounters.written, elapsed: elapsed
            )
        }

        return StorageMetrics(
            total: capacity.total, used: capacity.used, free: capacity.free,
            lifetimeRead: ioCounters.read, lifetimeWritten: ioCounters.written,
            readRate: readRate, writeRate: writeRate, volumes: capacity.volumes
        )
    }

    private func sampleThermal(now: Date) -> ThermalMetrics {
        guard let smc else { return .empty }
        if let thermalSampledAt, now.timeIntervalSince(thermalSampledAt) < Self.thermalInterval {
            return thermal
        }
        thermalSampledAt = now
        thermal = ThermalCalculator.metrics(smc.sensors(), fans: smc.fans())
        return thermal
    }
}
