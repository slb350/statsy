import Testing
@testable import StatsyKit

/// Fixtures copied verbatim from `top -l 2 -s 1 -stats pid,command,cpu,mem,threads`
/// on this machine, including its exact column padding.
private enum Fixture {
    static let header = "PID    COMMAND          %CPU MEM    #TH    "
    static let safari = "79086  Safari           88.4 7878M+ 16/1   "
    static let window = "404    WindowServer     40.6 2983M+ 28/1   "
    static let kernel = "0      kernel_task      10.1 20G+   1027/18"
    static let chrome = "37538  Google Chrome He 8.7  485M-  29     "
    static let tiny   = "19415  XprotectService  16.9 3616K- 5      "
}

@Suite("TopParser")
struct TopParserTests {
    private let layout = TopParser.layout(header: Fixture.header)!

    @Test("locates columns from the header line")
    func locatesColumns() {
        let layout = TopParser.layout(header: Fixture.header)
        #expect(layout?.ranges["PID"]?.lowerBound == 0)
        #expect(layout?.ranges["COMMAND"]?.lowerBound == 7)
        #expect(layout?.ranges["%CPU"]?.lowerBound == 24)
        #expect(layout?.ranges["MEM"]?.lowerBound == 29)
        // Each column ends where the next one begins.
        #expect(layout?.ranges["PID"]?.upperBound == 7)
        #expect(layout?.ranges["COMMAND"]?.upperBound == 24)
    }

    @Test("rejects lines that are not a header")
    func rejectsNonHeader() {
        #expect(TopParser.layout(header: Fixture.safari) == nil)
        #expect(TopParser.layout(header: "Processes: 1058 total, 4 running") == nil)
    }

    @Test("parses a straightforward row")
    func parsesRow() throws {
        let sample = try #require(TopParser.row(Fixture.safari, layout: layout))
        #expect(sample.id == 79086)
        #expect(sample.name == "Safari")
        #expect(abs(sample.cpu - 88.4) < 0.001)
        #expect(sample.memory == UInt64(8_260_681_728))
    }

    @Test("keeps command names that contain spaces intact")
    func handlesSpacedCommandNames() throws {
        // Whitespace splitting would shred this into "Google" / "Chrome" / "He".
        let sample = try #require(TopParser.row(Fixture.chrome, layout: layout))
        #expect(sample.name == "Google Chrome He")
        #expect(sample.id == 37538)
        #expect(abs(sample.cpu - 8.7) < 0.001)
    }

    @Test("parses the kernel row, which has pid 0 and gibibyte memory")
    func parsesKernelRow() throws {
        let sample = try #require(TopParser.row(Fixture.kernel, layout: layout))
        #expect(sample.id == 0)
        #expect(sample.name == "kernel_task")
        #expect(sample.memory == UInt64(21_474_836_480))
    }

    @Test("converts memory tokens across units, ignoring trend markers")
    func convertsMemoryTokens() {
        #expect(TopParser.memoryBytes("3616K") == UInt64(3_702_784))
        #expect(TopParser.memoryBytes("485M-") == UInt64(508_559_360))
        #expect(TopParser.memoryBytes("20G+") == UInt64(21_474_836_480))
        #expect(TopParser.memoryBytes("512") == UInt64(512))
        #expect(TopParser.memoryBytes("") == nil)
        #expect(TopParser.memoryBytes("banana") == nil)
    }

    @Test("ignores rows that do not parse rather than failing the batch")
    func ignoresJunkRows() throws {
        #expect(TopParser.row("", layout: layout) == nil)
        #expect(TopParser.row("Processes: 1058 total", layout: layout) == nil)
    }
}

@Suite("TopStreamParser")
struct TopStreamParserTests {
    private func feed(_ parser: inout TopStreamParser, _ lines: [String]) -> [[ProcessSample]] {
        lines.compactMap { parser.consume($0) }
    }

    @Test("discards the first block, whose CPU figures are lifetime averages")
    func discardsFirstBlock() {
        // `top`'s opening sample reports average-since-launch CPU, exactly the
        // way `ps` does. Showing it would make the first frame wrong.
        var parser = TopStreamParser(skipFirstBlock: true)
        let blocks = feed(&parser, [
            "Processes: 1058 total", Fixture.header, Fixture.safari, Fixture.window, "",
            "Processes: 1058 total", Fixture.header, Fixture.kernel, Fixture.tiny, ""
        ])
        #expect(blocks.count == 1)
        #expect(blocks.first?.map(\.name) == ["kernel_task", "XprotectService"])
    }

    @Test("emits every block when told not to skip")
    func emitsAllBlocks() {
        var parser = TopStreamParser(skipFirstBlock: false)
        let blocks = feed(&parser, [
            Fixture.header, Fixture.safari, "",
            Fixture.header, Fixture.kernel, ""
        ])
        #expect(blocks.count == 2)
        #expect(blocks[0].map(\.name) == ["Safari"])
        #expect(blocks[1].map(\.name) == ["kernel_task"])
    }

    @Test("treats a new header as the end of the previous block")
    func headerEndsPreviousBlock() {
        var parser = TopStreamParser(skipFirstBlock: false)
        let blocks = feed(&parser, [
            Fixture.header, Fixture.safari, Fixture.window,
            Fixture.header, Fixture.kernel
        ])
        #expect(blocks.count == 1)
        #expect(blocks[0].count == 2)
    }
}

@Suite("ProcessTable")
struct ProcessTableTests {
    private let samples = [
        ProcessSample(id: 1, name: "low-cpu-big-mem", cpu: 1, memory: 27_000_000_000),
        ProcessSample(id: 2, name: "high-cpu-small-mem", cpu: 88.4, memory: 1_000_000),
        ProcessSample(id: 3, name: "middling", cpu: 40.6, memory: 3_000_000_000)
    ]

    @Test("ranks the same samples independently by cpu and by memory")
    func ranksIndependently() {
        let table = ProcessTable.ranked(samples, limit: 2)
        #expect(table.byCPU.map(\.name) == ["high-cpu-small-mem", "middling"])
        #expect(table.byMemory.map(\.name) == ["low-cpu-big-mem", "middling"])
    }

    @Test("honours the limit")
    func honoursLimit() {
        #expect(ProcessTable.ranked(samples, limit: 1).byCPU.count == 1)
        #expect(ProcessTable.ranked(samples, limit: 99).byCPU.count == 3)
    }
}
