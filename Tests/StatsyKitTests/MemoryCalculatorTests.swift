import Testing
@testable import StatsyKit

@Suite("MemoryCalculator")
struct MemoryCalculatorTests {
    /// Page counts captured from this machine alongside a `top` reading of
    /// "114G used ... 13G unused", which is what these figures must reproduce.
    private let measured = VMCounters(
        free: 540_789,
        active: 3_214_251,
        inactive: 2_913_091,
        speculative: 300_899,
        wired: 473_841,
        compressed: 882_088,
        pageSize: 16384
    )
    private let installed: UInt64 = 137_438_953_472
    private var metrics: MemoryMetrics { MemoryCalculator.metrics(measured, totalBytes: installed) }

    @Test("counts inactive pages as used, matching Activity Monitor")
    func matchesActivityMonitor() {
        // active + inactive + wired + compressed
        #expect(metrics.used == 122_605_912_064)
        #expect(Format.gibibytes(metrics.used) == "114")
    }

    @Test("counts free and speculative pages as unused")
    func unusedIsFreePlusSpeculative() {
        #expect(metrics.unused == 13_790_216_192)
        #expect(Format.gibibytes(metrics.unused) == "13")
    }

    @Test("used and unused very nearly account for installed memory")
    func partitionsInstalledMemory() {
        // vm_stat's buckets do not perfectly partition physical memory: about a
        // gibibyte sits outside them. `top` shows the same shortfall (114G used
        // + 13G unused against 128G installed), so a strict equality here would
        // be asserting something untrue of the kernel rather than of our maths.
        let accounted = metrics.used + metrics.unused
        #expect(accounted < installed)
        #expect(Double(installed - accounted) / Double(installed) < 0.015)
    }

    @Test("excluding inactive pages would badly under-report")
    func inactiveIsNotOptional() {
        let withoutInactive = metrics.active + metrics.wired + metrics.compressed
        // The gap is ~44 GiB — the bug this test exists to prevent.
        #expect(metrics.used - withoutInactive > 45_000_000_000)
    }

    @Test("reports the used fraction")
    func usedFraction() {
        #expect(abs(metrics.usedFraction - 0.892) < 0.001)
    }

    @Test("reports swap pressure")
    func swapPressure() {
        let metrics = MemoryCalculator.metrics(
            measured, totalBytes: installed,
            swapUsed: 11_584_684_032, swapTotal: 12_884_901_888
        )
        #expect(abs(metrics.swapFraction - 0.899) < 0.001)
    }

    @Test("does not divide by zero when totals are unknown")
    func toleratesZeroTotals() {
        let metrics = MemoryCalculator.metrics(measured, totalBytes: 0)
        #expect(metrics.usedFraction == 0)
        #expect(metrics.swapFraction == 0)
    }
}
