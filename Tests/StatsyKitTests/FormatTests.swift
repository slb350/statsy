import Testing
@testable import StatsyKit

@Suite("Format")
struct FormatTests {
    @Test("renders bytes in binary units")
    func binaryUnits() {
        #expect(Format.binary(0) == "0 B")
        #expect(Format.binary(512) == "512 B")
        #expect(Format.binary(1024) == "1.0 KiB")
        #expect(Format.binary(1_099_511_627_776) == "1.0 TiB")
    }

    @Test("renders the boot volume capacity the way the panel shows it")
    func realCapacity() {
        // 1.8 TiB volume with 535 GiB free, as measured on this machine.
        #expect(Format.binary(574_355_505_152) == "534.9 GiB")
    }

    @Test("renders whole gibibytes for the memory readout")
    func gibibytes() {
        // Measured "Memory Used" on this machine: top reported 114G.
        #expect(Format.gibibytes(122_605_912_064) == "114")
        #expect(Format.gibibytes(137_438_953_472) == "128")
    }

    @Test("scales throughput to a sensible unit")
    func rates() {
        #expect(Format.rate(0) == "0 B/s")
        #expect(Format.rate(45056) == "44.0 KB/s")
        #expect(Format.rate(26_863_534) == "25.6 MB/s")
    }

    @Test("renders fractions as percentage numbers")
    func percentages() {
        #expect(Format.percent(0.307) == "30.7")
        #expect(Format.percent(0.867, decimals: 1) == "86.7")
        #expect(Format.percent(0.71, decimals: 0) == "71")
    }
}
