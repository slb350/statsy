import Testing
@testable import StatsyKit

@Suite("CPUCalculator")
struct CPUCalculatorTests {
    private let load = LoadAverage(one: 4.98, five: 6.85, fifteen: 5.68)

    @Test("derives per-core and aggregate utilisation from tick deltas")
    func derivesUtilisation() {
        let previous = [
            CPUTicks(user: 100, system: 50, idle: 850, nice: 0),
            CPUTicks(user: 0, system: 0, idle: 0, nice: 0),
        ]
        let current = [
            CPUTicks(user: 200, system: 100, idle: 1700, nice: 0),
            CPUTicks(user: 500, system: 0, idle: 500, nice: 0),
        ]
        let metrics = CPUCalculator.metrics(previous: previous, current: current, loadAverage: load)

        #expect(metrics.cores.count == 2)
        #expect(abs(metrics.cores[0].busy - 0.15) < 0.0001)
        #expect(abs(metrics.cores[1].busy - 0.5) < 0.0001)
        #expect(abs(metrics.user - 0.3) < 0.0001)
        #expect(abs(metrics.system - 0.025) < 0.0001)
        #expect(abs(metrics.idle - 0.675) < 0.0001)
        #expect(metrics.loadAverage == load)
    }

    @Test("counts nice time as busy rather than idle")
    func niceIsBusy() {
        let previous = [CPUTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let current = [CPUTicks(user: 0, system: 0, idle: 900, nice: 100)]
        let metrics = CPUCalculator.metrics(previous: previous, current: current, loadAverage: load)
        #expect(abs(metrics.cores[0].busy - 0.1) < 0.0001)
    }

    @Test("survives 32-bit counter wraparound")
    func survivesWraparound() {
        // The kernel's tick counters are UInt32 and wrap; a naive subtraction
        // would trap or produce a nonsense delta on a long-running machine.
        let previous = [CPUTicks(user: UInt32.max - 10, system: 0, idle: 0, nice: 0)]
        let current = [CPUTicks(user: 9, system: 0, idle: 80, nice: 0)]
        let metrics = CPUCalculator.metrics(previous: previous, current: current, loadAverage: load)
        #expect(abs(metrics.cores[0].busy - 0.2) < 0.0001)
    }

    @Test("returns zero when no ticks elapsed instead of dividing by zero")
    func handlesNoElapsedTicks() {
        let sample = [CPUTicks(user: 10, system: 10, idle: 10, nice: 0)]
        let metrics = CPUCalculator.metrics(previous: sample, current: sample, loadAverage: load)
        #expect(metrics.cores[0].busy == 0)
        #expect(metrics.busy == 0)
    }

    @Test("returns zero when core counts disagree")
    func handlesMismatchedCoreCounts() {
        let previous = [CPUTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let current = [
            CPUTicks(user: 1, system: 1, idle: 1, nice: 0),
            CPUTicks(user: 1, system: 1, idle: 1, nice: 0),
        ]
        let metrics = CPUCalculator.metrics(previous: previous, current: current, loadAverage: load)
        #expect(metrics.cores.isEmpty)
    }
}
