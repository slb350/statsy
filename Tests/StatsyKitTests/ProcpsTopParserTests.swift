import Testing
@testable import StatsyKit

/// Rows copied from `LC_ALL=C top -b -d 2 -w 512 -e k` on strix and homelab-1,
/// with procps' right-aligned padding intact.
private enum Fixture {
    static let header =
        "    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND"
    static let systemd =
        "      1 root      20   0   27148  17296  10616 S   0.0   0.0   9:02.81 systemd"
    static let kthread =
        "      4 root       0 -20       0      0      0 I   0.0   0.0   0:00.00 kworker/R-rcu_gp"
    /// RES too wide for its column, so procps scales it to gibibytes.
    static let llama =
        " 216368 steve     20   0  224.9g   6.5g   3.0g S   0.0   5.2 133:54.97 llama-server"
    /// A numeric user, a scaled VIRT, and procps' compressed TIME+ form.
    static let alloy =
        "1477085 root      20   0 9968.6m 393488  76000 S   9.1   1.2     13,05 alloy"
    static let rustc =
        "3575241 ci-tatt+  20   0  805632 336244 201912 S 109.1   0.3   0:02.11 rustc"
    /// A thread-group name with a space in it, which must survive whole.
    static let spaced =
        "   2636 cabinet+  20   0  150408  57084  22856 S   0.4   0.0   2:15.90 Web Content"
    static let summary = [
        "top - 21:55:19 up 10 days, 11:36,  2 users,  load average: 0.00, 0.02, 0.08",
        "Tasks: 444 total,   1 running, 443 sleeping,   0 stopped,   0 zombie",
        "%Cpu(s):  0.0 us,  0.0 sy,  0.0 ni,100.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st ",
        "MiB Mem : 127939.7 total,  14084.4 free, 100128.6 used,  17738.2 buff/cache     ",
        "MiB Swap:   8192.0 total,   8192.0 free,      0.0 used.  27811.1 avail Mem ",
        ""
    ]
}

@Suite("ProcpsTopParser")
struct ProcpsTopParserTests {
    private let layout = ProcpsTopParser.layout(header: Fixture.header)!

    @Test("finds columns by name in a right-aligned header")
    func locatesColumns() {
        #expect(layout.cpu == 8)
        #expect(layout.resident == 5)
        #expect(layout.count == 12)
    }

    @Test("rejects the summary lines and rows")
    func rejectsNonHeader() {
        for line in Fixture.summary + [Fixture.systemd] {
            #expect(ProcpsTopParser.layout(header: line) == nil)
        }
    }

    @Test("parses a row, reading RES as kibibytes")
    func parsesRow() throws {
        let sample = try #require(ProcpsTopParser.row(Fixture.systemd, layout: layout))
        #expect(sample.id == 1)
        #expect(sample.name == "systemd")
        #expect(sample.cpu == 0)
        #expect(sample.memory == 17296 * 1024)
    }

    @Test("reads a scaled RES in the unit its suffix names")
    func scaledResident() throws {
        let sample = try #require(ProcpsTopParser.row(Fixture.llama, layout: layout))
        #expect(sample.name == "llama-server")
        #expect(sample.memory == UInt64(6.5 * 1024 * 1024 * 1024))
    }

    @Test("reads more than one core's worth of CPU")
    func multicoreCPU() throws {
        let sample = try #require(ProcpsTopParser.row(Fixture.rustc, layout: layout))
        #expect(abs(sample.cpu - 109.1) < 0.001)
        #expect(sample.memory == 336_244 * 1024)
    }

    @Test("ignores columns it does not read, whatever their form")
    func unreadColumns() throws {
        let sample = try #require(ProcpsTopParser.row(Fixture.alloy, layout: layout))
        #expect(sample.id == 1_477_085)
        #expect(abs(sample.cpu - 9.1) < 0.001)
        #expect(sample.memory == 393_488 * 1024)
    }

    @Test("keeps a command name with a space in it whole")
    func spacedCommand() throws {
        let sample = try #require(ProcpsTopParser.row(Fixture.spaced, layout: layout))
        #expect(sample.name == "Web Content")
        #expect(sample.id == 2636)
    }

    @Test("parses kernel threads, which hold no resident memory")
    func kernelThread() throws {
        let sample = try #require(ProcpsTopParser.row(Fixture.kthread, layout: layout))
        #expect(sample.name == "kworker/R-rcu_gp")
        #expect(sample.memory == 0)
    }

    @Test("rejects a row with too few fields")
    func truncatedRow() {
        #expect(ProcpsTopParser.row("  1234 root  20", layout: layout) == nil)
        #expect(ProcpsTopParser.row("", layout: layout) == nil)
    }

    @Test("reads memory tokens in every unit procps scales to")
    func memoryTokens() {
        #expect(ProcpsTopParser.residentBytes("17296") == 17296 * 1024)
        #expect(ProcpsTopParser.residentBytes("2.5m") == UInt64(2.5 * 1024 * 1024))
        #expect(ProcpsTopParser.residentBytes("6.5g") == UInt64(6.5 * 1024 * 1024 * 1024))
        #expect(ProcpsTopParser.residentBytes("1.2t") == UInt64(1.2 * 1024 * 1024 * 1024 * 1024))
        #expect(ProcpsTopParser.residentBytes("") == nil)
        #expect(ProcpsTopParser.residentBytes("-") == nil)
    }
}

@Suite("TopStreamParser, procps")
struct ProcpsStreamTests {
    private func feed(_ parser: inout TopStreamParser, _ lines: [String]) -> [[ProcessSample]] {
        lines.compactMap { parser.consume($0) }
    }

    /// Two iterations as `top -b` prints them: summary, blank, header, rows,
    /// then a blank before the next summary.
    private var iterations: [String] {
        Fixture.summary + [Fixture.header, Fixture.systemd, Fixture.llama, ""]
            + Fixture.summary + [Fixture.header, Fixture.rustc, Fixture.alloy, ""]
    }

    @Test("discards the first iteration, as on macOS")
    func skipsFirstBlock() {
        var parser = TopStreamParser(dialect: .procps)
        let blocks = feed(&parser, iterations)
        #expect(blocks.count == 1)
        #expect(blocks[0].map(\.name) == ["rustc", "alloy"])
    }

    @Test("emits every iteration when asked to")
    func emitsAllBlocks() {
        var parser = TopStreamParser(dialect: .procps, skipFirstBlock: false)
        let blocks = feed(&parser, iterations)
        #expect(blocks.map { $0.map(\.name) } == [["systemd", "llama-server"], ["rustc", "alloy"]])
    }

    @Test("does not read summary lines as rows")
    func summaryIsNotRows() {
        var parser = TopStreamParser(dialect: .procps, skipFirstBlock: false)
        let blocks = feed(&parser, iterations + Fixture.summary)
        #expect(blocks.flatMap { $0 }.count == 4)
    }

    @Test("the darwin dialect does not mistake a procps header for its own")
    func dialectsStayApart() {
        var parser = TopStreamParser(skipFirstBlock: false)
        #expect(feed(&parser, iterations).isEmpty)
    }
}
