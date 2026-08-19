import Testing
@testable import StatsyKit

@Suite("ThermalCalculator")
struct ThermalCalculatorTests {
    @Test("maps SMC key prefixes to the clusters the panel shows")
    func mapsKnownPrefixes() {
        #expect(ThermalCalculator.cluster(for: "Tp0C") == .cpu)
        #expect(ThermalCalculator.cluster(for: "Tg0f") == .gpu)
        #expect(ThermalCalculator.cluster(for: "TH0x") == .storage)
        #expect(ThermalCalculator.cluster(for: "TB1T") == .battery)
        #expect(ThermalCalculator.cluster(for: "Ts0S") == .enclosure)
    }

    @Test("ignores keys outside the clusters we chart")
    func ignoresUnknownPrefixes() {
        // The SMC exposes hundreds of keys; TCMb and TVDP are real ones we do
        // not attribute to a cluster, and must not silently land in another.
        #expect(ThermalCalculator.cluster(for: "TCMb") == nil)
        #expect(ThermalCalculator.cluster(for: "TVDP") == nil)
        #expect(ThermalCalculator.cluster(for: "") == nil)
        #expect(ThermalCalculator.cluster(for: "T") == nil)
    }

    @Test("averages a real CPU sensor cluster")
    func averagesRealCluster() throws {
        // The 23 Tp sensors as captured from this machine.
        let readings = [
            60.4, 59.3, 58.9, 60.4, 59.7, 58.9, 60.3, 59.4, 59.3, 60.8, 60.3, 60.0,
            58.5, 58.7, 59.0, 58.8, 59.2, 59.0, 57.6, 58.6, 58.8, 58.6, 57.9,
        ]
        let sensors = readings.enumerated().map {
            ThermalSensor(key: "Tp0\($0.offset)", celsius: $0.element)
        }
        let cpu = try #require(ThermalCalculator.metrics(sensors)[.cpu])
        #expect(cpu.count == 23)
        #expect(abs(cpu.average - 59.24) < 0.01)
        #expect(cpu.minimum == 57.6)
        #expect(cpu.maximum == 60.8)
    }

    @Test("keeps clusters separate")
    func separatesClusters() throws {
        let sensors = [
            ThermalSensor(key: "Tp01", celsius: 70),
            ThermalSensor(key: "Tp02", celsius: 72),
            ThermalSensor(key: "Tg01", celsius: 60),
        ]
        let metrics = ThermalCalculator.metrics(sensors)
        #expect(metrics[.cpu]?.average == 71)
        #expect(metrics[.gpu]?.average == 60)
        #expect(metrics[.storage] == nil)
    }

    @Test("discards implausible sensor readings before averaging")
    func discardsImplausibleReadings() throws {
        // A dead or unpowered sensor reads 0; including it would drag a 70C
        // cluster down to 35C and make the panel lie.
        let sensors = [
            ThermalSensor(key: "Tp01", celsius: 70),
            ThermalSensor(key: "Tp02", celsius: 0),
            ThermalSensor(key: "Tp03", celsius: 4000),
        ]
        let cpu = try #require(ThermalCalculator.metrics(sensors)[.cpu])
        #expect(cpu.count == 1)
        #expect(cpu.average == 70)
    }

    @Test("reports no cluster when every sensor in it was discarded")
    func dropsEmptyClusters() {
        let sensors = [ThermalSensor(key: "Tp01", celsius: 0)]
        #expect(ThermalCalculator.metrics(sensors)[.cpu] == nil)
    }

    @Test("reports fan speed as a fraction of maximum")
    func fanFraction() {
        // Both fans on this machine idle at about a quarter of their ceiling.
        let fan = FanReading(id: 0, actual: 1350, maximum: 5349)
        #expect(abs(fan.fraction - 0.2524) < 0.001)
        #expect(FanReading(id: 1, actual: 1461, maximum: 0).fraction == 0)
    }
}

@Suite("RateCalculator")
struct RateCalculatorTests {
    @Test("derives a per-second rate from two lifetime counters")
    func derivesRate() {
        // Real lifetime read counter, advanced by one second of 44 KiB writes.
        let rate = RateCalculator.rate(
            previous: 13_975_069_499_392, current: 13_975_069_544_448, elapsed: 1
        )
        #expect(abs(rate - 45056) < 0.001)
    }

    @Test("scales by the elapsed interval")
    func scalesByInterval() {
        #expect(RateCalculator.rate(previous: 0, current: 1000, elapsed: 2) == 500)
    }

    @Test("returns zero when the counter goes backwards")
    func handlesCounterReset() {
        #expect(RateCalculator.rate(previous: 5000, current: 10, elapsed: 1) == 0)
    }

    @Test("returns zero rather than dividing by a zero interval")
    func handlesZeroInterval() {
        #expect(RateCalculator.rate(previous: 0, current: 1000, elapsed: 0) == 0)
        #expect(RateCalculator.rate(previous: 0, current: 1000, elapsed: -1) == 0)
    }
}
