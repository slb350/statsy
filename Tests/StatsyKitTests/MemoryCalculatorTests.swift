import Testing
@testable import StatsyKit

@Suite("MemoryCalculator")
struct MemoryCalculatorTests {
    /// Page counts captured from this machine alongside a `top` reading of
    /// "114G used ... 13G unused". Statsy's headline intentionally differs from
    /// `top`: inactive pages are reclaimable and do not count as in use.
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

    @Test("excludes reclaimable inactive pages from in-use memory")
    func excludesReclaimableMemory() {
        // active + wired + compressed; inactive is reported separately.
        #expect(metrics.inUse == 74_877_829_120)
        #expect(Format.gibibytes(metrics.inUse) == "70")
    }

    @Test("counts free and speculative pages as free")
    func freeIncludesSpeculative() {
        #expect(metrics.free == 13_790_216_192)
        #expect(Format.gibibytes(metrics.free) == "13")
    }

    @Test("in-use, reclaimable, and free memory nearly account for installed memory")
    func partitionsInstalledMemory() {
        // vm_stat's buckets do not perfectly partition physical memory: about a
        // gibibyte sits outside them. `top` shows the same shortfall (114G used
        // + 13G unused against 128G installed), so a strict equality here would
        // be asserting something untrue of the kernel rather than of our maths.
        let accounted = metrics.inUse + metrics.reclaimable + metrics.free
        #expect(accounted < installed)
        #expect(Double(installed - accounted) / Double(installed) < 0.015)
    }

    @Test("keeps inactive pages visible as reclaimable memory")
    func reportsReclaimableMemory() {
        #expect(metrics.reclaimable == 47_728_082_944)
        #expect(Format.gibibytes(metrics.reclaimable) == "44")
    }

    @Test("reports the in-use fraction")
    func inUseFraction() {
        #expect(abs(metrics.inUseFraction - 0.545) < 0.001)
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
        #expect(metrics.inUseFraction == 0)
        #expect(metrics.swapFraction == 0)
    }
}
